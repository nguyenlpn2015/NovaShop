# TLS Certificate Lifecycle

Certificate operations must be repeatable, monitored, and independent of
application releases. Private keys and issued certificate material must never
be committed to Git.

## Lifecycle

```text
Inventory
  -> Request or issue
  -> Validate identity and SANs
  -> Store securely
  -> Create or rotate Kubernetes TLS Secret
  -> Validate Traefik
  -> Monitor expiry
  -> Renew before threshold
  -> Revoke and replace when compromised
  -> Retire securely
```

Maintain an inventory containing:

- issuer and certificate profile;
- covered hostnames;
- Kubernetes namespace and Secret name;
- issue, activation, and expiration timestamps;
- renewal owner and procedure;
- monitoring destination;
- revocation procedure.

Do not store private keys, API tokens, or Secret exports in the inventory.

## Automated Renewal

After the reviewed TLS phase is activated, cert-manager owns routine issuance
and renewal. It is not installed by the default bootstrap. Operators monitor
`Certificate`, `CertificateRequest`, `Order`, and `Challenge` conditions and
verify the served certificate after every renewal.

```bash
kubectl get certificates --all-namespaces
kubectl get certificaterequests,orders,challenges --all-namespaces
```

## Break-glass Manual Renewal

Use this procedure only if cert-manager recovery cannot complete before the
certificate expires.

1. Issue the replacement certificate without modifying the active Secret.
2. Verify the full chain, hostname set, key match, and expiration.
3. Back up the current Secret to approved encrypted storage.
4. Update the stable Secret name with the replacement material.
5. Confirm Traefik serves the new certificate.
6. Validate HTTPS through the origin and Cloudflare.
7. Revoke the replaced certificate if compromise, supersession policy, or the
   issuer requires it.

Validate local files before creating the Secret:

```bash
openssl x509 -in tls.crt -noout -subject -issuer -dates -ext subjectAltName

openssl x509 -in tls.crt -pubkey -noout \
  | openssl sha256

openssl pkey -in tls.key -pubout \
  | openssl sha256
```

The two public-key hashes must match.

Rotate a Secret without printing its contents:

```bash
kubectl create secret tls <TLS_SECRET_NAME> \
  --namespace <NAMESPACE> \
  --cert=tls.crt \
  --key=tls.key \
  --dry-run=client \
  --output=yaml \
  | kubectl apply --server-side \
      --field-manager=novashop-tls-operator \
      --filename=-
```

Remove local certificate working files securely according to the host and
storage policy after successful installation.

## Validation

Inspect the Secret certificate without exposing the private key:

```bash
kubectl get secret <TLS_SECRET_NAME> \
  --namespace <NAMESPACE> \
  --output=jsonpath='{.data.tls\.crt}' \
  | base64 --decode \
  | openssl x509 -noout -subject -issuer -dates -ext subjectAltName
```

Validate the served origin certificate:

```bash
openssl s_client \
  -connect <PUBLIC_IPV4>:443 \
  -servername novashop.smartdev.vn \
  -showcerts </dev/null
```

Validate the public edge:

```bash
curl --fail --show-error --head https://novashop.smartdev.vn
curl --fail --show-error https://api.novashop.smartdev.vn/health
```

For Cloudflare-proxied records, test both the public Cloudflare path and a
controlled direct-origin path.

## Renewal Timing

- Renew automatically where the issuer supports it.
- Alert at 30, 14, and 7 days before expiry for manually operated
  certificates.
- Complete manual renewal before the 14-day threshold.
- Do not assume a fixed certificate lifetime; evaluate the actual `notAfter`
  value and current issuer policy.
- Run a renewal rehearsal before the first production expiration.

Let's Encrypt currently uses 90 days as its default lifetime and has published
a transition toward shorter lifetimes. Automation is therefore an operational
requirement, not an optimization.

## Rollback

If the new certificate fails:

1. restore the prior Secret from approved encrypted storage;
2. verify Traefik serves the prior certificate;
3. disable DNS or edge changes introduced with the rotation;
4. confirm HTTP health and HTTPS trust;
5. document the failure without recording private material.

Do not roll back to an expired, revoked, or compromised certificate.

## Monitoring

Monitor:

- certificate expiry and hostname coverage;
- TLS handshake failures;
- Cloudflare 525 and 526 responses;
- Traefik certificate selection errors;
- unexpected issuer or fingerprint changes;
- renewal job success when automation is introduced.

Route alerts to an owned channel with an escalation path. A dashboard without
actionable alerts is insufficient.

## References

- [Let's Encrypt certificate lifetimes](https://letsencrypt.org/docs/cert-lifetimes/)
- [Cloudflare Origin CA](https://developers.cloudflare.com/ssl/origin-configuration/origin-ca/)
- [Future cert-manager Integration](../future/cert-manager.md)
