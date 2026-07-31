# Production Edge Verification

Run verification after Argo CD has reconciled the Ubuntu k3s overlay. No
operator `kubectl apply` or patch is part of this procedure.

## Automated Verification

```bash
export KUBECONFIG=/root/.kube/config
export PATH="/root/.local/bin:${PATH}"

cd ~/NovaShop
bash scripts/linux/verify.sh
```

Every check prints `PASS` or `FAIL`. Success ends with:

```text
[linux/verify] RESULT: PASS (... passed, 0 failed)
```

## DNS Resolution

```bash
getent ahostsv4 dev.novashop.smartdev.vn
getent ahostsv4 staging.novashop.smartdev.vn
getent ahostsv4 novashop.smartdev.vn
```

Expected: each command returns at least one IPv4 address. Proxied Cloudflare
records return Cloudflare addresses rather than the FortiGate public address.

## Argo CD

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

## Traefik

```bash
kubectl --namespace kube-system get deployment traefik
kubectl get ingress --all-namespaces
kubectl get middleware.traefik.io --all-namespaces
```

Expected: Traefik is Available and each environment has HTTP and HTTPS Ingress
resources plus redirect, security-header, compression, and chain Middleware
resources.

## cert-manager

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

## HTTP Redirect

```bash
curl --head http://dev.novashop.smartdev.vn
curl --head http://staging.novashop.smartdev.vn
curl --head http://novashop.smartdev.vn
```

Expected: HTTP status `301`, `302`, `307`, or `308` with an HTTPS `Location`.

## HTTPS and Health

```bash
curl --fail https://dev.novashop.smartdev.vn/
curl --fail https://api.dev.novashop.smartdev.vn/health

curl --fail https://staging.novashop.smartdev.vn/
curl --fail https://api.staging.novashop.smartdev.vn/health

curl --fail https://novashop.smartdev.vn/
curl --fail https://api.novashop.smartdev.vn/health
```

Expected: every request returns HTTP 200 with a publicly trusted certificate.

## Security Headers

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
