# cert-manager

The Ubuntu k3s GitOps overlay installs cert-manager `v1.21.0` from the official
OCI Helm chart and reconciles the resources in this directory.

## Ownership

| File | Owner | Purpose |
|------|-------|---------|
| `namespace.yaml` | Argo CD | Isolates cert-manager controllers |
| `helm-values.yaml` | Argo CD Helm source | Enables retained CRDs and single-node resource limits |
| `clusterissuer.yaml` | cert-manager | Registers the Let's Encrypt production ACME account |
| `certificate.yaml` | cert-manager | Issues and renews one certificate per NovaShop environment |

The ACME HTTP-01 solver uses `ingressClassName: traefik`. Public DNS and TCP 80
must reach the Traefik `web` entrypoint before issuance can complete.

Certificate private keys, ACME account keys, and generated TLS Secrets are
controller-managed runtime data. They must not be committed to Git.

## GitOps Flow

```text
NovaShop-GitOps Ubuntu overlay
  -> cert-manager OCI Helm chart
  -> ClusterIssuer
  -> Certificate resources
  -> temporary HTTP-01 Ingress
  -> Let's Encrypt validation
  -> environment TLS Secrets
  -> Traefik HTTPS Ingress
```

No operator `kubectl apply` is required after bootstrap. Argo CD reconciles the
installation and cert-manager reconciles certificate issuance and renewal.

## Runtime Verification

```bash
kubectl get pods --namespace cert-manager
kubectl get clusterissuer letsencrypt-production
kubectl get certificates --all-namespaces
kubectl get challenges,orders --all-namespaces
```

See [edge verification](../../docs/networking/verification.md) for expected
results and troubleshooting.
