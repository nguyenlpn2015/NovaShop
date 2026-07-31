# Changelog

All notable changes to NovaShop will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
