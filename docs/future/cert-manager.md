# cert-manager Evolution

Sprint 4.6.1 installs cert-manager declaratively for Deployment Target B
without changing NovaShop application code, Traefik ownership, or the GitOps
architecture.

The current implementation uses a production Let's Encrypt `ClusterIssuer` and
HTTP-01 challenges through Traefik. This document records future evolution
toward DNS-01 when wildcard certificates or private origins are required.

## Target Responsibility Model

```text
GitOps repository
  -> desired Certificate and Issuer references
  -> Argo CD reconciliation
  -> cert-manager controller
  -> ACME issuer
  -> Kubernetes TLS Secret
  -> Traefik Ingress
```

- Argo CD owns declarative certificate resources.
- cert-manager owns issuance, renewal, and the generated TLS Secret.
- Traefik reads the Secret and terminates TLS.
- Cloudflare remains authoritative DNS and the optional HTTP proxy.
- Private keys and DNS API tokens remain outside Git.

## Recommended Issuance Model

Use ACME DNS-01 with a narrowly scoped Cloudflare API token when:

- wildcard certificates are required;
- the origin must not expose HTTP solely for validation;
- all validation must work before public traffic is enabled.

Use HTTP-01 when:

- only named host certificates are required;
- TCP 80 is reliably reachable;
- the routing path is simpler than managing DNS credentials.

Prefer a namespace-scoped `Issuer` when one environment owns its credentials.
Use a `ClusterIssuer` only when cluster-wide reuse is intentional and its blast
radius is accepted.

## Secret and Credential Controls

- Create the Cloudflare API token out-of-band.
- Grant only the required zone DNS edit and read permissions.
- Scope the token to `smartdev.vn`.
- Store it in a dedicated namespace with restrictive RBAC.
- Rotate it independently of application deployments.
- Do not place token values in Helm values, manifests, command history, or
  screenshots.

## DNS-01 Adoption Sequence

1. Record an ADR covering DNS-01 and credential scope.
2. Create a zone-scoped Cloudflare API token out-of-band.
3. Add its Secret through the approved secret-management workflow.
4. Add a staging DNS-01 issuer and validate a non-production certificate.
5. Test renewal and credential rotation.
6. Migrate one environment at a time.
7. Remove HTTP-01 only after every certificate is Ready through DNS-01.

## Validation

Validation includes:

```bash
kubectl get issuers,clusterissuers --all-namespaces
kubectl get certificates,certificaterequests,orders,challenges --all-namespaces
kubectl describe certificate <NAME> --namespace <NAMESPACE>
```

Acceptance requires:

- `Certificate` reports `Ready=True`;
- the target Secret contains a valid chain and key;
- Traefik serves the expected certificate;
- renewal succeeds before expiry;
- no credential appears in Git or logs.

## Rollback

Keep the last known-good manually operated TLS Secret in approved encrypted
storage during migration. If automated issuance fails:

1. stop the affected certificate rollout;
2. restore the known-good Secret if it is still valid and uncompromised;
3. confirm Traefik certificate selection;
4. retain cert-manager events and controller logs for investigation;
5. do not delete cluster-wide CRDs while managed resources still exist.

## Non-Goals

- changing the Helm chart in Sprint 4.6.1;
- replacing Traefik;
- storing issuer credentials in Git;
- using cert-manager as a general secret-management solution.

## References

- [cert-manager documentation](https://cert-manager.io/docs/)
- [Cloudflare API token permissions](https://developers.cloudflare.com/fundamentals/api/how-to/restrict-tokens/)
- [TLS Renewal Runbook](../networking/ssl-renewal.md)
