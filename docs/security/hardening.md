# Public Edge Hardening

Apply hardening incrementally, test each control, and preserve an authenticated
recovery path. This document provides guidance; it does not automatically
change the host, firewall, Cloudflare, Traefik, or application.

## Exposure Policy

Publicly expose only TCP 80 and 443 through FortiGate. Keep these private:

- SSH (`22`);
- PostgreSQL (`5432`);
- Redis (`6379`);
- Kubernetes API (`6443`);
- Argo CD UI and API;
- Traefik dashboard and metrics;
- node and container runtime endpoints.

## Traefik Dashboard

- Keep the dashboard disabled unless operators actively need it.
- Never publish the insecure dashboard entrypoint.
- For temporary access, use an SSH tunnel and localhost-bound `kubectl
  port-forward`.
- If long-lived access becomes necessary, require authentication,
  authorization, TLS, and source restrictions.

## SSH

- Restrict FortiGate and UFW sources to the management network or VPN.
- Use SSH keys; disable password authentication after emergency access is
  tested.
- Disable direct root login and use a named administrative account with sudo.
- Set idle timeouts and review authentication logs.
- Do not create a public TCP 22 VIP.

Example policy targets, to be applied only after console recovery is confirmed:

```text
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AllowUsers <ADMIN_USER>
```

## UFW and Network Firewall

FortiGate is the primary perimeter control; UFW is defense in depth on Ubuntu.
Keep policies consistent:

- allow SSH only from the management CIDR;
- allow Kubernetes API only from trusted administration sources;
- allow HTTP/HTTPS from the intended source set;
- allow required k3s pod and service networking;
- deny unsolicited inbound traffic;
- enable logging without exhausting disk capacity.

When Cloudflare proxying is mandatory, allow current Cloudflare ranges to
origin ports and block other Internet sources. Treat range synchronization as a
reviewed operational process because provider ranges can change.

## Fail2Ban

Fail2Ban is useful for exposed host authentication services, not as a
replacement for removing public exposure. If SSH is reachable from a controlled
network only, tune jails to that threat model. Never ban Cloudflare proxy
addresses based on untrusted forwarding headers.

## Automatic Updates

- Enable Ubuntu unattended security updates with an approved maintenance
  policy.
- Monitor failed updates and `/var/run/reboot-required`.
- Schedule k3s, Traefik, Argo CD, and kernel upgrades separately.
- Preserve rollback artifacts and backups before platform upgrades.
- Do not permit unattended major-version changes.

## TLS

- Use Cloudflare Full (strict).
- Permit TLS 1.2 and 1.3 according to client compatibility requirements.
- Disable obsolete protocols and weak cipher suites.
- Monitor expiration, hostname mismatches, and handshake errors.
- Rotate a private key after compromise or suspected disclosure.

## HTTP Security Headers

Introduce headers with browser validation:

| Header | Recommended baseline | Caution |
|--------|----------------------|---------|
| `Strict-Transport-Security` | `max-age=31536000` after burn-in | Do not enable before HTTPS and subdomains are ready |
| `X-Content-Type-Options` | `nosniff` | Low compatibility risk |
| `X-Frame-Options` | `DENY` | Use `SAMEORIGIN` if legitimate framing is required |
| `Referrer-Policy` | `strict-origin-when-cross-origin` | Validate analytics and cross-origin flows |
| `Content-Security-Policy` | Application-specific | Begin report-only; a generic policy can break Next.js |

Do not submit a domain to the HSTS preload list during this sprint. Preload is
difficult to reverse and applies to future traffic before the application can
respond.

## Rate Limiting

- Use Cloudflare edge rate limiting for public abuse controls.
- Use Traefik rate limiting to protect origin capacity.
- Separate API and browser thresholds.
- Exclude or carefully tune health checks.
- Confirm the trusted client-IP chain before enforcing per-client limits.
- Alert on sustained throttling and review false positives.

## Cloudflare WAF and Bot Protection

- Proxy public web records before expecting WAF enforcement.
- Start managed rules in log or simulate mode when available.
- Review API paths, request sizes, and expected automation clients.
- Add narrowly scoped exceptions with owners and expiration dates.
- Enable bot controls progressively and monitor customer impact.
- Keep origin controls active; Cloudflare is an additional layer, not the sole
  security boundary.

## Verification

```bash
curl --head https://novashop.smartdev.vn
curl --silent --dump-header - --output /dev/null \
  https://api.novashop.smartdev.vn/health

ss -lntup
sudo ufw status verbose
sudo sshd -T
sudo systemctl status unattended-upgrades --no-pager
```

From an authorized external network, confirm only the intended public ports are
reachable.

## References

- [Cloudflare origin protection](https://developers.cloudflare.com/fundamentals/security/protect-your-origin-server/)
- [Cloudflare IP addresses](https://developers.cloudflare.com/fundamentals/concepts/cloudflare-ip-addresses/)
- [Traefik Headers Middleware](https://doc.traefik.io/traefik/reference/routing-configuration/http/middlewares/headers/)
- [TLS Strategy](tls.md)
