# TLS Strategy

TLS protects both the browser-to-edge and edge-to-origin paths. Cloudflare Full
(strict) mode is the minimum acceptable proxied production configuration.

## Options

| Option | Public trust | Typical lifetime | Automation | Direct-origin browser access | Best fit |
|--------|--------------|------------------|------------|------------------------------|----------|
| Let's Encrypt | Publicly trusted | Issuer-controlled; currently 90-day default | Strong ACME ecosystem | Yes | Development, labs, public production |
| Cloudflare Origin CA | Trusted by Cloudflare, not public browsers | Selected at issuance | Cloudflare/API workflow | No | Proxy-only production lab origin |
| Commercial wildcard | Publicly trusted | CA and policy dependent | Varies by provider | Yes | Enterprise policy or support requirements |

Never commit a private key or Kubernetes TLS Secret manifest containing real
certificate data.

## Let's Encrypt

### Let's Encrypt Advantages

- publicly trusted;
- no certificate fee;
- supports ACME automation;
- direct-origin validation remains possible;
- avoids dependence on a single reverse proxy.

### Let's Encrypt Trade-offs

- reliable renewal automation is mandatory;
- HTTP-01 requires reachable port 80; DNS-01 requires scoped DNS API access;
- issuance rate limits and DNS propagation must be considered;
- wildcard certificates require DNS-01.

## Cloudflare Origin CA

### Origin CA Advantages

- designed for encrypted Cloudflare-to-origin traffic;
- compatible with Cloudflare Full (strict);
- long validity options reduce manual rotation frequency;
- useful when direct origin access is intentionally blocked.

### Origin CA Trade-offs

- not trusted by browsers or generic direct clients;
- an emergency switch to DNS Only produces trust failures;
- Cloudflare does not provide expiration notifications for Origin CA
  certificates, so independent monitoring is required;
- creates operational dependence on the Cloudflare proxy path.

## Commercial Wildcard Certificate

### Commercial Wildcard Advantages

- broad public trust and vendor support;
- can cover multiple NovaShop subdomains;
- may satisfy enterprise procurement, warranty, or support requirements;
- supports direct-origin access.

### Commercial Wildcard Trade-offs

- cost and procurement lifecycle;
- a shared wildcard key increases blast radius;
- automation capabilities vary;
- wildcard coverage does not include unrelated deeper label levels unless the
  SAN set explicitly covers them.

Prefer narrowly scoped SAN certificates over a wildcard when lifecycle tooling
can manage them reliably.

## Recommendations

### Development

Use a publicly trusted Let's Encrypt certificate when the environment is
publicly reachable. Use a private development CA only for closed networks with
managed client trust. Keep development private by default.

### Production Lab

Use a Cloudflare Origin CA certificate when:

- every public record is permanently proxied;
- FortiGate permits origin web traffic only from Cloudflare networks and
  controlled operator sources;
- Full (strict) mode is enabled;
- expiry monitoring and a Cloudflare-independent recovery plan exist.

Use Let's Encrypt instead when direct-origin browser access, DNS Only rollback,
or provider portability is a priority. For this portfolio, Let's Encrypt is the
most reproducible default; Cloudflare Origin CA is a valid documented
proxy-only variant.

### Enterprise

Use an organization-approved public CA or managed certificate service. Select
wildcard or SAN scope according to key isolation, compliance, support,
automation, and incident-response requirements. Do not choose a commercial
certificate solely for perceived cryptographic strength.

## TLS Policy

- Support TLS 1.2 and TLS 1.3 according to client requirements.
- Disable obsolete protocol versions and weak cipher suites.
- Use Full (strict) between Cloudflare and Traefik.
- Ensure certificate SANs exactly cover the Ingress hosts.
- Enable HSTS only after HTTPS is continuously healthy.
- Rotate keys during renewal and immediately after suspected compromise.
- Monitor certificate expiry and handshake failures.

## References

- [Cloudflare Full (strict)](https://developers.cloudflare.com/ssl/origin-configuration/ssl-modes/full-strict/)
- [Cloudflare Origin CA](https://developers.cloudflare.com/ssl/origin-configuration/origin-ca/)
- [Let's Encrypt certificate lifetimes](https://letsencrypt.org/docs/cert-lifetimes/)
- [TLS Renewal Runbook](../networking/ssl-renewal.md)
