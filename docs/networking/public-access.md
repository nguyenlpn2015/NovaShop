# Public Access Architecture

This document extends Deployment Target B with phased public HTTP and HTTPS
access.
It does not change the GitOps reconciliation model, Helm chart, or application
runtime.

## Request Path

```text
Internet user
    |
    | HTTPS request for *.novashop.smartdev.vn
    v
Cloudflare authoritative DNS and optional reverse proxy
    |
    | DNS Only: origin public IPv4 address
    | Proxied: Cloudflare anycast address, then HTTPS to origin
    v
Public IPv4 address
    |
    v
FortiGate WAN interface
    |
    | VIP / destination NAT
    | TCP 80  -> 10.10.1.45:80
    | TCP 443 -> 10.10.1.45:443
    v
FortiGate inbound firewall policy
    |
    v
Ubuntu Server 22.04 at 10.10.1.45
    |
    v
k3s ServiceLB -> Traefik entrypoints web/websecure
    |
    v
Kubernetes Ingress host rules
    |
    +--> NovaShop frontend Service -> frontend Pods
    |
    `--> NovaShop backend Service  -> backend Pods
```

The public IP, FortiGate VIP, and DNS values are environment-specific
infrastructure data. Do not commit the actual public IP, private keys, API
tokens, or firewall backups to this repository.

## Public Hostnames

| Environment | Frontend | Backend |
|-------------|----------|---------|
| Development | `dev.novashop.smartdev.vn` | `api.dev.novashop.smartdev.vn` |
| Staging | `staging.novashop.smartdev.vn` | `api.staging.novashop.smartdev.vn` |
| Production | `novashop.smartdev.vn` | `api.novashop.smartdev.vn` |

Development should remain restricted to trusted source networks unless public
testing is explicitly required. Staging should be access-controlled. Production
is the only environment intended for general Internet access.

## Trust Boundaries

1. Cloudflare controls authoritative DNS and, when proxying is enabled, the
   public HTTP security edge.
2. FortiGate is the network enforcement point. It permits only the required
   destination NAT and inbound services.
3. Ubuntu is the origin host. It does not expose PostgreSQL, Redis, the
   Kubernetes API, SSH, or Argo CD to the Internet.
4. Traefik terminates origin TLS and routes only declared hostnames.
5. Kubernetes Services and Pods remain private cluster resources.

## Implementation Sequence

1. Reserve and document the public IPv4 address without committing it.
2. Confirm that the ISP permits inbound TCP 80 and 443 and that no upstream
   carrier-grade NAT prevents port forwarding.
3. Configure FortiGate VIP mappings and the least-privilege inbound policy.
4. Confirm Traefik is listening on `10.10.1.45:80` and `10.10.1.45:443`.
5. Merge the HTTP-only GitOps phase and run the normal Linux bootstrap.
6. Create DNS records with proxy disabled and validate HTTP end to end.
7. Confirm HTTP frontend and backend health before introducing TLS.
8. Open a separate GitOps pull request that changes the Ubuntu overlay from
   `phases/http` to `phases/tls`.
9. Validate the Let's Encrypt staging issuer, certificates, HTTPS routing, and
   rollback path.
10. Promote Certificate resources to the production issuer through another
    reviewed GitOps change.
11. Enable HTTP-to-HTTPS redirect, HSTS, Cloudflare proxying, and Full (strict)
    only after production certificates are healthy.

The Linux bootstrap does not install cert-manager. This separation prevents an
ACME or Certificate failure from obscuring HTTP routing validation.

## Origin Validation

Run these checks from outside the private network. Replace `<PUBLIC_IPV4>` with
the FortiGate public address:

```bash
curl --resolve novashop.smartdev.vn:80:<PUBLIC_IPV4> \
  --head http://novashop.smartdev.vn

curl --resolve novashop.smartdev.vn:443:<PUBLIC_IPV4> \
  --head https://novashop.smartdev.vn

curl --resolve api.novashop.smartdev.vn:443:<PUBLIC_IPV4> \
  https://api.novashop.smartdev.vn/health
```

When a Cloudflare Origin CA certificate is used, direct HTTPS clients will not
trust the certificate. Perform the direct origin test with the Origin CA root
installed in a controlled test environment, then validate public trust through
the proxied hostname.

## Operational Boundaries

- Do not publish TCP 22, 5432, 6379, 6443, or Argo CD service ports.
- Do not enable HSTS until HTTPS is proven stable and rollback is tested.
- Do not trust client-supplied forwarding headers from arbitrary sources.
- If only Cloudflare-proxied access is supported, restrict origin ports 80 and
  443 to the current Cloudflare IP ranges plus explicit operator test sources.
- Preserve an authenticated management path that does not depend on public DNS.

## Related Documentation

- [Cloudflare DNS](cloudflare.md)
- [FortiGate Edge](fortigate.md)
- [Traefik Edge Routing](traefik.md)
- [TLS Strategy](../security/tls.md)
- [Platform Hardening](../security/hardening.md)
- [Public Deployment Checklist](../operations/public-deployment-checklist.md)
- [Edge Architecture](../../diagrams/EDGE_ARCHITECTURE.md)

## References

- [Cloudflare proxy status](https://developers.cloudflare.com/dns/proxy-status/)
- [Cloudflare Full (strict) mode](https://developers.cloudflare.com/ssl/origin-configuration/ssl-modes/full-strict/)
- [Traefik Kubernetes Ingress provider](https://doc.traefik.io/traefik/providers/kubernetes-ingress/)
