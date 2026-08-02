# Question Bank

107 questions, every one answerable from this repository. Levels indicate the depth of
reasoning expected, not the seniority of the asker — a Principal interviewer will open with
beginner questions.

**How answers are structured.** Beginner and Intermediate questions get an answer and, where
it matters, the mistake to avoid. Senior, Staff, and Principal questions get the full
treatment: answer, reasoning, common mistakes, follow-ups.

**Answer out loud before reading.** Recognising an answer is not the same as producing one.

---

# Beginner — 20

*Establishing that you know what you built.*

### B1. What is NovaShop and what is it for?

A two-tier application — FastAPI backend, Next.js frontend — used as the payload for a
platform engineering portfolio. The application is deliberately trivial; the platform around
it is the subject. It runs on one Ubuntu node with k3s and is live at
`novashop.smartdev.vn`.

> **Mistake:** describing it as an e-commerce project. It has no schema and no business
> endpoints. Say so first.

### B2. How many environments, and how do they differ?

Three — development, staging, production — in namespaces `novashop-{env}`. They differ by
namespace, replica count (1/2/3), hostname, and resource sizing. One Helm chart, three values
files.

### B3. What Kubernetes distribution, and where does it run?

k3s v1.33.13, single node, Ubuntu 22.04 at `10.10.1.45`. 8GB RAM, 28GB disk.

### B4. What is GitOps in this project?

A second repository, `NovaShop-GitOps`, holds the desired state. Argo CD polls it and
reconciles the cluster. Nobody deploys by running `kubectl apply`.

### B5. Which repository holds what?

`NovaShop` — application code, Helm chart, platform component values, scripts, Terraform,
docs. `NovaShop-GitOps` — Argo CD Applications, values per environment, the phase composition.

### B6. What does Traefik do here?

It is the ingress controller, bundled with k3s. It terminates TLS and routes by `Host` header,
so four public names arrive on one address and are separated inside the cluster.

### B7. Where do the TLS certificates come from?

cert-manager requests them from Let's Encrypt using HTTP-01 validation. Three certificates,
one per environment, renewed automatically at about 60 days of a 90-day lifetime.

### B8. What is in the observability stack?

Prometheus for metrics, Grafana for dashboards, Loki for logs, Alloy as the log agent,
Alertmanager for alerts, plus node-exporter, kube-state-metrics, and exporters for PostgreSQL
and Redis.

### B9. Where do PostgreSQL and Redis run?

On the node itself, not in the cluster. Pods reach them at `10.10.1.45` over the pod network.

### B10. What triggers a deployment?

A merge in the GitOps repository that changes a pinned revision or image tag. Argo CD
converges within about three minutes.

### B11. How many Argo CD Applications are there?

Twelve. All Synced and Healthy at v1.0.0.

### B12. What is an ADR and how many are there?

An Architecture Decision Record — what was decided, what was rejected, and why. Fifteen,
in `adr/`.

### B13. What CI checks run on a pull request?

Five: Backend, Frontend, Security, Platform, Container Images. Plus Terraform on the
application repository.

### B14. What are the three health endpoints?

`/health` (legacy), `/live` (checks nothing), and `/ready` (checks PostgreSQL and Redis, and
returns 503 if either is unreachable).

### B15. How do you run this locally?

`cp .env.example .env && docker compose up --build`. No Argo CD, no TLS, no observability —
local development is for changing the application, not reproducing the platform.

### B16. What is the storage class?

`local-path`, shipped with k3s, and the only one. Volumes are node-local.

### B17. How are images tagged?

By the full 40-character commit SHA that produced them. `latest` is also moved, but only after
the whole build matrix succeeds.

### B18. What is Alertmanager configured to do?

Evaluate 14 rules and group them. It has one receiver with **no destination** — alerts are
visible and queryable but nothing pages anyone.

### B19. Where are the runbooks?

`docs/observability/runbooks/`, one per alert, fourteen of them. Each is the target of a
`runbook_url` in the rule.

### B20. What does `scripts/linux/bootstrap.sh` do?

Prepares the node, configures the datastores, installs k3s, Helm, and Argo CD, applies the
root Application, and then hands over to Argo CD. Every step is idempotent.

---

# Intermediate — 25

*Establishing that you understand the mechanisms.*

### I1. Why two repositories instead of one?

Separating code from desired state decouples the lifecycles. A single repository makes every
image build a potential deployment and every deployment a code change. The cost is two merges
per release, and that cost is the feature — the second merge is where a human decides a
verified image should go live. [ADR 003]

> **Mistake:** saying "because that is GitOps best practice." Give the lifecycle argument.

### I2. Why is `targetRevision` a commit SHA rather than a branch?

So the cluster cannot change underneath you. A gate additionally requires the SHA to be an
**ancestor of `origin/main`**, so a force-push cannot orphan what the cluster is pinned to.

### I3. Which references deliberately track `main`?

`novashop-root` and the ApplicationSet's own repository reference. Pinning the root Application
would mean no GitOps change could ever take effect without editing the cluster.

### I4. What is a sync wave and how are they used?

An Argo CD ordering annotation, most negative first. `-30` AppProject → `-20` cert-manager
(CRDs before Certificates) → `-15` Prometheus (ahead of what it observes) → `0` Certificates →
`10` applications.

### I5. What are the three edge phases?

`http`, `tls-baseline`, `tls-enforced`. Kustomize overlays composing different sets of Argo CD
objects.

### I6. Why are there phases at all?

Let's Encrypt allows five duplicate certificates per 168 hours, and HTTP-01 needs port 80 to
reach this node. A cluster that demands TLS before the edge is reachable cannot obtain the
certificate it is demanding, and retrying burns the weekly budget.

### I7. How does `verify.sh` know what to assert?

It detects the edge phase from live cluster state via `scripts/lib/edge-phase.sh`. A script
that can be *told* which phase it is in can be told the wrong one.

### I8. Why does `/live` check nothing?

A liveness probe that fails when the database is unreachable restarts a healthy process and
turns a datastore outage into a crash loop. `/ready` returns 503 instead, so the pod stops
receiving traffic and recovers on its own without a restart.

### I9. Why are Helm and Kustomize both used?

Helm for anything installed — one chart, three environments, parametric variation. Kustomize
for composing and ordering Argo CD objects into phases. Kustomize never patches rendered chart
output. [ADR 006]

> **Mistake:** "Kustomize for overlays, Helm for packaging." Too vague. Give the rule.

### I10. What does the `AppProject` whitelist do?

Restricts which resource kinds Argo CD may create. It is enforced **at sync time**, so a
manifest can render, validate, merge, and only then be refused — which happened with Loki's
`StatefulSet`.

### I11. How was that turned from a runtime failure into a pre-merge one?

`validate-observability.sh` renders every chart and fails the pull request if any rendered kind
is absent from the whitelist.

### I12. Why does Prometheus scrape Traefik with `role: pod`?

Traefik publishes metrics on the pod at port 9100 only; its Service exposes `web` and
`websecure`. An endpoints-based job renders, validates, deploys, and collects zero series.

### I13. Why is retention both 7 days and 2GB?

One disk holds the k3s datastore, PostgreSQL, and every volume. Time alone bounds nothing when
ingest can grow.

### I14. What replaced Promtail, and why two reasons?

Grafana Alloy. Promtail reached end of life in March 2026, and Alloy also terminates OTLP —
so one DaemonSet replaces two planned workloads. One fewer technology, not one more. [ADR 004]

### I15. Why does Alloy read container logs through the Kubernetes API?

So it needs no hostPath mount for them and cannot read outside its RBAC. The journal is the one
exception.

### I16. Why is `repeat_interval` twelve hours?

Anything shorter trains people to mute the channel, which is worse than not alerting.

### I17. What does the `NodeDown` inhibition rule do?

Suppresses every other alert for that instance. A down node also breaches CPU, memory, and
disk; reporting all four turns one fault into four pages pointing at the wrong problem.

### I18. Why does `CertificateExpiring` fire at 21 days rather than 7?

cert-manager renews at about 30 days remaining. Reaching 21 proves renewal has already been
failing for over a week, and it still leaves three weeks to fix it.

### I19. What does `fail-fast: false` solve here?

A frontend CVE was cancelling the backend job. Across three consecutive blocked releases there
was no way to tell whether the backend was clean.

### I20. Why are GitHub Actions pinned to commit SHAs?

A tag is a movable pointer. An action referenced by tag can change under a workflow that runs
with credentials.

### I21. Why is the Argo CD install manifest pinned by SHA-256?

Bootstrap downloads a large YAML file over the network and applies it with cluster-admin.
Pinning a version is not enough — a version is a mutable pointer at a URL. The digest makes
substitution detectable.

### I22. What is `local-path`'s effect on backups?

Volumes are node-local and cannot outlive the node. Prometheus, Loki, Grafana, and Alertmanager
volumes are therefore excluded from backup as explicitly disposable.

### I23. Why is Terraform in this project if there is no cloud?

To codify what Git cannot reproduce: GitHub repositories and rulesets, Cloudflare DNS, node
configuration, PostgreSQL roles and grants, and the Argo CD seed. DNS in particular existed
nowhere in the repository before. [ADR 012]

### I24. How do you run the validation gates without a cluster?

```sh
bash scripts/validate-platform.sh          --gitops-dir ../NovaShop-GitOps
bash scripts/validate-gitops-revisions.sh  --gitops-dir ../NovaShop-GitOps
bash scripts/validate-observability.sh     --gitops-dir ../NovaShop-GitOps
```

All three run offline and need no credentials.

### I25. Why is there no HorizontalPodAutoscaler or PodDisruptionBudget?

One node. An HPA has nowhere to scale to that changes anything, and a PDB would only block
drains. Their absence is deliberate, not an oversight.

---

# Senior — 30

*Establishing that you can reason about failure.*

### S1. Your monitoring says everything is healthy. Why might that be meaningless?

**Answer.** Because a scrape job whose relabel rules match nothing renders correctly,
schema-validates, deploys, and collects zero series — and that is indistinguishable from a
healthy system with nothing to report. This happened here: the backend's scrape annotation
named the Service port instead of the container port, so all six production replicas returned
connection refused, `novashop_http_requests_total` did not exist, nothing was unhealthy, and
no alert fired.

**Reasoning.** Endpoints-role discovery connects to the **pod IP**. A Service port in the
annotation is a port nothing listens on.

**Common mistakes.** Treating "no alerts" as evidence of health. Testing that a metric query
returns without checking that it returns *data*.

**Follow-ups.** *How would you catch it?* Assert required scrape jobs by name in CI, assert the
discovery role, and evaluate every alert expression against live data before merge — which is
how the duplicate Traefik scrape was found.

### S2. An Argo CD Application is OutOfSync but the sync reports Succeeded. How do you diagnose it?

**Answer.** Do **not** compare the rendered manifest to the live object. With
`ServerSideApply`, sync status compares `predictedLiveState` — a server-side apply dry-run —
against `normalizedLiveState`. Read all four states from
`/api/v1/applications/<app>/managed-resources`.

**Reasoning.** On this platform `helm template | diff` reported **zero differences** on an
Application that was permanently OutOfSync. The real difference was `apiVersion` and `kind`
that Kubernetes adds to a StatefulSet's `volumeClaimTemplate`, which the dry-run does not
reproduce.

**Common mistakes.** Re-syncing repeatedly. Assuming a Succeeded sync means convergence.
Comparing the wrong pair — which cost two consecutive wrong fixes here, both reverted.

**Follow-ups.** *How did you fix it?* `ignoreDifferences` on the two TypeMeta paths. *Why not
values?* The chart exposes `minReadySeconds`, and setting it would have changed runtime
behaviour to satisfy a diff engine — but that was the wrong diagnosis anyway.

### S3. You patch a live resource to test a hypothesis and nothing changes. What is the trap?

**Answer.** Every Application has `selfHeal: true`. The patch is reverted within about three
minutes — usually before Argo CD recomputes the comparison — so the status you read reflects
the **reverted** state.

**Reasoning.** This discarded a working fix here. Re-run with root's `selfHeal` paused, the same
approach reached Synced immediately.

**Common mistakes.** Reading "unchanged" as a negative result. **An inconclusive experiment is
not a negative result.**

**Follow-ups.** *How do you test safely?* Pause `selfHeal` on `novashop-root`, test, restore it.
Documented in the ArgoSyncFailed runbook.

### S4. Why does recovery restore certificates before Argo CD reconciles?

**Answer.** If Argo CD reconciles first, cert-manager finds no certificate Secret and requests a
new one, spending one of five duplicate certificates per 168 hours. A recovery rehearsed three
times in a week — which is what a recovery procedure *should* be — exhausts the budget.

**Reasoning.** cert-manager adopts an existing valid Secret and schedules normal renewal. The
ordering makes rehearsal free.

**Common mistakes.** Treating certificates as regenerable. Deleting a Certificate to "force a
retry" — it feels like a reset and spends one of five.

**Follow-ups.** *What if the budget is gone?* Debug on Let's Encrypt staging and only return to
production once staging issues cleanly.

### S5. A NetworkPolicy test says traffic is blocked. Why might you not believe it?

**Answer.** kube-router takes several seconds to program iptables for a new pod. A short-lived
probe that runs `wget` immediately is blocked by absence of rules, not by policy.

**Reasoning.** Here the first run reported BLOCKED for *same-namespace* traffic, which would
have meant the policy was broken. With a 20-second settle it reported REACHABLE. That made the
cross-namespace BLOCKED from the same run **equally suspect** — it was the answer I wanted,
produced by the same broken mechanism.

**Common mistakes.** Accepting the convenient half of a broken test. Running without a
no-policy control group.

**Follow-ups.** *What did you change?* Every probe re-run with a settle and a control.

### S6. Why is egress deliberately unrestricted?

**Answer.** The backend reaches PostgreSQL and Redis on the node's LAN address over the pod
network, and `/ready` checks both. An egress rule that gets that path wrong takes every replica
NotReady — a platform outage caused by a hardening change.

**Reasoning.** Ingress carries most of the value: it stops a compromised pod in one environment
reaching pods in another, which is the realistic lateral-movement path with three environments
on one node.

**Common mistakes.** Treating "default-deny everything" as automatically correct.

**Follow-ups.** *How would you add it safely?* One namespace, live, with datastore reachability
checked before and after — the way ingress was trialled.

### S7. What does `/ready` not tell you, and why does that matter in recovery?

**Answer.** It checks PostgreSQL is *reachable*, not that it holds data. Skip the data restore
and pods go Ready, Applications report Healthy, no alert fires, and the application serves an
empty database. Nothing on this platform catches that.

**Follow-ups.** *How is it mitigated?* `recover.sh` restores datastore contents before Argo CD
reconciles, and the restore script prints the table count.

### S8. Why can you not `cp` the k3s datastore?

**Answer.** k3s writes to SQLite continuously. A byte-for-byte copy can capture a half-written
page and produce a file that looks fine and is corrupt — discovered at the moment it is needed.
Use `sqlite3 .backup`, the online backup API, then verify with `PRAGMA integrity_check`.

**Reasoning.** k3s ships snapshot support for **etcd only**. Single-server k3s uses SQLite, so
this has to be handled explicitly.

### S9. Your backup is 27MB on-node and volumes are 550MB. What do you actually back up?

**Answer.** **21 KB.** Three TLS Secrets, two ACME account keys, a PostgreSQL dump, and the
platform environment file — the part that cannot be regenerated from Git.

**Reasoning.** Almost everything else is reconciled by Argo CD. Prometheus and Loki volumes are
observational and bounded by retention; including them would grow the set fifty-fold to protect
data that expires on its own.

**Follow-ups.** *Where does it live?* Off the node. A backup on the disk it protects addresses a
bad migration and nothing else — and the only failure mode this platform has is losing the node.

### S10. How do you guarantee an unscanned image never reaches the registry?

**Answer.** Ordering inside the `publish` job: build loads the image locally, Trivy scans, and
**only then** does the workflow log in to GHCR and push. Registry credentials are not acquired
until the scan passes.

**Common mistakes.** Relying on `if: success()` — a condition someone can weaken. Scanning after
push.

**Follow-ups.** *What enforces the ordering?* Nothing mechanical. It is a convention a future
edit could break, and the audit says so.

### S11. How do you guarantee release never races CI?

**Answer.** `release.yml` does not wait for `ci.yml` or inspect its result. It calls the same
`validation.yml` as a reusable workflow, so validation and publication are nodes in **one job
graph** with `publish` declaring `needs: validate`.

**Reasoning.** Any check-then-act across two workflow runs can only narrow the window, never
remove it.

### S12. What does `validate-gitops-revisions.sh` prove that the others do not?

**Answer.** That the desired state is *deployable*: every pin is a 40-hex SHA and an ancestor of
`origin/main`, both components come from one commit, nothing is `latest`, and **both images
exist in GHCR**.

**Reasoning.** A pin to a commit whose release failed renders and validates perfectly and
produces `ImagePullBackOff`. Only a registry query catches it.

### S13. Why does the observability gate assert scrape jobs by name?

**Answer.** Because a job silently disappearing from the rendered configuration is invisible
otherwise — the render is still valid YAML and the deploy still succeeds.

### S14. Why did `pg_monitor` turn out to be insufficient?

**Answer.** PostgreSQL 14 grants `CREATE` on the `public` schema to `PUBLIC`; PostgreSQL 15
removed it. So the metrics exporter could create tables in the application's database.

**Reasoning.** Found by *attempting* a write as the exporter rather than assuming the role was
read-only.

**Common mistakes.** Verifying only that the restriction works, not that the application still
works. A permission fix that quietly breaks the application is worse than the permission.

### S15. Why remove npm from the frontend runtime image?

**Answer.** Trivy reported CVEs in `tar`, `sigstore`, and `brace-expansion` that were **not** in
`package-lock.json`. They were vendored inside the Node base image. Nothing in the running
container needs a package manager, so npm, npx, corepack, and yarn were removed.

### S16. What is inotify exhaustion and why is it a correctness problem?

**Answer.** The kernel default is 128 instances; this node reached 140. Every config reloader,
log collector, dashboard sidecar, and certificate watcher consumes one. Traefik logged
`failed to create fsnotify watcher: too many open files`.

**Reasoning.** A workload that cannot create a watcher **does not fail**. It keeps running with
what it loaded at startup and silently stops noticing changes — here, a renewed certificate or a
synced manifest that never takes effect.

### S17. HSTS is enabled and you need to roll back. What breaks?

**Answer.** HSTS tells browsers to refuse plain HTTP for `max-age`. Reverting the edge to HTTP
does not degrade gracefully — previous visitors get a connection refusal with no click-through.

**Answer, continued.** Rollback serves `max-age=0` first so browsers release the pin, then
removes HTTPS.

### S18. Why is `websecure` named explicitly on production Ingress objects?

**Answer.** Leaving the entrypoint implicit can bind a router to `web` only, serving plain HTTP
with nothing reporting an error.

### S19. How do you know NetworkPolicy is actually enforced?

**Answer.** Prove it before writing any: k3s runs kube-router's netpol controller — 2 processes,
123 iptables chains — and a deny-all in a probe namespace took a pod from REACHABLE to BLOCKED.

**Reasoning.** A NetworkPolicy on a cluster that ignores them is the worst kind of control: it
appears in `kubectl get` and does nothing.

### S20. Why does one NetworkPolicy rule admit the whole node network?

**Answer.** Readiness and liveness probes originate on the **node**, not from a pod. A
namespace-only rule takes every replica NotReady the moment it applies, and with no ready
endpoint Traefik returns 503. Scoped to `10.10.1.0/24` rather than left open.

### S21. Why is `MANAGEMENT_CIDR` required before UFW is enabled?

**Answer.** The operator workstation is `192.168.3.2`, which is **not** inside `10.10.0.0/16`. A
rule written for the node's own subnet would look reasonable and lock the operator out of the
only node, with no second machine to fix it from.

**Reasoning.** This is the one bootstrap step where a sensible-looking default is worse than
refusing to act.

### S22. How does the platform prevent a chart upgrade from silently regressing?

**Answer.** `validate-observability.sh` asserts properties a render cannot: required jobs by
name, Traefik's discovery role, that Loki has not reintroduced caches/gateway/canary/MinIO, that
every rendered kind is whitelisted, and that every container declares requests and limits.

### S23. What does `ApplyOutOfSyncOnly=true` buy you?

**Answer.** Argo CD applies only resources that differ, rather than the whole set each sync. On
a single node with limited API throughput that reduces churn, and it makes sync logs readable
when something is genuinely wrong.

### S24. What happens to a resource you delete from Git?

**Answer.** It is pruned — `prune: true` on every Application. `PruneLast=true` defers pruning
until after other operations, and `PrunePropagationPolicy=foreground` waits for dependents.

**Follow-ups.** *What is the hazard?* Removing a tracked resource from an Application's source
deletes it. Removing `namespace.yaml` from the Prometheus Application would delete the
`observability` namespace and everything in it — which is why that handover was not done.

### S25. Why is Prometheus at sync wave -15?

**Answer.** Ahead of the workloads it observes, so a target appearing during a rollout is
collected from its first moment rather than after things settle.

### S26. How do you tell "not collected" from "healthy with nothing to report"?

**Answer.** Check whether the series exists at all — `count({__name__=~"novashop_.*"})` — then
check the target list for that job. No series means not collected.

### S27. Why does the platform have three separate validation scripts rather than one?

**Answer.** Different inputs and different failure domains. `validate-platform.sh` renders
desired state; `validate-gitops-revisions.sh` needs network access to GHCR;
`validate-observability.sh` needs Docker for `promtool`. Separating them means a network outage
does not fail schema validation.

### S28. What did negative-testing the gates actually find?

**Answer.** That the runbook check reported its own artefact count as a failure. Command
substitution strips trailing newlines, so a clean run collapsed to one line and the count was
read as the problem list — the gate failed on a repository where every alert was correct.

**Reasoning.** A gate that has only ever passed proves nothing.

### S29. Why is the `argocd` namespace the only one Terraform owns?

**Answer.** It is the only one Argo CD does not reconcile — created by the bootstrap script
before Argo CD existed, `managed-by: kubectl`, no tracking annotation. `cert-manager` and
`observability` are tracked resources, and the three `novashop-*` namespaces are covered by
`managedNamespaceMetadata` on the ApplicationSet, which reapplies their labels every sync.

**Common mistakes.** Trusting `kubectl get namespace -o yaml` — it shows nothing suggesting Argo
CD owns those three.

### S30. Why can `kubernetes_manifest` not manage the root Application?

**Answer.** It does not support import, and the object already exists. Declaring it plans a
create; the create fails on conflict; and deleting first cascades, because the Application
carries `resources-finalizer.argocd.argoproj.io`.

---

# Staff — 20

*Establishing that you can decide, and defend the decision.*

### T1. Defend not deploying distributed tracing.

**Answer.** The backend has no business endpoints and the frontend calls it from the browser. A
trace today contains `GET /ready`, one `asyncpg SELECT 1`, and one Redis `PING`. That
demonstrates plumbing, not tracing, and a Tempo dashboard showing nothing but health checks is
weaker evidence of competence than an honest absence.

**Reasoning.** The instrumentation *is* written — sampling strategy, guarded imports, endpoint
exclusions — because that is the part with design decisions worth reviewing. Deploying a
backend for it is not the interesting half.

**Common mistakes.** Claiming tracing exists. Framing the absence as "not got to it yet" rather
than a decision with stated reversal conditions.

**Follow-ups.** *What would change your mind?* A business endpoint spanning both datastores; a
server-side rendering path; or a decision to expose an authenticated public OTLP endpoint for
browser RUM.

### T2. Why reject `kube-prometheus-stack`?

**Answer.** Two reasons. Its default resource requests do not fit alongside PostgreSQL, Redis,
and Loki on 8GB without trimming away its advantage. More importantly its ~100 alert rules would
be **inherited rather than authored** — mostly for multi-node conditions that cannot occur here,
none carrying a runbook.

**Reasoning.** Fourteen rules whose expressions were each evaluated against live data is better
evidence of engineering than 100 that arrived in a chart.

**Follow-ups.** *When would you use it?* A multi-node cluster with a team, where inherited
coverage beats authored coverage because nobody has time to write 100 rules.

### T3. Why Argo CD over Flux?

**Answer.** Two platform-specific reasons. Multi-source Applications compose a chart from one
repository with values from another directly; Flux's `HelmRelease` equivalent is less direct.
And Flux has no `AppProject` equivalent — that boundary would need Kyverno or an admission
controller, which means adding a technology to get a property Argo CD includes.

**Reasoning.** For a single operator the web UI is a genuine diagnostic advantage rather than
attack surface to justify.

**Common mistakes.** Claiming Flux is worse. It is smaller and arguably cleaner; the ADR says so.

### T4. Why is Terraform's boundary drawn where it is?

**Answer.** Terraform manages what Argo CD does not reconcile, and never an object it does. With
`selfHeal` on, a Terraform-managed Deployment is reverted every three minutes and `plan` never
converges. This is a functional constraint, not a preference.

**Reasoning.** The boundary was drawn twice. The first version was reasoned from principle; the
second came from reading the cluster, which revealed that three namespaces are reconciled
invisibly.

**Follow-ups.** *Could Terraform own the whole GitOps tree?* Yes — create all twelve
Applications directly and drop the app-of-apps. Rejected because it removes the two-merge review
and turns an image tag change into `terraform apply`.

### T5. Justify the `pg` state backend.

**Answer.** No cloud account exists. PostgreSQL already runs on the node, is already in the
platform backup, and the `pg` backend gives real state locking. It adds no infrastructure.

**Reasoning.** The cost is an ordering dependency: PostgreSQL must be restored before Terraform
runs at all. Layers that run before the node exists start on local state via an override file
and migrate.

**Common mistakes.** Proposing Terraform Cloud — a hosted dependency and an account to hold
state for a home lab.

### T6. Why is `run_bootstrap` false by default?

**Answer.** On a running cluster the scripts are a long no-op that waits on Deployments and
rollouts, which surprises whoever ran `terraform apply` expecting a quick change. True on a
fresh node or during recovery, which is where the layer earns its place.

### T7. Defend managing repository registration Secrets in Terraform after rejecting secrets in state.

**Answer.** Both repositories are **public**, so the Secret holds a `url`, a `type`, and no
credential. The exception is enforced rather than trusted: a `check` block refuses `password`,
`sshPrivateKey`, `tlsClientCertKey`, `githubAppPrivateKey`, `bearerToken`, and a variable
validation refuses `ssh://` URLs because they imply a deploy key.

**Follow-ups.** *Why no `project` scoping?* Scoping a repository to a project restricts every
*other* project from using it, breaking the `novashop-platform` Applications that render from
the same repositories.

### T8. How would you introduce egress NetworkPolicies without an outage?

**Answer.** The way ingress was introduced. Render the policies, apply to **one** namespace on
the live cluster, verify pods stay Ready, the edge still returns 200, and Prometheus still
scrapes — then remove them so GitOps creates them as tracked resources.

**Reasoning.** The specific risk is the datastore path. `/ready` checks PostgreSQL and Redis, so
a wrong egress rule takes every replica unready.

**Follow-ups.** *What control group?* A namespace with no policy, probed in the same run — and a
settle period, because kube-router propagation produced a false result.

### T9. The platform is overcommitted at ~150% memory limits. Defend that.

**Answer.** Limits over 100% is safe while workloads sit near their requests, and requests are
at ~44%. Every container declares both, enforced by a gate. `MemoryHigh` watches for the point
where overcommit stops being free, and its runbook says to reduce replicas before raising
thresholds.

**Reasoning.** Three production replicas on one node demonstrates scaling mechanics, not
capacity. That is the honest reason the number is what it is.

### T10. Why does the observability namespace run Pod Security `privileged`?

**Answer.** node-exporter needs host network and host filesystem mounts to report anything about
the node, which `restricted` forbids. The workloads there are platform components from pinned
upstream charts, not application code, and the namespace holds no application workload.

**Reasoning.** The posture is asserted by a Terraform `check` block, so a change to it is
reported at plan time rather than discovered.

### T11. What is your backup tiering argument?

**Answer.** Back up what Git cannot reproduce. Tier 0 is irreplaceable — ACME account key, TLS
certificates, the environment file. Tier 1 is business data. Tier 2 is convenience — the k3s
datastore, rebuildable in ten minutes. Redis and observability volumes are excluded.

**Reasoning.** That reduces 577MB to 21KB, which is what makes an off-node copy trivial.

### T12. Your RTO is 30–45 minutes. Defend that number.

**Answer.** I would not defend it — I would say it is an estimate and should be treated as
unknown. Measured components: preconditions ~10s, single resource reconcile 5s, slowest
Application sync 62s, database restore under 5s. Unmeasured and dominant: OS preparation, k3s
install, image pulls.

**Reasoning.** Stating an unverified RTO as a number is the kind of claim this platform exists
to avoid making.

### T13. Why does the release note lead with limitations?

**Answer.** Because a release claiming everything works fails the moment someone probes it, and
because the audit already scores Production Readiness 2/5. Consistency between the front page
and the audit is what makes both credible.

**Reasoning.** I recommended against v1.0 on the grounds recovery was unexercised, was
overruled with a reason, and recorded both in the release.

### T14. What is the argument against adding Kyverno?

**Answer.** Pod Security Admission already enforces `restricted` and demonstrably rejects
non-compliant pods — it refused my own diagnostic pod. RBAC and the `AppProject` whitelist cover
authorization. Kyverno would duplicate an existing control and add a webhook to secure.

**Follow-ups.** *When would you add it?* When a policy is needed that PSA cannot express —
image registry allowlists, or required labels across namespaces.

### T15. How do you decide what deserves a guardrail?

**Answer.** Whether the failure is silent. A loud failure is caught by the next person to look. A
silent one — a scrape job collecting nothing, a pin to a nonexistent image, an alert whose
runbook does not exist — is caught by nobody, so it gets a gate.

**Reasoning.** Every guardrail here traces to a class of defect that actually occurred.

### T16. Why is documentation treated as an engineering artefact?

**Answer.** Because it drifts toward optimism and nothing detects it. Two documents claimed a
backup captured the SQLite datastore and runtime environment. It captured Kubernetes Secrets.
Someone reads that claim and stops looking — which is how the database went unprotected while
the repository described a working backup.

**Follow-ups.** *What detects it now?* A link checker in CI, and a habit of verifying every
number in the README against the live platform before release.

### T17. What would you do differently if starting again?

**Answer.** Three things. Not stack pull requests — #51 was reported MERGED and landed nowhere.
Run `recover.sh` in week one rather than month three. And treat a test that agrees with me as
suspect by default.

### T18. How do you keep 121 documents accurate?

**Answer.** Imperfectly. A link checker catches structural rot. Version numbers are verified
against the live platform at release. What is not automated is semantic drift — the Ubuntu
version was wrong in five documents until a `pg_dump` string exposed it.

**Follow-ups.** *What would you automate next?* Asserting that every version string in the docs
matches what is deployed.

### T19. Argue for or against the two-repository split at this scale.

**Answer.** For, but narrowly. At one operator and one cluster the overhead is real — two merges
for every release. What justifies it is that the desired state must be replayable onto a
replacement node, and that CI holds no cluster credentials.

**Reasoning.** At ten clusters the answer is obvious. At one it is a judgement call, and it
should be presented as one.

### T20. What is the single biggest weakness, and what would you do about it?

**Answer.** Full recovery has never been exercised on a replacement node. Every component is
tested — preconditions, a database restore round-tripping 137 rows with an identical checksum, a
Service reconciled in 5 seconds — but not the sequence.

**Reasoning.** The related point matters more: the defect that would have made recovery fail was
found by *running* the script, not reviewing it. `recover.sh` grepped `^DATABASE_URL=` while the
file declares `export DATABASE_URL=`. Every review had passed it.

---

# Principal — 12

*Establishing judgement about the system as a whole.*

### P1. What is this platform's actual risk profile?

**Answer.** Concentrated in one node and one operator. The realistic failure is node loss, and
the mitigation — recovery — is documented and unproven. Everything else is degradation:
certificates expire with three weeks of warning; overcommit is monitored; drift self-heals.

**Reasoning.** Nothing here is protected against operator error at the GitOps layer, because
`selfHeal` means a bad merge propagates in three minutes. The control is the pre-merge gates,
which is why there are 93 of them.

### P2. Where does the guardrail approach break down?

**Answer.** Guardrails catch classes of failure that have already been seen. They caught nothing
about the stacked pull request that merged into its base — CI was green, `gh pr list` showed
nothing outstanding, and 1,091 lines landed nowhere.

**Reasoning.** Every gate encodes a past incident. The next novel failure is by definition
outside them, which is why the engineering log matters more than the gate count.

### P3. If this platform had to serve real traffic tomorrow, what is the ordered list?

**Answer.** Alert routing first — 14 good alerts that page nobody are diagnostics. Then a second
node, which changes the storage class decision and makes PDBs meaningful. Then WAL archiving to
move RPO from 24 hours to minutes. Then the recovery rehearsal.

**Reasoning.** Ordered by what fails first under real traffic, not by effort.

### P4. Critique your own ADRs.

**Answer.** ADR 002's rejection of k0s is the weakest — "ecosystem familiarity" is a preference
dressed as analysis, and the ADR admits it. ADR 012's rejection of Ansible is thin; Ansible is
genuinely the right tool for the node layer and the argument against it is mostly "not adding a
technology."

**Reasoning.** The strongest are 010 and 011, because both say no and both state reversal
conditions.

### P5. What would you tell an engineer inheriting this?

**Answer.** Read `LEARNING_LOG.md` first, then `AUDIT.md`. The architecture views describe what
exists; those two describe what went wrong and what is still weak, which is what you need on day
one. Then run the three gates — they will fail if something has drifted.

**Warn them:** `selfHeal` reverts live edits, `ServerSideApply` changes what "diff" means, and
five Terraform layers manage nothing despite looking complete.

### P6. Is 94 pre-merge checks the right number?

**Answer.** The count is not the metric. What matters is that each was negative-tested and each
maps to a failure class that occurred. A gate nobody has broken deliberately is a gate that has
only ever passed.

**Reasoning.** The risk of many gates is slow feedback and normalised failure. Here they run
offline in seconds, so neither has materialised — but at three times the count it would.

### P7. How would you scale this design to twenty services and five engineers?

**Answer.** Most of it holds. The ApplicationSet generator scales; the gates scale; the ADR
habit scales.

What breaks: one Helm chart for all services becomes wrong — you want a chart per service or a
library chart. The `AppProject` whitelist becomes a bottleneck as each team needs different
kinds. And `enforce_admins: false` stops being defensible the moment there is a second engineer.

### P8. What is the cost of the honesty in this repository?

**Answer.** It caps the impression. A reader who wants "production-ready Kubernetes platform"
finds Production Readiness 2/5 on the front page.

**Reasoning.** The trade is deliberate: the claims that remain are checkable, and a reviewer who
verifies one and finds it true will extend credit to the rest. A repository that oversells gets
one probe before everything is suspect.

### P9. Where is complexity unjustified?

**Answer.** Seven Terraform layers for six resources. The layering is right in principle —
separate state, separate blast radius — but at this scale a single root module would have been
defensible and 74 variables would not exist.

**Reasoning.** The counter-argument is that the layers are the demonstration. That is true and
it is also the argument every over-engineered system makes.

### P10. Reconcile "avoid unnecessary complexity" with 15 ADRs and 121 documents.

**Answer.** Complexity is in the running system, not the explanation of it. The running system
is small: one node, eight Helm templates, twelve Applications, no mesh, no operator, no
admission controller beyond built-in PSA.

**Reasoning.** The documentation is large because the audience is a reviewer who was not there.
If the audience were a team who built it, most of it would be over-explanation.

### P11. What would make you reject this design in a real review?

**Answer.** If it claimed to be production-ready. The architecture is sound for its stated
purpose and unsound for serving customers — single node, no HA, no paging, unproven recovery.

**Reasoning.** The design is not wrong; a mismatch between the design and its claimed purpose
would be. The repository avoids that, and that is what makes it reviewable.

### P12. What does this project prove about the engineer who built it?

**Answer.** That they distrust their own conclusions. Control groups in NetworkPolicy tests,
negative-tested gates, self-scored audits, recorded disagreements, and a log of sixteen defects
where the code read correctly and was wrong.

**Reasoning.** It does not prove they can operate at scale, run an on-call rotation, or work in
a team — none of that is demonstrable in a single-node lab, and the repository does not claim
it.
