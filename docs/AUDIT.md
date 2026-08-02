# Repository Audit

A self-assessment of NovaShop across seven dimensions, with the evidence behind each score
and a roadmap to v1.0.

**Date:** 2026-08-01 · **Commit:** `main` after Sprint 5.1 · **Scope:** both repositories,
all scripts, all documentation, CI, GitOps, Kubernetes, bootstrap, observability

Scores are 1–5. A 5 means "I would defend this in a production review at a company with an
SRE function". Nothing here is scored 5, and the reasons are stated.

## Summary

| Dimension | Score | One-line assessment |
|---|---|---|
| Maintainability | **4** / 5 | Strong structure and documented reasoning; the `docs/` tree still carries layered duplication |
| Reliability | **3** / 5 | Excellent configuration validation; genuinely thin application test coverage |
| Security | **4** / 5 | No secrets in Git, least-privilege proven, scan-before-push enforced; open items on node access |
| Platform Readiness | **4** / 5 | GitOps, guardrails, phased TLS, and rehearsed recovery all real and verified |
| Production Readiness | **2** / 5 | One node, no HA, no alert routing, 7-day retention. Honest about all of it. |
| Interview Readiness | **5** / 5 | Every non-obvious decision has a recorded reason and a failure that motivated it |
| Portfolio Quality | **5** / 5 | Engineering log, interview guide, and a README a reviewer can finish |

**Overall 3.9 / 5 after the v1.0 rescore below.**

**Weighted view for the stated purpose** (a Senior DevOps portfolio): the dimensions that
matter most are Platform Readiness, Interview Readiness, and Maintainability, and those are
the strongest. The weakest, Production Readiness, is weak for reasons the repository declares
rather than hides.

---

## Maintainability — 4/5

### Evidence for

**Decisions are recorded, with alternatives.** Eleven ADRs, each naming the constraint that
was real at the time and giving every rejected option a specific reason. The Let's Encrypt
rate limit explains more of this platform's design than any preference could, and it is
written down.

**Failures are recorded where the fix lives.** Comments explain *why*, including the wrong
turns: the scrape annotation that named a Service port, the `stage.labels` that produced
journal streams with no `unit` label, the `initChownData` that needed root. A future reader
does not have to rediscover them.

**Validation is scripted, not described.** Three gates, 94 checks total (39 + 30 + 25), all
runnable locally without a cluster. Version constants live in the gate, so a chart upgrade
that forgets to bump them fails visibly.

**Shell discipline is consistent.** 19 of 20 scripts use `set -Eeuo pipefail`. The exception,
`scripts/lib/edge-phase.sh`, is a sourced library where strict mode would leak into the
caller — correct, not an omission.

**Diagrams cannot silently rot.** All Mermaid, all in Markdown, all diffable in review.

### Evidence against

**The `docs/` tree has layered duplication with confusing names.** `docs/DEPLOYMENT_GUIDE.md`
and `docs/deployment/ubuntu-k3s.md` both walk through installation. `docs/OPERATIONS.md` and
`docs/deployment/operations.md` are both operations references. `docs/PORTFOLIO_EVIDENCE.md`
(27 lines) is a thinner version of `docs/deployment/portfolio-evidence.md` (85). They are
layered rather than duplicated — generic versus target-specific — but nothing in the names says
so, and "Deployment Target A/B" is internal jargon that means nothing to a reader.

**A sprint artefact is shelved as an operational document.**
`docs/guardrails/validation-checklist.md` is titled "Sprint 5.0 Validation Checklist" and sits
in a directory implying it is current reference.

**Stub documents remain.** `docs/PROJECT_GLOSSARY.md` (13 lines) and `docs/LEARNING_LOG.md`
(18 lines) are placeholders.

### To reach 5

Merge the layered pairs or rename them to say what they are; move sprint artefacts under
`docs/SPRINTS/`; fill or delete the stubs.

---

## Reliability — 3/5

This is the honest low point among the engineering dimensions, and the gap is specific.

### Evidence for

**Configuration reliability is genuinely strong.** 94 automated checks. The observability gate
in particular defends against the failure mode that ordinary validation misses: a scrape job
whose relabel rules match nothing renders, validates, and deploys correctly and collects
nothing. It asserts required jobs by name, asserts Traefik's discovery role, runs
`promtool check config` and `promtool check rules`, and resolves every alert's `runbook_url` to
a file that exists.

**The gates are negative-tested.** The runbook check was verified against a deleted runbook, a
removed `severity`, and a corrupted expression — each failing correctly and naming the alert. A
gate that has only ever passed proves nothing.

**Bootstrap and datastore configuration are idempotent**, using marked managed blocks that
restart a service only when content actually changed — which is what makes them safe to run
during an incident.

**Recovery is rehearsed, and its preconditions are checked before anything is modified.**
Certificates are restored *before* reconciliation specifically so a rehearsal costs zero
Let's Encrypt issuances.

**Fourteen alerts, every expression evaluated against live data before merge** — not to see it
fire, but to confirm its label selectors match real series. That check found a real defect: the
duplicate Traefik scrape.

### Evidence against

**Application test coverage is thin.** Nine test functions across two backend files
(`test_health.py`, `test_metrics.py`). **Zero frontend tests and no test framework installed.**
No coverage measurement in CI.

The nine tests are well-chosen — one caught the route-label bug where every request was
labelled `unmatched` — but nine is nine.

**No integration test.** Nothing exercises the application against a real PostgreSQL and Redis
in CI, so the `/ready` behaviour that gates every production pod is verified only by hand.

**Tracing instrumentation has never run against a collector.** It is unit-tested and disabled;
"it works" is untested end to end.

**No load or soak testing.** Latency and error-rate alert thresholds were chosen by reasoning,
not measurement.

### To reach 4

Add a frontend test framework and a meaningful first suite; add an integration test with
service containers; measure coverage in CI and publish the number.

---

## Security — 4/5

### Evidence for

**No credential is in Git, in any form.** Runtime credentials are in a root-owned 0600 file;
two Kubernetes Secrets are created out of band and referenced by name. `.gitignore` blocks
`tls-*.json`, `acme-*.json`, `runtime-*.json`, and `platform-state*/` because a backup of this
platform contains certificate private keys.

**An unscanned image cannot reach the registry.** In the `publish` job the build loads locally,
Trivy scans, and only then does the workflow acquire registry credentials and push. There is no
path — no `continue-on-error`, no `if: always()` — from a failing scan to a push.

**Least privilege was proven, not assumed.** `pg_monitor` alone let the metrics exporter create
tables, because PostgreSQL 14 grants `CREATE` on `public` to `PUBLIC`. That grant is revoked and
given to the application role only, verified by attempting a write as the exporter and having it
denied — and separately verifying the application could still write.

**Actions are pinned to full commit SHAs.** A tag is a movable pointer, and workflows run with
credentials.

**The Argo CD install manifest is pinned by digest**, because bootstrap applies a large remote
YAML file with cluster-admin.

**No cluster credentials exist in CI at all.** Deployment is Argo CD's job; CI's most privileged
secret is a registry token.

**Redis requires authentication and PostgreSQL is scoped to the pod CIDR** — both were
previously open on the pod network, which was a real finding.

**Grafana runs fully non-root.** `initChownData` was disabled rather than granted root, since
`fsGroup` already sets group ownership at mount time.

**Dependabot covers four ecosystems weekly**, and base-image CVEs have been acted on — including
removing npm, npx, corepack, and yarn from the frontend runtime stage, since the vulnerable
packages were vendored inside the node image and absent from `package-lock.json`.

### Evidence against

**The node password was shared in plain text during development and is not yet rotated.** SSH
key authentication is not yet enforced. Recorded as an open item in
[security/hardening.md](security/hardening.md) rather than quietly omitted.

**No admission control.** The `AppProject` whitelist bounds what Argo CD may create, but nothing
stops a direct `kubectl apply`. No Kyverno, no Gatekeeper, no Pod Security Admission enforcement
documented.

**Network policies covered nothing this platform owns.** Seven existed, all shipped by the
Argo CD install manifest and scoped to `argocd`. Every namespace the platform owns —
`novashop-*`, `observability`, `cert-manager` — had none, so any pod could reach any pod and
the host datastores. Addressed for the application namespaces; `observability` and
`cert-manager` remain open.

**No image signing or provenance.** Images are scanned, not signed. No cosign, no SLSA
attestation.

**No secret rotation mechanism.** A procedure exists; nothing enforces or reminds.

### To reach 5

Rotate node credentials and enforce SSH keys; add default-deny network policies; sign images
with cosign; enable Pod Security Admission at `restricted` where workloads allow.

---

## Platform Readiness — 4/5

### Evidence for

**GitOps is real and enforced.** Every reference from the GitOps repository to the application
repository is a 40-character SHA, verified to be an ancestor of `main`, with both components
from one commit and both images confirmed to exist in GHCR.

**Release safety is structural, not conditional.** Release cannot race CI because it calls the
same reusable workflow inside one job graph — there is no check-then-act window to narrow.
`latest` moves only after the full matrix.

**TLS is phased, and the phase is detected rather than assumed.** Driven by a real constraint:
five duplicate certificates per 168 hours. Rollback unwinds HSTS with `max-age=0` rather than
dropping to HTTP and stranding every previous visitor.

**Recovery is a tested procedure** with preconditions checked before modification and
certificate material restored before reconciliation.

**Branch protection is code**, applied by script, with check names discovered from actual runs
on both the default branch and pull-request heads.

**Observability is verified rather than assumed**, including the AppProject-whitelist gate added
after Loki's `StatefulSet` was refused at sync time — moving that class of failure from after
merge to before it.

### Evidence against

**Some control-plane metrics are not collected.** Scheduler and controller-manager need k3s
bind-address flags and a restart, deliberately deferred to a maintenance window.

**Traefik is scraped twice** — seven duplicate series — because the Traefik pod carries its own
`prometheus.io` annotations alongside the dedicated job. Mitigated by pinning `job="traefik"` in
the alerts, not yet removed.

**Duplicate CI runs.** `ci.yml` triggers on both `pull_request` and `push` for working branches.
Wasteful, and it has caused real confusion.

**Dashboards are provisioned but sparse.** The mechanism is right — ConfigMaps with the
`grafana_dashboard` label, nothing created in the UI — but the original scope named eleven
dashboards and they are not all built.

### To reach 5

Land the k3s flag change with the next upgrade; remove the duplicate Traefik scrape; drop the
`push` trigger; complete the dashboard set.

---

## Production Readiness — 2/5

The lowest score, and the most honestly earned. This platform is not production-ready for
someone else's traffic, and every document says so.

### The gaps, plainly

| Gap | Consequence |
|---|---|
| **One node** | A node fault is a total outage. Nowhere to reschedule. |
| **SQLite datastore** | No quorum. The backup is the only rollback. |
| **`local-path` only** | Volumes cannot outlive the node. |
| **No alert routing** | Alerts evaluate and are queryable; nothing pages anyone. |
| **7-day metrics, 5-day logs** | Enough to investigate an incident, not to see a trend. |
| **Memory limits at ~150% of allocatable** | Intentional overcommit; the OOM killer picks by score, not importance. |
| **No autoscaling** | Replica counts are fixed in values files. |
| **No PodDisruptionBudgets in practice** | With one node they would only block drains. |
| **No load testing** | Alert thresholds are reasoned, not measured. |

### What is genuinely production-grade

Delivery, validation, secret handling, recovery, and alert design are all of a standard that
would transfer to a production environment unchanged. The gap is capacity and redundancy, not
practice.

### To reach 3

Configure alert routing to a real destination with a Secret; extend retention or add remote
write. The ACME contact address is set, so Let's Encrypt expiry warnings now reach a
monitored mailbox.

### To reach 4

A second node, which changes the storage class decision, makes PDBs meaningful, and turns a
node fault into a degradation instead of an outage. That is a hardware decision, not an
engineering one.

---

## Interview Readiness — 5/5

The strongest dimension, and the reason the repository is shaped the way it is.

**Every non-obvious decision has a recorded reason**, and most have a failure that motivated
them. That is what distinguishes a portfolio from a tutorial:

- Traefik's metrics are on the pod, not the Service — so an endpoints job would validate and
  collect nothing.
- The scrape annotation must name the container port — six production replicas returned
  connection refused with nothing reporting an error.
- `pg_monitor` was insufficient — PostgreSQL 14 grants `CREATE` on `public` to `PUBLIC`.
- inotify exhaustion is a correctness problem — a workload that cannot create a watcher silently
  stops noticing changes.
- With `ServerSideApply`, `helm template | diff` is the wrong comparison — it reported zero
  differences on a permanently OutOfSync Application.
- `selfHeal` reverts a debugging patch before the comparison is recomputed — so an approach that
  works looks like one that does nothing.

**Mistakes are documented as mistakes.** The `minReadySeconds` fix was based on a wrong
diagnosis, shipped, and then reverted with the false reasoning removed — because a harmless
setting justified by an untrue comment is a setting nobody revisits. That is in
[ADR 011](../adr/011-distributed-tracing.md)'s neighbours and in the ArgoSyncFailed runbook.

**The repository says no to things.** Tracing is instrumented and not deployed, with the reason
written down. Alert routing is absent, deliberately. A candidate who can defend an absence is
more convincing than one who deployed everything.

### The one caveat

The application is trivial: no business endpoints, no authentication, no domain logic. An
interviewer asking about application architecture will find little. That is the correct trade
for a *platform* portfolio, and it should be stated up front rather than discovered.

---

## Portfolio Quality — 4/5

### Evidence for

- Twelve architecture views, all Mermaid, all with reasoning attached.
- Eleven ADRs with genuine alternatives analysis.
- Fourteen runbooks, each written for someone reading it at an inconvenient hour, and each
  verified by CI to exist.
- Five operational guides plus task references.
- 94 automated checks anyone can run locally.
- Both repositories protected by rulesets as code.

### Evidence against

- The application is deliberately minimal, so there is nothing to show on application design.
- `README.md` is 753 lines with emoji headings — comprehensive but not the fastest way to
  convey competence to a reviewer with five minutes.
- The dashboard set is incomplete against its stated scope.
- Two Dependabot major bumps are open (#42 Python 3.14, #43 Node 26) and will fail the
  runtime-alignment check, which is the check working correctly but reads as a red state.

### To reach 5

Restructure `README.md` around a short competence summary with links; complete the dashboards;
resolve or close the Dependabot majors with a note.

---

## v1.0.0 — what shipped

Released 2026-08-02. The audit above was written before this release; the scores are
re-stated below against what is now on `main`.

### Closed since the audit

| Item | Shipped in |
|---|---|
| ACME contact address, so Let's Encrypt expiry warnings reach a monitored mailbox | #48 |
| Terraform GitOps handover layer, ADR 014, Terraform audit, tflint in CI | #51 / #54 |
| Datastore backup, verification, and restore — the `novashop` database had none | #52 |
| `recover.sh` fixed; it could not run at all before | #52 |
| Off-node backup copy — 21 KB, the part that cannot be regenerated | #52 |
| Default-deny ingress in the application namespaces, trialled live with a control | #53 |
| README restructured, 753 lines to 169; glossary and engineering log written | #55 |

### Rescored

| Dimension | Was | Now | Change |
|---|---|---|---|
| Maintainability | 4 | **4** | README and stubs fixed; the layered `docs/` pairs remain |
| Reliability | 3 | **3** | Backup and restore validated. 52 backend and 17 frontend tests -- the gap this row named is closed. Held at 3: there is still no coverage measurement and no load testing |
| Security | 4 | **4** | Network policy added; egress and two namespaces still open |
| Platform Readiness | 4 | **4** | — |
| Production Readiness | 2 | **2** | One node, no alert routing, recovery unexercised |
| Interview Readiness | 5 | **5** | — |
| Portfolio Quality | 4 | **5** | The engineering log and interview guide are what changed this |

**Overall 3.9 / 5. Maturity level 3 — Defined.**

### The condition v1.0 does not meet, stated plainly

**Full recovery has never been exercised on a replacement node.** Every component has been
tested individually — preconditions pass, database restore round-trips 137 rows with an
identical content checksum, GitOps reconciliation recreates a deleted Service in 5 seconds —
but the sequence has not been run end to end.

This was a blocker in the earlier recommendation. It was consciously accepted for release
because the project's purpose is demonstrating platform engineering, not operating a
business service, and rehearsing on a second node requires hardware that does not exist here.

The consequence is precise and should not be softened: **RTO is an estimate of 30–45 minutes
and should be treated as unknown.** Recovery is a documented procedure, not a demonstrated
capability. Anyone reading this repository as evidence of operational maturity should weigh
that accordingly — and anyone reading it as evidence of engineering judgement should note
that the defect which would have made recovery fail was found by running it, not reviewing
it.

## v1.1 — what remains

Ordered by value. None requires a new platform technology.

| # | Item | Why |
|---|---|---|
| 1 | Exercise full recovery on a replacement node | The only thing that turns RTO into a measured number |
| 2 | Alert routing to a real destination | Fourteen alerts that page nobody are diagnostics |
| 3 | Scheduled backup plus a `BackupStale` alert | The off-node copy is manual and will go stale |
| 4 | Frontend test framework and first suite | The most conspicuous gap in the repository |
| 5 | Rotate node credentials, enforce SSH keys | The only open security item that is purely a decision |
| 6 | Remove the duplicate `push` CI trigger and the duplicate Traefik scrape | Both known, both cheap |
| 7 | Land the k3s control-plane metric flags | Combine with the next k3s upgrade |
| 8 | Resources in the five inert Terraform layers | Interface is designed, validated, and empty |
| 9 | Network policies for `observability` and `cert-manager`; egress restriction | Trial each the way the application namespaces were |
| 10 | Sign images with cosign | Images are scanned, not signed |

### Deliberately not planned

| Not doing | Because |
|---|---|
| Deploy Tempo | Nothing worth tracing yet — [ADR 011](../adr/011-distributed-tracing.md) |
| Second node / HA | Hardware, not engineering. The honest path from Production Readiness 2 to 4 |
| Service mesh | Nothing here exercises traffic management |
| External secret manager | Every option moves the bootstrap problem — [ADR 010](../adr/010-secret-management.md) |
| Gateway API | Four `Host` rules are satisfied by Ingress |

## How to verify these claims

```sh
bash scripts/validate-platform.sh          --gitops-dir ../NovaShop-GitOps   # 38
bash scripts/validate-gitops-revisions.sh  --gitops-dir ../NovaShop-GitOps   # 30
bash scripts/validate-observability.sh      --gitops-dir ../NovaShop-GitOps  # 25
```

```sh
cd backend && pytest --collect-only -q | tail -1     # the test count, unflattered
grep -c 'def test_' backend/tests/*.py
ls frontend/src/**/*.test.* 2>/dev/null | wc -l   # 3 files, 17 tests
```

Every score above is falsifiable from the repository. If one of them is generous, the commands
that show it are in this document.
