# Changelog

All notable changes to NovaShop will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-08-02

First release. A single-node platform engineering portfolio: GitOps delivery,
pre-merge guardrails, observability with runbook-backed alerting, Infrastructure
as Code, and documented recovery.

### Platform, as released

- 12 Argo CD Applications, Synced and Healthy
- 31 Prometheus scrape targets, all up
- 14 alert rules, each linked to a runbook CI proves exists
- 93 automated pre-merge checks across three gates
- 15 Architecture Decision Records, 13 architecture views, 117 documents
- 7 Terraform layers, non-cloud, `fmt` clean and all validating
- Three environments behind Traefik with Let's Encrypt certificates and HSTS

### Added in this release

- Datastore backup, verification, and restore. The `novashop` database previously
  had no backup of any kind, while two documents claimed otherwise.
- An off-node copy of the material that cannot be regenerated — 21 KB, against
  27 MB on-node and 550 MB of volumes.
- Default-deny ingress in the application namespaces, trialled on a live namespace
  with a no-policy control group before being committed.
- Terraform GitOps handover layer, completing seven layers, with ADR 014.
- A Terraform audit with a maturity score and the commands to reproduce it.
- `tflint` in CI, which found twelve unused declarations invisible to `fmt` and
  `validate`.
- An ACME contact address, so Let's Encrypt expiry warnings reach a monitored
  mailbox.
- An interview guide and an engineering log recording sixteen defects, how each
  was found, and what changed.

### Fixed

- `recover.sh` could not run. It matched `^DATABASE_URL=` while the platform
  environment file declares `export DATABASE_URL=`, so recovery aborted at its
  first precondition on a healthy platform. The same mismatch had already been
  fixed in another script; it survived here because this one had never been run.
- Argo CD sync status compares a server-side apply dry-run against the live
  object, not the rendered manifest. Comparing the wrong pair produced two
  consecutive wrong fixes, both reverted.
- Backup scripts: `postgres` could not read a dump written into a 0700 root-owned
  directory; `su` inherited an inaccessible working directory; `IFS` was
  newline-and-tab while the manifest is space-separated.
- Documentation claiming the SQLite datastore and runtime environment were backed
  up, and five documents naming the wrong Ubuntu release.

### Known limitations

Stated here rather than in a footnote, because they bound what this release
claims.

- **Full recovery has never been exercised on a replacement node.** Components are
  tested individually; the sequence is not. RTO is an estimate of 30-45 minutes and
  should be treated as unknown.
- **Alerts route nowhere.** They evaluate and are queryable; nothing pages anyone.
- **No frontend tests**, 9 backend test functions, no coverage measurement.
- **Five of seven Terraform layers manage nothing.** The interface is designed and
  validated; the resources are not written.
- **Single node.** No high availability, no rescheduling, SQLite datastore.
- **No off-node backup automation**, no scheduled backup, no point-in-time recovery.
- **Distributed tracing instrumented but not deployed** — see ADR 011.

Production Readiness is scored 2/5 in `docs/AUDIT.md` for these reasons. The
remaining work is listed there as v1.1.

### Added

- Repository governance policies and community health documentation.
- Project charter and engineering principles.
- Repository-wide formatting and Git behavior configuration.
- GitOps-managed production TLS enforcement with permanent HTTPS redirects and
  HSTS after successful Let's Encrypt staging and production validation.
- Platform validation gate rendering the desired state exactly as Argo CD does,
  covering YAML lint, Kustomize builds, Helm lint and template per environment,
  and Kubernetes plus CRD schema validation.
- Cross-repository revision validation requiring every pinned NovaShop revision
  to be a commit SHA reachable from the default branch, every environment to
  deploy both components from one commit, and every referenced image tag to
  exist in the registry.
- Reusable validation workflow shared by continuous integration, the release
  workflow, and the GitOps repository.
- Branch protection expressed as reviewed repository rulesets, applied by a
  script that refuses required status checks no workflow has ever reported.
- TLS-preserving rollback manifests that keep certificates and HTTPS while
  releasing enforcement and clearing the HSTS pin with `max-age=0`.
- Certificate and ACME account key backup and restore, and a disaster recovery
  entry point that verifies every precondition before rebuilding a node.
- Dependabot coverage for GitHub Actions, pip, npm, and container base images.
- ADR 001 recording the guardrail decisions and the alternatives rejected.

### Changed

- Release publishes only after the shared validation workflow succeeds in the
  same job graph, scans each image before pushing it, and promotes `latest` in a
  separate job that requires every component to have published.
- Continuous integration no longer runs on `main`; validation there belongs to
  the release graph, which removes both the duplicate run and the race.
- Bootstrap reads the active edge phase from the reconciled Argo CD Application
  instead of accepting it as an instruction, and stops when an operator
  expectation disagrees with Git.
- The Argo CD installation manifest is verified against a pinned digest before
  it is applied.
- System upgrades during Linux bootstrap are opt-in through
  `ENABLE_SYSTEM_UPGRADE`, and the pending-reboot check runs first.
- Runtime teardown refuses to destroy namespaces holding TLS Secrets unless the
  certificate loss is acknowledged, and now removes both Argo CD projects.

### Fixed

- Prevented public-edge verification from reporting proxy responses or failed
  HTTP requests as successful origin health checks.
- Waited for Argo CD child Applications and target-specific Ingress resources
  before starting Linux runtime verification.
- Corrected certificate expiry accounting in Linux verification, which counted a
  pass inside the predicate and a failure in the caller, and added a renewal
  margin instead of only checking for expiry.
- Rejected runtime Secrets that exist without `DATABASE_URL` or `REDIS_URL`,
  which previously satisfied a presence check while leaving workloads unable to
  start.

[Unreleased]: https://github.com/nguyenlpn2015/NovaShop/commits/main
