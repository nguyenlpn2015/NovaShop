# Contributing to NovaShop

Thank you for helping improve NovaShop. Contributions that strengthen
reliability, security, maintainability, documentation, and operational
readiness are welcome.

By participating, you agree to follow the
[Code of Conduct](CODE_OF_CONDUCT.md).

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
and examples synchronized with behavior. Store architectural decisions in
`adr/`, architecture material in `architecture/`, operational procedures in
`runbooks/`, and general project documentation in `docs/`.

## Licensing

By submitting a contribution, you agree that it may be distributed under the
terms of the [MIT License](LICENSE).
