# Portfolio Evidence

What to have open, and what to be able to run, when showing this platform to someone
evaluating you.

For the **narrative** — the order to tell it in and the questions to expect — use
[INTERVIEW_GUIDE.md](INTERVIEW_GUIDE.md). This page is the evidence behind it.

> **This replaces an earlier checklist built around Docker Desktop, `dev.novashop.local`, and
> `localhost:8080`.** That was accurate in Sprint 3 and wrong from Sprint 6 onward: the
> platform runs on a real Ubuntu node behind Let's Encrypt. A stale evidence list is worse
> than none, because it sends someone to look at the wrong thing and they conclude the
> project is smaller than it is.

## Before you show anything

```sh
bash scripts/validate-platform.sh          --gitops-dir ../NovaShop-GitOps
bash scripts/validate-gitops-revisions.sh  --gitops-dir ../NovaShop-GitOps
bash scripts/validate-observability.sh     --gitops-dir ../NovaShop-GitOps
```

If a gate fails, fix it before the conversation. Being asked to explain a red check you had
not noticed costs more than the check ever protected.

## Tier 1 — nothing but a browser

The strongest opening, because the person evaluating you can verify it themselves while you
talk.

| Open | Shows |
|---|---|
| [novashop.smartdev.vn](https://novashop.smartdev.vn) | A real deployment, valid certificate, HSTS |
| [staging](https://staging.novashop.smartdev.vn) · [dev](https://dev.novashop.smartdev.vn) | Three environments from one chart, different values |
| [api.novashop.smartdev.vn/ready](https://api.novashop.smartdev.vn/ready) | Dependency-aware readiness — and the reason `/live` is separate |
| The certificate padlock → issuer, expiry | cert-manager, Let's Encrypt production, renewal monitored |
| This repository's [Actions tab](https://github.com/nguyenlpn2015/NovaShop/actions) | Green checks, and a release workflow that calls the same validation |

## Tier 2 — the repository itself

You will spend most of the conversation here. These are the files that carry an argument, not
just a configuration.

| File | The point to make |
|---|---|
| [`scripts/validate-gitops-revisions.sh`](../scripts/validate-gitops-revisions.sh) | A gate that checks the image *exists in the registry*. Nothing else catches a pin to a failed release. |
| [`helm/novashop/templates/backend-service.yaml`](../helm/novashop/templates/backend-service.yaml) | Five lines of comment above one value, because that value silently broke metrics on six replicas |
| [`.github/workflows/release.yml`](../.github/workflows/release.yml) | Registry credentials are not acquired until Trivy has passed. Safety by structure. |
| [`adr/011-distributed-tracing.md`](../adr/011-distributed-tracing.md) | A decision *not* to deploy something, with the condition that would reverse it |
| [`docs/AUDIT.md`](AUDIT.md) | Your own scoring, including a 2/5 |
| [`docs/LEARNING_LOG.md`](LEARNING_LOG.md) | Sixteen defects, each with how it was found |

**Lead with the audit and the log.** Most portfolios present only what worked. Handing over a
document that scores your own Production Readiness at 2/5 changes what the rest of the
conversation is about.

## Tier 3 — the live cluster

Only if you have the node in front of you and time to spare. Port-forwards and consoles are
in [screenshots/](screenshots/).

```sh
kubectl get applications -n argocd                     # 12/12 Synced, Healthy
kubectl get pods -A                                    # what actually runs, on one node
kubectl get certificate -A                             # issued, and days to renewal
kubectl top node                                       # the honest resource picture
```

Two commands that make a better impression than a dashboard, because they show the reasoning
rather than the result:

```sh
# The sync-wave ordering, as a sorted list
grep -rn 'sync-wave' ../NovaShop-GitOps/clusters/ | sort -t'"' -k2 -n

# Every alert, and the runbook it resolves to
grep -rn 'runbook_url' kubernetes/observability/prometheus/alerting-values.yaml
```

## What to say about the weak parts

They will find these. Say them first.

| Weakness | The honest framing |
|---|---|
| One node, no HA | A hardware decision, not an oversight. Every document says single node rather than implying redundancy. |
| **Recovery never exercised end to end** | Every component is tested; the sequence is not. RTO is an estimate of 30–45 minutes and should be treated as unknown. |
| No frontend tests | Stated in the audit. It is the largest single gap and it is not disguised. |
| Alerts route nowhere | They evaluate and are queryable. Routing needs a credential this repository does not hold and an on-call decision that does not exist. |
| Production Readiness 2/5 | Self-assessed, with the commands to falsify it. |

An interviewer who finds an undisclosed weakness discounts everything else you said. An
interviewer handed the weakness up front spends the time on the engineering.

## What not to claim

- Do not call recovery *tested*. It is documented and partially exercised.
- Do not call this production. It serves real traffic on one node with no HA.
- Do not present the 93 pre-merge checks as a quality guarantee. They catch specific defects
  that actually occurred; [ADR 001](../adr/001-platform-guardrails.md) says exactly that.
- Do not describe the application as the work. It is deliberately small.
