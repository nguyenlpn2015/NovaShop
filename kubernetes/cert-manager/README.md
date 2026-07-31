# cert-manager

These resources integrate cert-manager and Let's Encrypt into the repository
without installing them during the default Ubuntu bootstrap.

## Deployment Phases

| Phase | Default | Desired state |
|------|---------|---------------|
| HTTP | Yes | Public DNS, FortiGate, Traefik, HTTP Ingress, application health |
| TLS staging | No | cert-manager, staging ClusterIssuer, staging Certificates, HTTPS |
| TLS production | No | Production ClusterIssuer, trusted Certificates, redirect and HSTS |

The GitOps root currently references `clusters/ubuntu-k3s/phases/http`.
Activating TLS requires a reviewed change to
`clusters/ubuntu-k3s/kustomization.yaml`; bootstrap never makes that decision.

## Resources

| File | Purpose |
|------|---------|
| `namespace.yaml` | Isolated controller namespace |
| `helm-values.yaml` | Pinned chart configuration |
| `clusterissuer.yaml` | Let's Encrypt staging and production issuers |
| `certificate-staging.yaml` | Initial ACME validation using staging |
| `certificate.yaml` | Production certificate promotion |

The first TLS activation uses `letsencrypt-staging`. Its certificate is not
browser trusted; it proves DNS, TCP 80, Traefik HTTP-01, issuance, Secret
creation, and renewal behavior without consuming production rate limits.

Production promotion changes the Certificate Application include from
`certificate-staging.yaml` to `certificate.yaml` in a reviewed GitOps pull
request.

## Preconditions

- Every requested hostname resolves publicly.
- FortiGate forwards TCP 80 to Traefik.
- Cloudflare and WAF rules allow `/.well-known/acme-challenge/`.
- HTTP frontend and backend health have already been validated.
- A rollback commit and operator are identified.

Private keys, ACME account keys, generated TLS Secrets, and API tokens must
never be committed.

## Verification

After TLS has been deliberately activated:

```bash
TLS_PHASE_ENABLED=true \
TLS_ISSUER_NAME=letsencrypt-staging \
bash scripts/linux/verify.sh
```

Use `TLS_ISSUER_NAME=letsencrypt-production` only after production promotion.
Production verification also sets `TLS_PRODUCTION_ENABLED=true` after redirect
and HSTS are enabled by that reviewed change.
See [edge verification](../../docs/networking/verification.md).
