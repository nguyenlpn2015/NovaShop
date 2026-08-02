# Engineering Log

Defects found on this platform, how each was found, and what it changed.

This is the most useful document in the repository for judging the engineering, because
every entry is a case where **the code read correctly and was wrong**. Reviews passed all of
them. Running the thing found them.

## The pattern

Most entries below share one shape: **something rendered, validated, deployed, and did
nothing**, while every dashboard stayed green. That failure mode — silent success — is what
most of the platform's guardrails now exist to catch.

---

## Observability

### Scrape annotation named the Service port, not the container port

`prometheus.io/port: "80"` on the backend Service. Endpoints-role discovery connects to the
**pod IP**, so all six production replicas returned connection refused.

Nothing was unhealthy. No alert fired. `novashop_http_requests_total` simply did not exist,
which is indistinguishable from an application serving no traffic.

**Found by** querying for a metric that should have had data, then probing the pod directly:
`:8000/metrics` returned 200, `:80/metrics` was refused.

**Changed** the annotation to `targetPort`, and added a gate check that exporter Services
carry scrape annotations at all.

### Traefik metrics exist only on the pod

Traefik's Service exposes `web` and `websecure`. An endpoints-based scrape job renders
correctly, schema-validates, deploys, and collects zero series.

**Changed** the job to `role: pod`, and `validate-observability.sh` now asserts that
explicitly — because the next person to tidy the scrape config would not know.

### Journal logs had no `unit` label

`stage.labels` promotes values from the *extracted map*, which earlier stages populate. For
journal input that map is empty, so the label was never created and filtering by systemd
unit was impossible.

**Changed** to `discovery.relabel` with `relabel_rules`, which promotes from the
`__journal_*` internal labels.

### Every request was labelled `unmatched`

The route-label helper iterated `app.routes`, which misses FastAPI's `_IncludedRouter`. Every
request got `route="unmatched"`, making the metric useless while looking populated.

**Found by** a test written alongside the instrumentation. The one entry in this log caught
before deployment.

**Changed** to read `scope["route"]` after routing completes.

### Traefik is scraped twice

The dedicated `traefik` job and the chart's default annotation-based `kubernetes-pods` job
both scrape the same pod. Seven duplicate series.

A ratio survives this — numerator and denominator double together — but `histogram_quantile`
over doubled buckets is only accidentally right.

**Found by** evaluating every alert expression against live data before merge, specifically
to check that label selectors match real series.

**Changed** the edge alerts to pin `job="traefik"`. Removing the duplicate needs a chart
default override and is still open.

---

## GitOps and Argo CD

### `helm template | diff` is the wrong comparison

`novashop-prometheus` sat OutOfSync while sync reported Succeeded. Comparing the rendered
manifest against the live object showed **zero differences**.

With `ServerSideApply`, sync status is decided by `predictedLiveState` against
`normalizedLiveState` — a server-side apply dry-run, not the manifest. The real difference
was `apiVersion` and `kind` that Kubernetes adds to a StatefulSet's `volumeClaimTemplate` and
the dry-run does not reproduce.

**Cost:** two consecutive wrong fixes. The first chased `minReadySeconds`, which the wrong
comparison flagged and the right one never did. The second "fixed" it in chart values on that
false premise, and had to be reverted.

**Changed** to `ignoreDifferences` on the two TypeMeta paths, and the `ArgoSyncFailed` runbook
now names which pair of states to compare.

### An inconclusive experiment is not a negative result

Testing `ignoreDifferences` with a live `kubectl patch` while root's `selfHeal` was active:
the patch was reverted before Argo CD recomputed, the status read unchanged, and I concluded
the approach could not work.

Re-run with self-heal paused, the same approach reached Synced immediately.

**Changed** the runbook to document pausing self-heal for any live experiment.

### Three namespaces look unowned and are not

`novashop-development`, `-staging`, `-production` carry **no Argo CD tracking annotation**.
`kubectl get namespace -o yaml` shows nothing suggesting Argo CD owns them. It does:
`managedNamespaceMetadata` on the ApplicationSet reapplies their labels every sync.

**Found by** checking ownership before declaring them in Terraform, rather than after.

**Changed** the Terraform Kubernetes layer to own one namespace instead of six, and
[ADR 013](../adr/013-terraform-kubernetes-boundary.md) records why.

### A stacked pull request merged nowhere

#51 was stacked on #50's branch. GitHub reported it **MERGED** — into its stacked base, which
#50 had already merged into `main`. 1,091 lines of reviewed work reachable only from an
orphaned branch.

`gh pr list` showed nothing outstanding. CI was green. No tooling catches this.

**Found by** counting Terraform layers while gathering facts for a readiness review.

**Changed** nothing in tooling, because nothing would catch it. Recorded so the next stack is
retargeted to `main` before its base merges.

---

## Recovery and backup

### The recovery script could not run

`recover.sh` aborted at its first precondition on a completely healthy platform. It grepped
`^[[:space:]]*DATABASE_URL=`; the file declares `export DATABASE_URL=`. Zero matches.

**The same mismatch had already been found and fixed in `configure-datastores.sh`.** It
survived here because `recover.sh` had never been executed, and the logic reads correctly.

**Found by** running it. Thirty seconds.

**Changed** to accept the optional prefix, and added `--preconditions-only` so inspecting
readiness cannot start a rebuild.

### The database had no backup, and the documentation said otherwise

Two architecture documents claimed `backup-platform-state.sh` captured the SQLite datastore
and the runtime environment. It exports Kubernetes Secrets and nothing else.

That is how a gap survives: someone reads the claim and stops looking.

**Changed** — `backup-datastores.sh`, `verify-backup.sh`, `restore-datastores.sh`, and the
false claims corrected.

### The backup lived on the disk it protected

Every backup was on the node whose loss is the platform's only real failure mode.

**Changed** — the irreplaceable material is **21 KB**. The on-node set is 27 MB and the
volumes are 550 MB; almost all of it regenerates from Git. Moving 21 KB off-node was the
whole fix.

### Permissions and working directory in the backup path

Three defects in one script, all found by running it:

- The backup directory is `0700` root-owned, so `postgres` could not read the dump it had
  just written. Fixed by running `pg_restore --list` as root and feeding the archive on
  **stdin** during restore, rather than loosening permissions on a directory of database dumps.
- `su` inherits the working directory; running from `/root/NovaShop` produced
  `could not change directory` on every PostgreSQL call.
- `IFS` was newline-and-tab — correct for filenames, wrong for a space-separated manifest.
  Every artefact read as missing.

---

## Security

### A test that produced the right answer for the wrong reason

The first NetworkPolicy trial reported `BLOCKED` for same-namespace traffic, which would have
meant the policy was broken. It was a race: kube-router takes seconds to program rules for a
new pod, and a short-lived probe ran `wget` before its rules existed.

The cross-namespace `BLOCKED` from the same run was **equally suspect** — it was the answer I
wanted, produced by the same broken mechanism.

**Changed** — every probe re-run with a settle period and a no-policy control group. Only
then were the results sound.

### `pg_monitor` was not read-only

PostgreSQL 14 grants `CREATE` on the `public` schema to `PUBLIC`; PostgreSQL 15 removed it.
So the metrics exporter could create tables in the application's database.

**Found by** attempting a write as the exporter rather than assuming the role was sufficient.

**Changed** — revoked from `PUBLIC`, granted to the application role only, and verified both
that the exporter is refused *and* that the application still succeeds. A permission fix that
quietly breaks the application is worse than the permission.

### npm was vulnerable inside the image, not in the lockfile

Trivy reported CVEs in `tar`, `sigstore`, `brace-expansion` — none present in
`package-lock.json`. They were vendored inside the Node base image.

**Changed** — npm, npx, corepack, and yarn removed from the runtime stage. Nothing in the
running container needs a package manager.

---

## Node and platform

### inotify exhaustion is a correctness problem

Traefik logged `failed to create fsnotify watcher: too many open files`. The kernel default
is 128 instances; the node reached 140.

A workload that cannot create a watcher **does not fail**. It keeps running with whatever it
loaded at startup and silently stops noticing changes — which here means a renewed
certificate or a synced manifest that never takes effect.

**Changed** — `configure-node-limits.sh`, and the limit added to bootstrap.

### The node is Ubuntu 22.04, not 24.04

Five documents said 24.04. Found while reading a `pg_dump` version string.

Small, and the reason it is here: documentation drifts toward what the author believed rather
than what is true, and nothing detects it.

---

## What changed structurally

Each class of defect produced a guardrail rather than only a fix:

| Defect class | Guardrail |
|---|---|
| Silent collection failure | `validate-observability.sh` asserts required jobs by name, discovery roles, and that every alert's runbook resolves to a real file |
| Wrong desired state | `validate-gitops-revisions.sh` proves every pin is an ancestor of `main` and every image exists in GHCR |
| Sync-time rejection | Every rendered kind is checked against the AppProject whitelist **before merge** |
| Unverifiable claims | Every score in [AUDIT.md](AUDIT.md) ships with the command to falsify it |
| Untested procedures | Recovery, backup, and NetworkPolicy are exercised against the live platform, with control groups |

## The habit worth taking from this

**Run it.** Every entry here passed review. The ones that cost the most — two wrong fixes on
the Argo CD diff, an inconclusive experiment read as a negative result, a race that produced
the expected answer — cost that much because the evidence was accepted before it was sound.

The corollary is uncomfortable: a green dashboard is evidence that nothing is *reporting* a
problem. On this platform it has repeatedly not been evidence that nothing is wrong.
