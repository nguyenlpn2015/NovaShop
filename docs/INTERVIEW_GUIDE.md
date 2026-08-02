# Interview Guide

A walkthrough of this platform for a technical interview, and the questions I expect.

**This is the live demo script.** For preparation — the full teaching guide, 107 questions
across five levels, and cheat sheets — see [interview/](interview/).

## The ten-minute tour

If you have one screen and ten minutes, this order works.

**1 — What it is.** One node, three environments, GitOps delivery, full observability, live
on the internet with real certificates. [Architecture Overview](architecture/overview.md).

**2 — Show it running.**

```sh
kubectl get applications -n argocd          # 12/12 Synced and Healthy
curl -sI https://novashop.smartdev.vn       # 200, HSTS, Let's Encrypt
```

**3 — Show the guardrails, because anyone can deploy something.**

```sh
bash scripts/validate-gitops-revisions.sh --gitops-dir ../NovaShop-GitOps
```

30 checks proving every pinned revision is an ancestor of `main` and every referenced image
exists in GHCR. Then explain why the last one matters: a pin to a commit whose release
failed renders perfectly and produces `ImagePullBackOff`.

**4 — Show an alert and its runbook.** `count(ALERTS)` is 0 on a healthy platform. Open
[ArgoSyncFailed](observability/runbooks/argo-sync-failed.md) and show that every rule links
to a document CI proves exists.

**5 — Show the engineering log.** [LEARNING_LOG.md](LEARNING_LOG.md) — the defects found and
how. This is the part that distinguishes the project from a tutorial.

**6 — Show the audit.** [AUDIT.md](AUDIT.md) — including Production Readiness 2/5 and the
fact that recovery has never been fully exercised.

## Questions I expect, and honest answers

### "Why single node? That is not production."

It is not, and every document says so. Production Readiness is scored **2/5** for exactly
this. What a second node would change is a hardware decision, not an engineering one — it
would change the storage class choice, make PodDisruptionBudgets meaningful, and turn a node
fault into a degradation instead of an outage.

What the single node forced is more interesting: recovery had to become a rehearsed procedure
rather than an assumption about redundancy, and every claim about resilience had to be
qualified rather than implied.

### "Show me something that went wrong."

[LEARNING_LOG.md](LEARNING_LOG.md), and the best example is the Argo CD diff.

An Application sat OutOfSync while sync reported Succeeded. `helm template | diff` showed
**zero differences** — so I fixed the wrong thing, shipped it, then fixed it again on the same
false premise and had to revert both.

The cause: with `ServerSideApply`, sync status compares a server-side apply *dry-run* against
the live object, not the rendered manifest. I had been comparing the wrong pair of states.

What I changed is the part worth discussing: the runbook now names which pair to compare,
because the next person will reach for `helm template | diff` too.

### "How do you know your monitoring works?"

Because I assumed it did once and it did not. The backend scrape annotation named the Service
port instead of the container port; all six replicas returned connection refused, and nothing
was unhealthy — the metric simply did not exist.

So the observability gate now asserts things a render cannot: required scrape jobs by name,
that Traefik is discovered by pod rather than endpoints, that every alert has a runbook
resolving to a real file. And every alert expression was evaluated against live Prometheus
before merge — not to watch it fire, but to confirm its label selectors match real series.
That check found Traefik being scraped twice.

### "Your test coverage is thin."

Nine backend test functions, zero frontend tests, no coverage measurement. It is the weakest
dimension and [AUDIT.md](AUDIT.md) scores Reliability **3/5** for it.

The distinction I would draw: *configuration* reliability is strong — 94 automated checks,
each negative-tested to prove it fails when it should. *Application* test coverage is thin,
and the application is deliberately trivial. If the interview is about platform engineering,
the first number is the relevant one. If it is about application delivery, the second is a
fair criticism.

### "Walk me through a deployment."

Pull request runs five checks. Merge to `main` triggers release, which calls **the same
reusable workflow** — validation and publication are nodes in one job graph, so release
cannot race CI. Inside publish: build loads locally, Trivy scans, and only then does the
workflow acquire registry credentials and push. `latest` moves in a separate job that needs
publish.

Then a second merge, in the GitOps repository, re-pins the revision and image tags. Argo CD
converges in about three minutes.

Two merges is deliberate. The second is where a human decides that a verified image should
become live.

### "What would you do differently?"

Three things.

**Not stack pull requests.** #51 was stacked on #50's branch, GitHub reported it MERGED, and
1,091 lines landed nowhere because the base was merged first. `gh pr list` showed nothing
outstanding, CI was green, and I found it by counting directories.

**Run the recovery script earlier.** It could not execute at all — it grepped
`^DATABASE_URL=` while the file declares `export DATABASE_URL=`. The same mismatch had already
been fixed in another script. It survived because nobody had run this one.

**Distrust a test that agrees with me.** A NetworkPolicy trial reported the isolation I
wanted, and the same run reported a same-namespace result that was obviously wrong. Both were
the same race. The convenient half of a broken test is still broken.

### "Why no service mesh / Kyverno / Vault?"

Pod Security Admission already enforces `restricted` and genuinely rejects non-compliant
pods — proven when my own diagnostic pod was refused. RBAC and the AppProject whitelist cover
authorization. Adding an admission controller would duplicate that.

Vault is the interesting one. [ADR 010](../adr/010-secret-management.md) rejects every option
for the same reason: Sealed Secrets, SOPS, and Vault all move the bootstrap problem to a key
that must survive a node rebuild, on a node with node-local storage. And Terraform state
stores values in plaintext, so managing secrets there would make the platform *less* secure
than a root-owned 0600 file.

### "What is the biggest risk right now?"

Full recovery has never been exercised on a replacement node. Every component has been tested
individually — preconditions, database restore with a content checksum, GitOps reconciliation
in 5 seconds — but that is not the same as running the sequence.

Until it has been, RTO is an estimate of 30–45 minutes and should be treated as unknown.

## For a DevSecOps conversation specifically

| Control | State | Evidence |
|---|---|---|
| Supply chain | Actions pinned to commit SHAs; Argo CD manifest pinned by SHA-256 | [ADR 008](../adr/008-ci-platform.md) |
| Scan before publish | Registry credentials not acquired until Trivy passes | `.github/workflows/release.yml` |
| Image hardening | Non-root, `readOnlyRootFilesystem`, `drop: ALL`, seccomp, npm removed from runtime | [Learning log](LEARNING_LOG.md) |
| Admission | Pod Security `restricted`, enforced | [network-policy.md](security/network-policy.md) |
| Network | Default-deny ingress, trialled live with a control group | [network-policy.md](security/network-policy.md) |
| Least privilege | Exporter role verified unable to write, application verified still able | [Learning log](LEARNING_LOG.md) |
| Secrets | Never in Git, never in Terraform state, enforced by a `check` block | [ADR 010](../adr/010-secret-management.md) |
| Branch protection | Rulesets as JSON, applied by script | `.github/rulesets/` |

**Open, and stated as such:** no image signing or provenance, no egress restriction, no
network policies in `observability` or `cert-manager`, and node credentials that need
rotating to SSH keys.

## What not to oversell

Say these before an interviewer finds them:

- The application has **no schema** and **no business endpoints**. The database has zero
  tables. This is a platform project.
- Distributed tracing is instrumented and **not deployed** —
  [ADR 011](../adr/011-distributed-tracing.md) explains why a trace today would be
  `GET /ready` plus two dependency calls.
- Five of seven Terraform layers **manage nothing yet** — the interface is designed and
  validated, the resources are not written.
- Alerts route **nowhere**. They evaluate and are queryable; nothing pages anyone.

Each of these is in [AUDIT.md](AUDIT.md) with a score attached. A candidate who names their
own gaps is easier to trust on the parts they claim work.
