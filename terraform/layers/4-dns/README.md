# Layer 4 — DNS

Cloudflare A records for the four public names.

> **Phase 1: foundation only.** No resources are declared. `terraform plan` produces an
> empty plan and evaluates the outputs from variables alone.

## Why this layer matters more than four records suggest

DNS is not only how visitors arrive. It is a hard dependency of TLS renewal:

```
public DNS resolves here → port 80 reaches this node
  → Traefik routes /.well-known/acme-challenge/ → HTTP-01 succeeds → certificate renews
```

Every link is required, and **nothing fails immediately** when one breaks — the existing
certificate keeps working. The failure appears at renewal, roughly 30 days before expiry,
which is precisely why `CertificateExpiring` fires at 21 days.

Before this layer, those four records existed only in the Cloudflare dashboard. They were
the least reproducible part of the platform and the one with the longest gap between a
mistake and its symptom.

## The records

All four resolve to the same address; separation is by `Host` header at Traefik.

| Name | Environment |
|---|---|
| `novashop` | production frontend |
| `api.novashop` | production backend |
| `staging.novashop` | staging |
| `dev.novashop` | development |

## `proxied` is locked to false

Enabling Cloudflare's proxy terminates TLS at Cloudflare and can stop the
`/.well-known/acme-challenge/` path reaching this origin unmodified. HTTP-01 validation
then fails **silently**, and the symptom arrives up to sixty days later.

So `proxied` is a single layer-wide variable with a validation rule that rejects `true`,
rather than a per-record flag. Turning the proxy on is a legitimate future change — it
would add caching and a WAF — but it requires moving the `ClusterIssuer` to DNS-01 first.
Forcing that to be a deliberate edit here, not a copied line in a record definition, is the
whole point of the design.

## Verifying intent against reality

```sh
terraform output -json fqdns | jq -r '.[]' | while read -r n; do
  printf '%s -> %s\n' "$n" "$(dig +short "$n")"
done
```

And the chain that certificates depend on:

```sh
for n in $(terraform output -json acme_reachable_fqdns | jq -r '.[]'); do
  curl -so /dev/null -w "%{http_code} $n\n" "http://$n/.well-known/acme-challenge/probe"
done
```

**404 is the healthy answer.** It proves the request reached Traefik and was routed. A
timeout means DNS or DNAT; connection refused means the node is reachable and nothing is
listening.

## Import, not create

The records exist. Recreating one is an outage *and* a certificate renewal failure.

Later phases land `import` blocks, `prevent_destroy = true` on every record, and the
acceptance gate is a **completely empty plan**.

```hcl
import {
  to = cloudflare_record.this["novashop"]
  id = "${var.cloudflare_zone_id}/<record-id>"
}
```

Record IDs come from:

```sh
curl -s -H "Authorization: Bearer $TF_VAR_cloudflare_api_token" \
  "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" | jq -r '.result[] | "\(.name) \(.id)"'
```

## Configuration

```sh
export TF_VAR_cloudflare_api_token=...     # Zone:DNS:Edit on this zone only
cp ../../examples/4-dns.tfvars.example terraform.tfvars

cp ../../examples/backend-local-override.tf.example backend_override.tf
terraform init
terraform plan
```
