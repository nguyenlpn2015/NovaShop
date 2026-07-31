# cert-manager

These resources operate cert-manager and Let's Encrypt for the Ubuntu k3s
production edge through Argo CD.

## Deployment Phases

| Phase | Default | Desired state |
|------|---------|---------------|
| HTTP | Completed | Public DNS, FortiGate, Traefik, HTTP Ingress, application health |
| TLS staging | Completed | ACME HTTP-01 and certificate lifecycle validation |
| TLS production | Active | Trusted Certificates, redirect, HSTS, and automatic renewal |

The GitOps root references `clusters/ubuntu-k3s/phases/tls`, and the
Certificate Application selects `certificate.yaml`.

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

Production validation:

```bash
TLS_PHASE_ENABLED=true \
TLS_ISSUER_NAME=letsencrypt-production \
TLS_PRODUCTION_ENABLED=true \
bash scripts/linux/verify.sh
```

See [edge verification](../../docs/networking/verification.md).
