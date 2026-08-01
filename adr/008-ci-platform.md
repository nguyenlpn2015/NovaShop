# ADR 008: GitHub Actions as the CI platform

## Status

Accepted

## Date

2026-08-01

## Context

The repositories are on GitHub. CI has to enforce three properties that were stated as
hard requirements:

1. An image must never publish unless code validation, the security scan, and platform
   validation all passed.
2. Release must never race CI.
3. `latest` must never point at a failed build.

There is a fourth, implicit requirement: the platform validation gates need to check out
**both** repositories in one job, because `validate-gitops-revisions.sh` compares pins in
the GitOps repository against commits and images produced by the application repository.

And a fifth: branch protection has to be configuration in the repository, not clicks in a
settings page, or it is neither reviewable nor recoverable.

## Decision

GitHub Actions, with the validation suite factored into a reusable workflow.

`validation.yml` is `workflow_call` only and contains five jobs: `backend`, `frontend`,
`security`, `platform`, and `container-images`. `ci.yml` calls it on pull requests.
`release.yml` calls **the same file** and declares `publish` with `needs: validate`, then
`promote` with `needs: publish`.

Branch protection is `.github/rulesets/*.json`, applied by
`scripts/apply-branch-protection.sh`.

Every third-party action is pinned to a full commit SHA with the version in a trailing
comment.

## Alternatives Considered

**A separate release workflow triggered by CI completion** (`workflow_run`, or polling for
a green status). This was the obvious first design and it is the one the requirement
"release must never race CI" was written against. Rejected because it can only ever
*narrow* the race, never remove it: any check-then-act across two workflow runs has a
window. Calling the same reusable workflow inside the release job graph removes the window
structurally — validation and publication are nodes in one graph, so there is no state to
observe and no interval in which it can change.

**Jenkins.** Would work and is what many organisations run. Rejected because it needs a
server that itself has to be bootstrapped, secured, backed up, and monitored — on the same
8GB node it would be deploying to. The platform would be maintaining its own CI
infrastructure as a side quest.

**GitLab CI.** Strong product, and its pipeline model expresses these dependencies at least
as cleanly. Rejected because the repositories are on GitHub and mirroring them to run CI
elsewhere adds a synchronisation failure mode to solve a problem that does not exist.

**Argo Workflows or Tekton, in-cluster.** Appealingly consistent — CI on the same platform
as everything else. Rejected on a circular-dependency argument: CI that runs on the cluster
cannot build the fix for a broken cluster. It also puts image builds on the node serving
production traffic, on a node whose memory limits are already at ~150%.

**Drone, Woodpecker.** Same self-hosting objection as Jenkins, with a smaller ecosystem.

## Consequences

**Easier.** All three guarantees are properties of the graph rather than of conditions
someone has to get right. No cluster credentials in CI at all, because deployment is
Argo CD's job — CI's most privileged secret is a registry token. The `platform` job can
check out both repositories side by side, which is what makes cross-repository revision
validation possible.

**Harder, and accepted.**

*Vendor coupling.* Reusable workflows, `workflow_call`, and rulesets-as-JSON are
GitHub-specific. Moving CI elsewhere is a rewrite, not a port. Accepted knowingly: the
alternative is a lowest-common-denominator pipeline that expresses the guarantees less
well.

*Pinning actions to SHAs is maintenance.* Dependabot raises the bumps, and each one needs
review. The alternative is trusting a movable tag in a workflow that runs with credentials.

*Ordering inside a job carries the scan guarantee.* In `publish`, the build loads the image
locally, Trivy scans it, and only then does the workflow log in and push. Registry
credentials are not acquired until the scan passes. This is correct and it is a convention
a future edit could break — there is no mechanism enforcing that the login step stays
after the scan.

*`fail-fast: false` was necessary.* With the default, a frontend CVE cancelled the backend
job, and across three consecutive blocked releases there was no way to tell whether the
backend was clean. Letting both run costs minutes and turns "something failed" into "this
failed and that did not".

*Applying rulesets needed real defensive work.* Check names are discovered from actual
completed runs on both the default branch **and** pull-request head commits, because a
`pull_request`-only workflow never appears on the default branch. Every comparison strips
`\r`, because `jq` emits CRLF on Windows while `gh api` emits LF, and without it every
required check reported as "never reported".

*Duplicate runs, unresolved.* `ci.yml` triggers on both `pull_request` and `push` for
working branches, so most pushes produce two identical runs. It has caused real confusion —
re-running one while reading the other's stale result. On the [roadmap](../docs/ROADMAP.md).

## Validation

```sh
gh pr checks <n>                      # five checks on a pull request
gh run view <id> --json jobs          # publish needs validate; promote needs publish
bash scripts/apply-branch-protection.sh --dry-run
```

Confirm the scan-before-push ordering by reading the step order in the `publish` job of
`.github/workflows/release.yml`; the login step must appear after the Trivy step.
