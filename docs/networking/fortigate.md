# FortiGate Edge Configuration

FortiGate provides the destination NAT and inbound network policy between the
public IP and NovaShop Deployment Target B at `10.10.1.45`.

The exact menus and CLI syntax vary by FortiOS release. Treat the object model
below as the required outcome and validate it against the installed release.

## Required Flow

| External listener | Destination NAT | Purpose |
|-------------------|-----------------|---------|
| `<PUBLIC_IPV4>:80/TCP` | `10.10.1.45:80/TCP` | ACME HTTP validation and HTTP-to-HTTPS redirect |
| `<PUBLIC_IPV4>:443/TCP` | `10.10.1.45:443/TCP` | NovaShop HTTPS |

No other NovaShop platform port is part of the public VIP.

## Virtual IP Objects

Create either:

- one VIP that maps the public address to `10.10.1.45` and restricts allowed
  services in the firewall policy; or
- two port-forwarding VIPs, one for TCP 80 and one for TCP 443.

Suggested object names:

```text
vip-novashop-http
vip-novashop-https
vipgrp-novashop-web
```

Required properties:

- incoming interface: the Internet-facing interface;
- external address: `<PUBLIC_IPV4>`;
- mapped address: `10.10.1.45`;
- protocol: TCP;
- external and mapped ports: 80-to-80 and 443-to-443;
- optional source filter: Cloudflare networks when the hostnames are proxy-only.

Do not configure source NAT on the inbound policy unless a documented routing
constraint requires it. Preserving source information supports audit,
rate-limiting, and incident investigation. Confirm asymmetric routing is not
introduced.

## Firewall Policy

Create a dedicated WAN-to-platform policy:

| Property | Value |
|----------|-------|
| Incoming interface | Internet-facing interface |
| Outgoing interface | Interface or VLAN containing `10.10.1.45` |
| Source | Cloudflare ranges for proxy-only operation, otherwise `all` during controlled validation |
| Destination | NovaShop VIP group |
| Service | HTTP and HTTPS only |
| Schedule | Always |
| Action | Accept |
| NAT | Disabled for destination-NAT policy unless the network design requires SNAT |
| Logging | Log accepted sessions and security events |

Place this rule above broad deny rules and below any explicit emergency block
rules. Do not reuse a general-purpose inbound policy.

## Security Recommendations

- Never include SSH, PostgreSQL, Redis, Kubernetes API, Argo CD, or node
  management ports in the public VIP.
- Restrict the management interface to trusted administration networks.
- Use named address and service objects rather than `all` where possible.
- Enable session logging and send logs to durable storage.
- Apply IPS or application controls only after testing latency, false positives,
  and certificate behavior.
- Rate-limit at Cloudflare or Traefik; use firewall DoS policies as an
  additional network-layer control.
- If Cloudflare proxying is mandatory, synchronize the current Cloudflare IP
  ranges into reviewed firewall address objects and deny direct origin access.
- Retain a separate, authenticated management path for incident response.
- Back up the firewall configuration before and after the change.

## Validation

From the FortiGate-connected LAN:

```bash
curl --head http://10.10.1.45
curl --insecure --head https://10.10.1.45
```

From an external network:

```bash
nc -vz <PUBLIC_IPV4> 80
nc -vz <PUBLIC_IPV4> 443

curl --resolve novashop.smartdev.vn:80:<PUBLIC_IPV4> \
  --head http://novashop.smartdev.vn

curl --resolve novashop.smartdev.vn:443:<PUBLIC_IPV4> \
  --head https://novashop.smartdev.vn
```

Also verify that these ports are closed externally:

```text
22, 5432, 6379, 6443, 8080
```

Use an approved external scanner and a narrowly scoped target. Do not perform
unauthorized scanning.

## Troubleshooting

| Symptom | Check |
|---------|-------|
| Connection timeout | ISP reachability, upstream NAT, WAN routing, VIP interface, firewall deny logs |
| Port open but HTTP fails | Traefik listener, Ingress host, backend endpoints |
| Wrong application | Client Host/SNI, DNS record, duplicate Ingress rule |
| Cloudflare 521 | Origin service unavailable or source ranges blocked |
| Cloudflare 522 | Routing, VIP, policy, or origin response timeout |
| Cloudflare 525/526 | Origin TLS handshake, hostname, trust chain, or Full (strict) requirements |
| Client IP unavailable | Forwarded-header trust and proxy protocol design |

## Rollback

1. Disable the new WAN-to-platform firewall policy.
2. Disable or remove the VIP mappings after traffic has drained.
3. Restore the prior DNS state.
4. Confirm private LAN and GitOps access still operate.
5. Preserve logs and the failed configuration for investigation.

## Reference

- [Fortinet virtual IPs with port forwarding](https://docs.fortinet.com/document/fortigate/7.6.0/administration-guide/155333/virtual-ips-with-port-forwarding)
