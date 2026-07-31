# Cloudflare DNS and Proxy

Cloudflare is the authoritative DNS provider for `smartdev.vn`. Its HTTP proxy
is an optional edge layer in front of the FortiGate public IP.

## DNS Record Plan

Replace `<PUBLIC_IPV4>` with the FortiGate WAN address.

| Type | Name | Target | Initial proxy | Steady-state proxy | TTL |
|------|------|--------|---------------|--------------------|-----|
| A | `dev.novashop` | `<PUBLIC_IPV4>` | DNS Only | DNS Only or Proxied | 300 during rollout |
| CNAME | `api.dev.novashop` | `dev.novashop.smartdev.vn` | DNS Only | DNS Only or Proxied | 300 during rollout |
| A | `staging.novashop` | `<PUBLIC_IPV4>` | DNS Only | Proxied | 300 during rollout |
| CNAME | `api.staging.novashop` | `staging.novashop.smartdev.vn` | DNS Only | Proxied | 300 during rollout |
| A | `novashop` | `<PUBLIC_IPV4>` | DNS Only | Proxied | 300 during rollout |
| CNAME | `api.novashop` | `novashop.smartdev.vn` | DNS Only | Proxied | 300 during rollout |

Cloudflare proxied records use the provider-managed automatic TTL. DNS-only
records may use a configurable TTL. Start with 300 seconds, then raise it after
the public path is stable if operational requirements favor fewer DNS queries.

Do not create a public `A`, `AAAA`, or `CNAME` record for PostgreSQL, Redis,
Argo CD, SSH, or the Kubernetes API.

## A Records and CNAME Records

- Use an `A` record for the canonical frontend hostname that maps to the public
  IPv4 address.
- Use a `CNAME` for the API hostname when it follows the same edge path.
- Use separate `A` records instead if the frontend and API must be failed over
  or migrated independently.
- Do not publish an `AAAA` record unless the entire IPv6 path, firewall policy,
  origin listener, and monitoring are operational.

## DNS Only

DNS Only returns the origin public IP to clients. Use it:

- during initial VIP, TLS, and Traefik validation;
- for controlled troubleshooting that must bypass the Cloudflare proxy;
- for protocols Cloudflare's HTTP proxy does not support;
- when direct public certificate validation is required.

DNS Only exposes the origin IP and bypasses Cloudflare WAF, bot controls,
rate-limiting rules, caching, and HTTP analytics. It is not the recommended
steady state for public production web traffic.

## Cloudflare Proxy

Proxy public frontend and API records after origin validation. Proxied traffic
resolves to Cloudflare anycast addresses and reaches the origin through
Cloudflare.

Recommended production settings:

- Proxy status: Proxied.
- SSL/TLS encryption mode: Full (strict).
- Always Use HTTPS: enable only after origin HTTPS validation.
- Minimum TLS version: choose according to client compatibility policy.
- Cache: bypass dynamic API responses; cache only explicitly safe content.
- WAF and bot controls: begin in log or managed mode, review, then enforce.
- Origin firewall: allow current Cloudflare source ranges and explicit operator
  test sources; deny other public sources to TCP 80 and 443.

Do not use Flexible encryption. It leaves the Cloudflare-to-origin hop
unencrypted and can cause redirect loops when the origin enforces HTTPS.

## Environment Policy

| Environment | Recommended exposure | Proxy policy | Additional control |
|-------------|----------------------|--------------|--------------------|
| Development | Private or temporary public | DNS Only during tests; Proxied if public | Source allowlist or Cloudflare Access |
| Staging | Restricted public | Proxied | Identity-aware access and no indexing |
| Production | Public | Proxied | Full (strict), WAF, bot controls, monitoring |

## Verification

```bash
dig +short dev.novashop.smartdev.vn A
dig +short staging.novashop.smartdev.vn A
dig +short novashop.smartdev.vn A

curl --head https://novashop.smartdev.vn
curl --silent --show-error https://api.novashop.smartdev.vn/health
```

When proxying is enabled, DNS should return Cloudflare addresses rather than
the configured origin address. Verify response headers, but do not treat any
single header as proof of security policy enforcement.

## Change and Rollback

1. Record the current DNS values, proxy state, and TLS mode.
2. Change one environment at a time.
3. Wait at least the effective TTL before declaring propagation complete.
4. Validate from multiple external resolvers and networks.
5. To bypass Cloudflare during an incident, confirm that the origin presents a
   publicly trusted certificate and can safely accept direct traffic before
   switching to DNS Only.

Cloudflare Origin CA certificates are not browser-trusted for direct access.
Do not switch an Origin CA-backed hostname to DNS Only as an unplanned
workaround.

## References

- [Cloudflare DNS record types](https://developers.cloudflare.com/dns/manage-dns-records/reference/dns-record-types/)
- [Cloudflare proxy status](https://developers.cloudflare.com/dns/proxy-status/)
- [Cloudflare proxy use cases](https://developers.cloudflare.com/dns/proxy-status/use-cases/)
- [Protect the origin server](https://developers.cloudflare.com/fundamentals/security/protect-your-origin-server/)
- [Cloudflare IP ranges](https://www.cloudflare.com/ips/)
