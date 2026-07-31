# Production Edge Verification

Verification retains phase flags for rollback testing. The Ubuntu bootstrap
exports the production TLS flags and validates the active final state.

## Automated Verification

```bash
export KUBECONFIG=/root/.kube/config
export PATH="/root/.local/bin:${PATH}"

cd ~/NovaShop
TLS_PHASE_ENABLED=true \
TLS_ISSUER_NAME=letsencrypt-production \
TLS_PRODUCTION_ENABLED=true \
bash scripts/linux/verify.sh
```

The production run verifies Nodes, disk, memory, Traefik, Argo CD, Pods,
Secrets, DNS, HTTP redirects, trusted HTTPS, certificate expiry, Ingress, HSTS,
and security headers. Every check prints `PASS` or `FAIL`.

The verifier disables curl proxy configuration and `.curlrc` for public edge
requests. A DNS or connection failure therefore cannot be reported as a
successful application response from an intermediary proxy.

After the reviewed TLS GitOps phase is active, enable the additional checks:

```bash
TLS_PHASE_ENABLED=true \
TLS_ISSUER_NAME=letsencrypt-staging \
bash scripts/linux/verify.sh
```

The staging chain is intentionally not publicly trusted. Automated staging
HTTPS checks allow that chain only after the Kubernetes Certificate and TLS
Secret have been validated. Production checks retain normal trust validation.

Use `TLS_ISSUER_NAME=letsencrypt-production` only after the Certificate
Application has been promoted from `certificate-staging.yaml` to
`certificate.yaml`. Set `TLS_PRODUCTION_ENABLED=true` only after the same
reviewed promotion enables HTTP redirect and HSTS.

## DNS Resolution

```bash
getent ahostsv4 dev.novashop.smartdev.vn
getent ahostsv4 staging.novashop.smartdev.vn
getent ahostsv4 novashop.smartdev.vn
```

Expected: each command returns at least one IPv4 address. Proxied Cloudflare
records return Cloudflare addresses rather than the FortiGate public address.

## HTTP Phase Health

```bash
curl --fail http://dev.novashop.smartdev.vn/
curl --fail http://api.dev.novashop.smartdev.vn/health
curl --fail http://staging.novashop.smartdev.vn/
curl --fail http://api.staging.novashop.smartdev.vn/health
curl --fail http://novashop.smartdev.vn/
curl --fail http://api.novashop.smartdev.vn/health
```

Expected: every request returns HTTP 200 before cert-manager is activated.

## Argo CD: TLS Phase

```bash
kubectl get applications --namespace argocd
```

Expected:

```text
novashop-root            Synced   Healthy
novashop-cert-manager    Synced   Healthy
novashop-certificates    Synced   Healthy
novashop-development     Synced   Healthy
novashop-staging         Synced   Healthy
novashop-production      Synced   Healthy
```

## Traefik: TLS Phase

```bash
kubectl --namespace kube-system get deployment traefik
kubectl get ingress --all-namespaces
kubectl get middleware.traefik.io --all-namespaces
```

Expected: Traefik is Available and each environment has HTTP and HTTPS Ingress
resources plus redirect, security-header, compression, and chain Middleware
resources.

## cert-manager: TLS Phase

```bash
kubectl get pods --namespace cert-manager
kubectl get clusterissuer letsencrypt-production
kubectl get certificates --all-namespaces
kubectl get certificaterequests,orders,challenges --all-namespaces
```

Expected:

- cert-manager, webhook, and cainjector Pods are `Running`;
- `letsencrypt-production` reports `Ready=True`;
- all three Certificates report `Ready=True`;
- completed ACME resources show no active failure.

Inspect a failed issuance:

```bash
kubectl describe clusterissuer letsencrypt-production
kubectl describe certificate novashop-production-tls \
  --namespace novashop-production
kubectl get challenges,orders --all-namespaces
kubectl logs deployment/cert-manager \
  --namespace cert-manager \
  --tail=200
```

## Namespaces, Secrets, and Pods

```bash
kubectl get namespaces | grep -E 'cert-manager|novashop'
kubectl get secrets --all-namespaces | grep 'novashop-.*-tls'
kubectl get pods --all-namespaces
```

Expected: all platform namespaces are Active, every environment has a
`kubernetes.io/tls` Secret, and application Pods are Ready.

## HTTP Redirect: TLS Phase

```bash
curl --head http://dev.novashop.smartdev.vn
curl --head http://staging.novashop.smartdev.vn
curl --head http://novashop.smartdev.vn
```

Expected: HTTP status `301`, `302`, `307`, or `308` with an HTTPS `Location`.

## HTTPS and Health: TLS Phase

```bash
curl --fail https://dev.novashop.smartdev.vn/
curl --fail https://api.dev.novashop.smartdev.vn/health

curl --fail https://staging.novashop.smartdev.vn/
curl --fail https://api.staging.novashop.smartdev.vn/health

curl --fail https://novashop.smartdev.vn/
curl --fail https://api.novashop.smartdev.vn/health
```

Expected during production promotion: every request returns HTTP 200 with a
publicly trusted certificate.

## Security Headers: TLS Phase

```bash
curl --head https://novashop.smartdev.vn
```

Expected headers:

```text
Strict-Transport-Security
X-Content-Type-Options
X-Frame-Options
Referrer-Policy
Permissions-Policy
```

## Troubleshooting

| Symptom | Diagnostic |
|---------|------------|
| `ClusterIssuer` not Ready | Check cert-manager controller logs and outbound HTTPS/DNS |
| `Certificate` not Ready | Describe its `CertificateRequest`, `Order`, and `Challenge` |
| HTTP-01 self-check fails | Confirm public DNS and TCP 80 reach Traefik |
| Challenge returns 404 | Inspect temporary solver Ingress, Service, and Pod |
| HTTPS default certificate | Confirm Certificate Secret name matches HTTPS Ingress |
| Application OutOfSync | Inspect Argo CD source revision and render error |
| Server-side checks time out | Test externally; FortiGate hairpin NAT may be unavailable |
| Cloudflare 526 | Confirm origin certificate SAN and Full (strict) trust |

HTTP-01 cannot issue certificates until every requested hostname resolves
publicly and reaches the Traefik `web` entrypoint on TCP 80.
