# Public Deployment Checklist

Complete this checklist for one environment at a time. Record evidence in the
change request without including public IP details, credentials, private keys,
or sensitive firewall configuration.

Complete and approve the HTTP gate before opening the separate TLS activation
pull request. The default Linux bootstrap must not install cert-manager.

## HTTP Phase Gate

- [ ] Ubuntu GitOps root references `phases/http`.
- [ ] cert-manager and Certificate Applications do not exist.
- [ ] Public DNS resolves and TCP 80 reaches Traefik.
- [ ] Frontend and backend health return HTTP 200.
- [ ] HTTP latency is below the approved threshold.
- [ ] Argo CD and all environment Applications are Synced and Healthy.
- [ ] HTTP rollback has been tested or documented.

## TLS Change Gate

- [ ] A separate reviewed GitOps pull request selects `phases/tls`.
- [ ] The initial rollout selects `certificate-staging.yaml`.
- [ ] ACME staging issuance and rollback succeed before production promotion.
- [ ] Production promotion is a separate reviewed GitOps change.

## Change Control

- [ ] Change owner, reviewer, maintenance window, and rollback owner assigned.
- [ ] Target environment and hostnames confirmed.
- [ ] Current DNS, firewall, Ingress, and TLS state recorded securely.
- [ ] Private management access tested independently of public DNS.
- [ ] Application and platform backups meet the recovery plan.

## DNS

- [ ] Cloudflare zone for `smartdev.vn` is active.
- [ ] Frontend `A` record points to the approved public IPv4 address.
- [ ] API `CNAME` or `A` record follows the approved edge path.
- [ ] No unintended `AAAA` record exists.
- [ ] Rollout TTL is set to 300 seconds or the approved value.
- [ ] Initial validation is performed with proxy set to DNS Only.
- [ ] Production records are switched to Proxied only after origin validation.
- [ ] External resolvers return the expected DNS answer.

## FortiGate VIP and Firewall

- [ ] Public TCP 80 maps only to `10.10.1.45:80`.
- [ ] Public TCP 443 maps only to `10.10.1.45:443`.
- [ ] Dedicated inbound policy references the NovaShop VIP objects.
- [ ] Only HTTP and HTTPS services are allowed.
- [ ] SSH, PostgreSQL, Redis, Kubernetes API, Argo CD, and dashboards are not
      publicly mapped.
- [ ] Accepted and denied sessions are logged.
- [ ] Cloudflare source ranges are enforced for proxy-only operation.
- [ ] Configuration backup and rollback steps are available.

## Ubuntu and k3s

- [ ] `systemctl is-active k3s` returns `active`.
- [ ] Node reports `Ready`.
- [ ] UFW policy is reviewed and does not conflict with k3s networking.
- [ ] Host time synchronization is healthy.
- [ ] Disk, memory, CPU, and certificate working storage have safe capacity.

```bash
systemctl is-active k3s
kubectl get nodes -o wide
timedatectl status
df -h
free -h
```

## TLS

- [ ] Issuer and certificate strategy are approved.
- [ ] Certificate SANs cover the frontend and API hostnames.
- [ ] Certificate chain, private-key match, and expiration are validated.
- [ ] TLS Secret exists only in the intended namespace.
- [ ] No certificate private key or Secret export is committed to Git.
- [ ] Traefik serves the expected certificate.
- [ ] Cloudflare encryption mode is Full (strict).
- [ ] Expiry alerts and renewal ownership are configured.
- [ ] Previous valid certificate is available in approved encrypted storage.

## Traefik and Ingress

- [ ] Traefik Deployment and Service are healthy.
- [ ] `web` and `websecure` entrypoints are available.
- [ ] Ingress class is `traefik`.
- [ ] Exact frontend and API host rules are present.
- [ ] HTTP redirects to HTTPS.
- [ ] HTTPS Ingress references the approved TLS Secret.
- [ ] Security header and compression Middleware behavior is validated.
- [ ] Traefik dashboard is not publicly exposed.

```bash
kubectl --namespace kube-system rollout status deployment/traefik
kubectl get ingress --all-namespaces
kubectl get middleware.traefik.io --all-namespaces
```

## Argo CD and Workloads

- [ ] Root Application is `Synced` and `Healthy`.
- [ ] Target environment Application is `Synced` and `Healthy`.
- [ ] Expected replica count is Available.
- [ ] Runtime Secrets exist.
- [ ] Pods are `Running` and restart counts are stable.
- [ ] Services have ready endpoints.

```bash
kubectl get applications --namespace argocd
kubectl get deployments,pods,services,endpoints \
  --namespace <NAMESPACE>
```

## External Health Validation

- [ ] HTTP frontend returns a redirect to HTTPS.
- [ ] HTTPS frontend returns HTTP 200.
- [ ] HTTPS backend `/health` returns HTTP 200.
- [ ] Browser shows a valid certificate and expected hostname.
- [ ] Validation succeeds from a network outside the origin LAN.
- [ ] Cloudflare-proxied validation succeeds.
- [ ] Controlled direct-origin validation succeeds where the certificate model
      supports direct trust.

```bash
curl --head http://novashop.smartdev.vn
curl --fail --show-error --head https://novashop.smartdev.vn
curl --fail --show-error https://api.novashop.smartdev.vn/health
```

## Security Validation

- [ ] `Strict-Transport-Security` is enabled only after HTTPS burn-in.
- [ ] `X-Content-Type-Options: nosniff` is present.
- [ ] `X-Frame-Options` matches the approved framing policy.
- [ ] `Referrer-Policy` matches the approved policy.
- [ ] Cloudflare WAF and bot controls are tested before enforcement.
- [ ] Rate limits protect origin capacity without blocking health checks.
- [ ] Origin access restrictions do not block Cloudflare.
- [ ] An approved external scan finds only the intended public ports.

## Rollback Readiness

- [ ] Prior DNS and proxy state can be restored.
- [ ] FortiGate policy and VIP can be disabled without affecting management.
- [ ] Prior valid TLS Secret can be restored.
- [ ] GitOps rollback revision is identified.
- [ ] Operators know how to distinguish Cloudflare, firewall, Traefik, and
      application failures.

## Completion

- [ ] All checks passed without waivers, or waivers have owners and expiry.
- [ ] Monitoring shows no sustained error increase.
- [ ] Evidence and timestamps are attached to the change record.
- [ ] Sprint acceptance evidence contains no secrets or sensitive public
      infrastructure details.
