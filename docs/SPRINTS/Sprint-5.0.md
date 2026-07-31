# Sprint 5.0 — Platform Guardrails

## Goal

Make the delivery contract enforceable before observability is deployed. No new
runtime technology, no application behaviour change.

## Why this sprint existed

An architecture review found four conditions that could each take production down
without warning, in a platform whose documentation already described the controls
that would have prevented them.

| Finding | Severity | Consequence if left |
|---------|----------|---------------------|
| GitOps pinned NovaShop commits that existed only on unmerged feature branches | Critical | Deleting a merged branch makes every environment, cert-manager, and the certificates unrenderable. Bootstrap and recovery both fail. |
| Release and CI both triggered on `main` with no dependency | Critical | A commit failing tests or the security scan still published its commit tag and `latest`. The published image was never the scanned image. |
| Neither default branch was protected | High | `CODEOWNERS` was advisory and a direct push bypassed every gate. |
| The documented rollback target removed TLS | High | HSTS made an HTTP-only rollback a hard failure, and pruning deleted the certificates, risking a week without HTTPS on Let's Encrypt rate limits. |

## Delivered

**A. GitOps safety.** `scripts/validate-platform.sh` renders the desired state the
way Argo CD does and validates it: yamllint on tracked YAML, `kustomize build` of
every overlay and phase, `helm lint` and `helm template` per environment for both
the in-cluster and Ubuntu k3s value combinations, and kubeconform against the
Kubernetes and CRD schemas. `scripts/validate-gitops-revisions.sh` enforces that
every NovaShop pin is a commit SHA reachable from the default branch, that each
environment deploys both components from one commit, that no desired state uses
`latest`, and that every referenced image tag exists in GHCR. Branch protection
is reviewed JSON in `.github/rulesets` applied by
`scripts/apply-branch-protection.sh`.

**B. Release safety.** `.github/workflows/validation.yml` is the single definition
of every gate, called by CI for pull requests and by the release workflow before
publication. Because release declares it as a job dependency, publishing cannot
race validation. Each image is built locally, scanned, and only then pushed;
`latest` is promoted in a separate job that requires the whole publish matrix to
have succeeded.

**C. Bootstrap reliability.** The Argo CD manifest is verified against a pinned
digest. The pending-reboot check moved ahead of package operations and the system
upgrade became opt-in, so a rerun cannot abort on a condition it created. The
edge phase is read from the reconciled Application instead of being asserted by
environment variables, so bootstrap and verification work in whatever phase Git
declares. Traefik entrypoints and runtime Secret completeness are asserted.

**D. Recovery.** `scripts/backup-platform-state.sh` and
`scripts/restore-platform-state.sh` handle the only state Git cannot reproduce:
TLS private keys and the ACME account key. `scripts/linux/recover.sh` checks every
precondition before touching k3s and restores certificates before cert-manager
reconciles, so cert-manager adopts them instead of consuming issuance quota.
`scripts/cleanup.sh` refuses to destroy TLS Secrets without acknowledgement.

**Rollback.** `kubernetes/ingress/baseline/` is a TLS-preserving rollback target.
Certificates and HTTPS stay; enforcement is released and
`Strict-Transport-Security: max-age=0` is served so browsers drop the pin. The
HTTP-only phase is retained as break-glass only.

## Evidence

The validation engine was demonstrated against the live state before it was
trusted:

```text
RESULT: FAIL (27 passed, 3 failed)   # current desired state
RESULT: PASS (30 passed, 0 failed)   # after re-pinning to a durable revision
```

The five failures were the five real non-durable pins. Re-pinning is
content-neutral: the trees at the old pins are identical to the default branch for
the referenced paths, so the fix changes durability and nothing else.

The negative test is recorded in
[the validation checklist](../guardrails/validation-checklist.md); a guardrail
that has never failed has not been tested.

## Out of scope

Prometheus, Grafana, Loki, Tempo, and OpenTelemetry belong to Sprint 5.1. Image
signing with cosign and declaring Traefik configuration as a `HelmChartConfig`
are deferred with reasons recorded in
[ADR 001](../../adr/001-platform-guardrails.md).

## Follow-up

- The ACME `ClusterIssuer` resources declare no contact address, so Let's Encrypt
  cannot send expiry warnings. Adding one requires a monitored mailbox.
- `require_code_owner_review` is disabled and required approvals are zero because
  the repository has one maintainer. A team configuration raises both.
- Declaring Traefik configuration so a node rebuild cannot lose edge settings.

## Definition of done

- [x] Cross-repository revision validation blocks a non-durable pin.
- [x] Desired state renders and schema-validates in CI for both repositories.
- [x] Release cannot publish before validation, and `latest` cannot advance on a
      partial release.
- [x] Bootstrap is rerun-safe and verifies the Argo CD manifest digest.
- [x] Recovery restores certificate material before cert-manager reconciles.
- [x] Rollback preserves TLS.
- [ ] Rulesets applied to both repositories.
- [ ] GitOps repository re-pinned and phases restructured.
