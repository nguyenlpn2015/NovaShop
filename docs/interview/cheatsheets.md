# Cheat Sheets

For the night before, the morning of, and the five minutes before.

---

## Architecture Summary — one screen

```
Developer → PR → 6 checks → merge main → release.yml
                                          ├ validate (same reusable workflow)
                                          ├ publish  (build → Trivy → THEN login → push)
                                          └ promote  (latest, needs: publish)
                                                ↓
                                          GHCR, tagged by commit SHA
                                                ↓
                          NovaShop-GitOps  ← second merge, re-pin SHA
                                                ↓ polled
                                          Argo CD (novashop-root, app-of-apps)
                                                ↓
        ┌───────────────────┬────────────────────┬─────────────────────┐
   ApplicationSet      cert-manager          observability      AppProject
   dev/staging/prod    + Certificates        Prom/Graf/Loki     whitelist
        ↓                    ↓                Alloy/Alertmgr
     Traefik ← TLS ──────────┘
        ↑
  FortiGate DNAT ← Cloudflare DNS (DNS-only, not proxied)

Terraform: 7 layers → creates root Application → stops.
Datastores: PostgreSQL 14 + Redis on the NODE, reached at 10.10.1.45 over pod network.
```

**Numbers:** 12 Applications · 31 targets · 14 alerts / 14 runbooks · 93 gate checks ·
14 ADRs · 13 architecture views · 7 Terraform layers · 134 markdown files · 1 node.

---

## One-page revision notes

### The six constraints that explain everything

| | |
|---|---|
| One node | No rescheduling; recovery is a procedure |
| SQLite not etcd | Backup is a file copy |
| `local-path` only | Volumes cannot outlive the node |
| **5 certs / 168h** | Phased TLS; restore certs before reconciling; never delete a Certificate to retry |
| ~150% memory limits | Every container declares requests + limits, gate-enforced |
| Datastores on host | One alert covers three faults |

### The four structural guarantees

1. **Release cannot race CI** — same reusable workflow, one job graph
2. **Unscanned image cannot publish** — credentials acquired *after* Trivy
3. **`latest` moves last** — separate job, `needs: publish`
4. **Nothing tracks a branch** — every pin is a SHA, ancestor-verified, image-existence-checked

### The five traps

| Trap | Reality |
|---|---|
| `helm template \| diff` | Wrong pair under `ServerSideApply`. Compare `predictedLiveState` vs `normalizedLiveState` |
| `kubectl patch` to test | `selfHeal` reverts in ~3 min, before the comparison recomputes |
| `cp` the k3s SQLite file | Use `sqlite3 .backup`; k3s snapshots are etcd-only |
| `/ready` passing | Checks *reachable*, not *has data* |
| A NetworkPolicy test | kube-router needs seconds to program rules; use a settle + control |

### Three health endpoints

`/health` legacy · `/live` checks **nothing** (a dependency-aware liveness probe turns an
outage into a crash loop) · `/ready` checks PostgreSQL **and** Redis, 503 on failure.

### Sync waves

`-30` AppProject → `-20` cert-manager → `-15` Prometheus → `-14…-12` Grafana/Loki/Alloy/exporters
→ `0` Certificates → `10` applications.

### Edge phases

`http` (serve before any cert exists — HTTP-01 needs port 80) → `tls-baseline` (HTTPS available,
HTTP still served) → `tls-enforced` (redirect + HSTS). Phase is **detected**, never assumed.
Rollback serves `max-age=0` first.

### Backup tiering

577MB total → **21KB** actually backed up: 3 TLS Secrets, 2 ACME keys, PostgreSQL dump,
environment file. Everything else regenerates from Git.

### The four things to disclose unprompted

No schema, zero tables · tracing instrumented **not deployed** · 5 of 7 Terraform layers manage
nothing · alerts route nowhere.

---

## 30-minute interview preparation

**Minutes 0–5 — the numbers.** Read the Architecture Summary above until you can draw it from
memory. If you can draw the flow and say the six constraints, you can hold a 45-minute
conversation.

**Minutes 5–12 — three stories.** Have these ready verbatim-ish. Each is a complete arc:
symptom → wrong turn → root cause → what changed.

1. **The scrape port.** Annotation named the Service port; endpoints discovery connects to the
   pod IP; six replicas refused connections; nothing unhealthy, metric simply absent. → Gate now
   asserts scrape jobs by name and discovery roles.

2. **The Argo CD diff.** OutOfSync while sync said Succeeded; `helm template | diff` showed zero
   differences; two wrong fixes shipped and reverted; cause was `ServerSideApply` comparing a
   dry-run, and TypeMeta on a `volumeClaimTemplate`. → Runbook now names which pair to compare.

3. **`recover.sh` could not run.** Grepped `^DATABASE_URL=`; file declares `export
   DATABASE_URL=`; aborted at the first precondition on a healthy platform. Same bug had been
   fixed elsewhere. → Found in thirty seconds of execution after surviving every review.

**Minutes 12–20 — the three "why not" answers.** These separate senior from mid:

- **No Tempo:** a trace today is `GET /ready` plus two dependency calls. Instrumentation written,
  backend not deployed, reversal conditions stated.
- **No `kube-prometheus-stack`:** 100 inherited rules for multi-node conditions that cannot
  occur, none with runbooks. Fourteen authored rules evaluated against live data is better
  evidence.
- **No Vault/Sealed Secrets:** every option moves the bootstrap problem to a key that must
  survive a node rebuild on node-local storage. And Terraform state is plaintext.

**Minutes 20–26 — the weaknesses, out loud.** Say them before you are asked. Production
Readiness 2/5. Recovery documented not demonstrated. Zero frontend tests. Five inert Terraform
layers. Alerts route nowhere.

**Minutes 26–30 — the demo.** Open three tabs: the live site, `kubectl get applications`, and
`LEARNING_LOG.md`. Practise the ten-minute tour in
[../INTERVIEW_GUIDE.md](../INTERVIEW_GUIDE.md).

---

## 5-minute elevator pitch

> NovaShop is a single-node platform engineering portfolio. The application is deliberately
> trivial — no schema, no business endpoints — because the platform around it is the subject.
>
> It runs three environments on k3s behind Traefik with real Let's Encrypt certificates,
> delivered by Argo CD from a separate desired-state repository where every reference is a
> commit SHA that CI proves is an ancestor of main and corresponds to images that exist in the
> registry.
>
> What I would want you to look at is not the stack — it is the guardrails. There are 93
> automated checks before a merge, and each one was deliberately broken to prove it fails. They
> exist because this platform kept failing *silently*: a scrape annotation named the Service
> port instead of the container port, so six replicas returned connection refused and the metric
> simply did not exist. Nothing was unhealthy. No alert fired.
>
> The document I would open first is the engineering log — sixteen defects, how each was found,
> and what changed. Including the ones that reflect badly on me: I shipped two consecutive wrong
> fixes to an Argo CD diff because I was comparing the wrong pair of states, and the recovery
> script could not run at all for most of the project because it grepped for a variable
> declaration format the platform does not use. Every review had passed it. Thirty seconds of
> execution found it.
>
> It is not production-ready and the front page says so — Production Readiness two out of five.
> One node, no high availability, alerts that evaluate but route nowhere, and full recovery that
> has never been exercised end to end. I would rather you find those in my own audit than in the
> interview.

**Timing:** roughly 90 seconds spoken. Stop there and let them choose the thread.

**If they ask for shorter (30 seconds):**

> A single-node k3s platform with GitOps delivery, 94 pre-merge guardrails each negative-tested,
> and full observability with runbook-backed alerting. The interesting part is the engineering
> log — sixteen defects where the code read correctly and was wrong, including a recovery script
> that could not run and had passed every review. The audit is self-scored and the front page
> says Production Readiness is two out of five.

---

## Emergency lookups

| They ask about | Say |
|---|---|
| Scale | One node. Three environments, 1/2/3 replicas. Scaling *mechanics*, not capacity |
| Uptime SLO | None. No paging, so no SLO would be honest |
| Cost | A home lab node. No cloud spend |
| Team size | One. `enforce_admins: false` is defensible for that and not beyond it |
| Traffic | Effectively none. Alert thresholds are reasoned, not measured |
| Incidents | Sixteen defects in `LEARNING_LOG.md`, all self-inflicted, all documented |
| Compliance | Out of scope; no SBOM, no image signing |
| Multi-cluster | No. ApplicationSet generator would scale; nothing else was designed for it |
