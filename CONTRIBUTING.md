# Contributing to NovaShop

Thank you for helping improve NovaShop. Contributions that strengthen
reliability, security, maintainability, documentation, and operational
readiness are welcome.

By participating, you agree to follow the
[Code of Conduct](CODE_OF_CONDUCT.md).

## Where to Start

**If you have never touched this repository**, read
[Architecture Overview](docs/architecture/overview.md), then run the three
gates in [Validate Before Opening](#validate-before-opening). They run in a few
minutes with no cluster and no credentials, and they are the fastest way to
learn what this platform considers correct.

**Contributions that are always welcome**, in rough order of how useful they
are here:

| | |
| --- | --- |
| A document that is wrong | The highest-value report this project takes — see the [documentation template](https://github.com/nguyenlpn2015/NovaShop/issues/new?template=documentation.yml) |
| Test coverage measurement | There is none, for either side. 52 backend and 17 frontend tests run, and nobody knows what they miss — [AUDIT.md](docs/AUDIT.md) |
| An Academy module | Fifteen of nineteen are specified but unwritten — [`docs/academy/`](docs/academy/) has the template and the files each teaches from |
| A gate that catches a real defect | Not a hypothetical one. [ADR 001](adr/001-platform-guardrails.md) explains the distinction |
| A reproduction of something that fails silently | Anything that renders, validates, deploys, and does nothing |

**Two repositories.** Application code, the Helm chart, platform values, and
scripts are here. Argo CD Applications and per-environment values are in
[NovaShop-GitOps](https://github.com/nguyenlpn2015/NovaShop-GitOps). A change
to what is deployed usually needs a pull request in both, and the one here
must merge first — the GitOps repository pins this one by commit SHA and a
gate verifies that SHA is reachable from `main`.

## Before You Contribute

- Search existing issues and pull requests before starting new work.
- Open an issue for significant changes so scope and direction can be agreed
  before implementation.
- Use GitHub's private vulnerability reporting process for security issues.
  Do not disclose vulnerabilities in public issues.
- Keep each contribution focused on one coherent change.

## Development Workflow

1. Fork the repository or create a branch in an authorized clone.
2. Create a short-lived branch from the default branch.
3. Make the smallest complete change that addresses the agreed scope.
4. Update tests and documentation where applicable.
5. Run the relevant local quality and security checks.
6. Commit with a clear, imperative message.
7. Open a pull request using the repository template.
8. Address review feedback and keep the branch current.

Recommended branch prefixes include `feature/`, `fix/`, `docs/`, `chore/`,
`security/`, and `release/`.

## Engineering Expectations

Contributions must:

- follow the [Engineering Principles](docs/ENGINEERING_PRINCIPLES.md);
- avoid committing credentials, tokens, private keys, or customer data;
- preserve backward compatibility unless a breaking change is approved;
- include observability and operational considerations where relevant;
- document significant architectural decisions as ADRs;
- use automation that is reproducible and suitable for continuous delivery;
- leave the repository in a buildable and reviewable state.

## Commits

Use concise, imperative commit subjects. Conventional Commit prefixes are
recommended:

- `feat:` for a new capability;
- `fix:` for a defect correction;
- `docs:` for documentation-only changes;
- `chore:` for maintenance;
- `refactor:` for internal restructuring;
- `test:` for test changes;
- `ci:` for delivery-pipeline changes;
- `security:` for security hardening.

Do not mix unrelated changes in one commit or rewrite another contributor's
history without coordination.

## Pull Requests

A pull request should:

- explain the problem, proposed change, and expected outcome;
- link the relevant issue or ADR;
- identify risks, breaking changes, and rollback considerations;
- include evidence of validation;
- update user, engineering, and operational documentation as needed;
- pass required automated checks;
- receive approval from the applicable code owner;
- contain no unresolved high-severity security findings.

Draft pull requests are encouraged for early feedback. Approval does not
replace the requirement for passing checks.

### Required Checks

The default branch is protected by the rulesets in
[`.github/rulesets`](.github/rulesets/). Merges require a linear history, a
squash merge, resolved conversations, and every check reported by the
[`Validation` workflow](.github/workflows/validation.yml): `Backend`, `Frontend`,
`Container Images`, `Security`, and `Platform`.

Changing a job name in that workflow changes a required check context. Update the
matching ruleset in the same pull request, otherwise the required check will never
be reported again and every subsequent pull request becomes unmergeable.

### Validate Before Opening

Any change to `helm/`, `kubernetes/`, `argocd/`, or the workflows affects the
deployed desired state. Run the same gate CI runs:

```bash
bash scripts/validate-platform.sh --gitops-dir ../NovaShop-GitOps
```

It needs `yamllint`, `helm`, `kubeconform`, and either `kustomize` or a recent
`kubectl`. Include the `RESULT` line as your validation evidence.

Changes to `NovaShop-GitOps` are validated by the same script through a
cross-repository workflow, so a pull request there must also keep every pinned
NovaShop revision reachable from this repository's default branch. See
[Platform Guardrails](docs/PLATFORM_GUARDRAILS.md).

## Reviews and Merging

Reviewers evaluate correctness, security, maintainability, operability,
documentation, and alignment with project scope. Authors should respond to
feedback constructively and resolve conversations only when the concern has
been addressed or explicitly accepted.

Changes are merged through the repository's protected-branch workflow. Direct
commits to protected branches are not part of the normal contribution process.

## Documentation

Documentation is part of the deliverable. Keep references, diagrams, runbooks,
and examples synchronized with behavior.

| Material | Goes in |
| --- | --- |
| Architectural decisions | [`adr/`](adr/) — use [ADR 000](adr/000-template.md) |
| Architecture views | [`docs/architecture/`](docs/architecture/) — Mermaid, so they diff |
| Alert response procedures | [`docs/observability/runbooks/`](docs/observability/runbooks/) |
| Operational guides | [`docs/operations/`](docs/operations/) |
| Teaching material | [`docs/academy/`](docs/academy/) — one module per subsystem |
| Everything else | [`docs/`](docs/), indexed by [`docs/README.md`](docs/README.md) |

Runbooks live under `docs/observability/` rather than in the root `runbooks/`
directory because each one is the target of a `runbook_url` in an alert rule,
and `validate-observability.sh` fails a pull request when any of those links
points at a file that does not exist. The root
[`runbooks/`](runbooks/README.md) is an index, not a second home.

**A document that claims more than the platform delivers is a defect, not a
rough edge.** Two documents here once stated that a backup captured the k3s
datastore; it did not, and a reader would have stopped looking. Report those
with the [documentation issue template](https://github.com/nguyenlpn2015/NovaShop/issues/new?template=documentation.yml).

## Licensing

By submitting a contribution, you agree that it may be distributed under the
terms of the [MIT License](LICENSE).
