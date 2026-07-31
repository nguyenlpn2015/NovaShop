# cert-manager Activation

Sprint 4.6.1 integrates cert-manager declaratively but leaves it disabled
during the default Ubuntu bootstrap.

## Controlled Rollout

```text
Phase 1
Cloudflare -> FortiGate -> Traefik -> HTTP Ingress -> NovaShop

Phase 2A
GitOps PR -> cert-manager -> Let's Encrypt staging
  -> Certificate -> TLS Secret -> Traefik HTTPS

Phase 2B
GitOps PR -> Let's Encrypt production
  -> trusted Certificate -> redirect -> HSTS
```

### Phase 1 Acceptance

- public DNS resolves;
- TCP 80 reaches Traefik;
- frontend and backend health return HTTP 200;
- Argo CD Applications are Synced and Healthy;
- cert-manager Applications do not exist.

### Phase 2A Acceptance

1. Change the Ubuntu root Kustomization from `phases/http` to `phases/tls`.
2. Keep `certificate-staging.yaml` selected.
3. Review and merge the GitOps pull request.
4. Verify Issuer Ready, Certificate Ready, TLS Secret creation, HTTPS routing,
   certificate expiry output, and rollback.

The staging certificate is intentionally untrusted by browsers.

### Phase 2B Acceptance

1. Change the Certificate Application include from
   `certificate-staging.yaml` to `certificate.yaml`.
2. Review and merge the GitOps pull request.
3. Verify the production chain and all SANs.
4. Enable redirect, HSTS, and Cloudflare Full (strict) only after HTTPS burn-in.

## Ownership

- Argo CD owns desired platform resources.
- cert-manager owns ACME issuance, renewal, and TLS Secrets.
- Traefik owns TLS termination and host routing.
- Operators own rollout approval and promotion.

No activation step uses `kubectl apply`, Helm CLI installation, or an
imperative bootstrap flag.

## Rollback

Revert the TLS activation GitOps commit to restore `phases/http`. Confirm HTTP
health before investigating cert-manager. Do not delete CRDs while Certificate
resources still exist.

## Future DNS-01

DNS-01 may replace HTTP-01 when wildcard certificates or private origins are
required. Use a narrowly scoped Cloudflare API token stored outside Git and
validate with a staging issuer first.

## References

- [cert-manager documentation](https://cert-manager.io/docs/)
- [TLS Renewal Runbook](../networking/ssl-renewal.md)
