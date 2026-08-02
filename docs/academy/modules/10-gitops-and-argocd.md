# Module 10 — GitOps and Argo CD

*Part 4 · GitOps · Intermediate to Senior*

The most important module here, and the one with the most expensive lesson: **the obvious way
to diff an Argo CD Application is wrong**, and getting it wrong cost this platform two
consecutive incorrect fixes that both had to be reverted.

## 1. Learning Objectives

After this module you can:

- Explain why NovaShop uses two repositories and defend the two-merge cost
- Say what `validate-gitops-revisions.sh` proves that a schema validator cannot
- Read a sync wave number and say what it orders and why
- **Diagnose an Application that is OutOfSync while its sync reports Succeeded**
- Explain why `kubectl patch` is a misleading debugging tool here
- Describe two ways Argo CD refuses work *after* a pull request has merged

## 2. Theory

**GitOps** means a controller in the cluster continuously reconciles live state toward a
declared state in Git. Two properties follow: the desired state exists outside the cluster and
can be replayed onto a new one, and CI never needs cluster credentials.

**App-of-apps.** One Application, `novashop-root`, whose job is to create other Applications.
Everything in this cluster descends from it.

**Sync waves** order resources within a sync, most negative first.

**Self-heal** means the controller reverts live drift. It is why nobody runs `kubectl edit`
here — and it is a debugging trap, covered in section 9.

**Server-side apply.** When an Application syncs with `ServerSideApply=true`, Argo CD computes
what to apply using a **server-side dry-run**. This changes what "difference" means, and section
9 is mostly about that.

## 3. Repository Walkthrough

### The two repositories

| Repository | Holds |
|---|---|
| `NovaShop` | Application code, the Helm chart, platform component values, scripts, Terraform |
| `NovaShop-GitOps` | 28 files: Argo CD Applications, per-environment values, phase composition |

### `NovaShop-GitOps/clusters/base/novashop-applicationset.yaml`

Read the `list` generator — three elements, one per environment — and the `template.spec`
below it. Note two things.

**Multi-source.** The chart comes from `NovaShop` at a pinned SHA; the values come from
`NovaShop-GitOps`. One Application composes sources from two repositories.

**`managedNamespaceMetadata`.** This is the field that makes three namespaces look unmanaged
and not be:

```yaml
managedNamespaceMetadata:
  labels:
    app.kubernetes.io/managed-by: argocd
    novashop.io/environment: "{{ .environment }}"
    pod-security.kubernetes.io/enforce: restricted
```

`kubectl get namespace novashop-production -o yaml` shows **no Argo CD tracking annotation**.
Argo CD nevertheless reapplies those labels on every sync. Terraform declaring them would
produce permanent drift with the usual evidence of ownership absent — see
[ADR 013](../../../adr/013-terraform-kubernetes-boundary.md).

### `argocd/application-ubuntu-k3s.yaml` — the root

```yaml
spec:
  project: novashop
  source:
    repoURL: https://github.com/nguyenlpn2015/NovaShop-GitOps.git
    targetRevision: main                      # NOT a SHA — deliberately
    path: clusters/ubuntu-k3s
  syncPolicy:
    automated: { prune: true, selfHeal: true, allowEmpty: false }
```

`targetRevision: main` is one of only two unpinned references in the platform. Pinning the root
Application would mean **no GitOps change could ever take effect** without editing the cluster.

### `scripts/validate-gitops-revisions.sh`

The gate. It fails a pull request unless, for every reference to `NovaShop`:

- the revision is a 40-character hex SHA — not a branch, not a tag;
- that SHA is an **ancestor of `origin/main`**, so a force-push cannot orphan it;
- backend and frontend image tags in one environment come from the **same** commit;
- no tag is `latest`;
- **both images exist in GHCR**, checked with an anonymous token.

That last check is the one worth remembering. A pin to a commit whose release failed renders
perfectly, validates perfectly, and produces `ImagePullBackOff`. Only a registry query catches
it.

### Phases and waves

`clusters/ubuntu-k3s/phases/`:

| Phase | Contains | Why separate |
|---|---|---|
| `http` | ApplicationSet, three environments | A fresh cluster serves traffic before any certificate exists |
| `tls-baseline` | AppProject, cert-manager, Certificates, all observability | Certificates requested once the edge is reachable |
| `tls-enforced` | Redirect and HSTS | Enforcement last, when there is something valid to enforce |

Waves: `-30` AppProject → `-20` cert-manager → `-15` Prometheus → `-14…-12` Grafana, Loki,
Alloy, exporters → `0` Certificates → `10` applications.

Prometheus at `-15` is deliberate: ahead of what it observes, so a target appearing during a
rollout is collected from its first moment.

### `platform-project.yaml`

The `AppProject` `namespaceResourceWhitelist`. Argo CD refuses to create a kind not listed —
**at sync time**, so a manifest can render, validate, merge, and only then be refused. Loki's
`StatefulSet` did exactly that.

## 4. Architecture Explanation

[GitOps Flow](../../architecture/gitops-flow.md) is the diagram for this module.

**Where Terraform stops.** Terraform creates the root Application and stops. Everything
downstream reconciles from Git —
[ADR 014](../../../adr/014-terraform-gitops-handover.md).

**What breaks elsewhere if this is wrong:**

| Mistake | Symptom |
|---|---|
| Pin to a commit with no published image | `ImagePullBackOff` on every replica |
| Pin the root Application to a SHA | No GitOps change ever takes effect again |
| New resource kind not whitelisted | Application OutOfSync, resource Missing, no error at merge |
| Remove a tracked resource from a source | It is **pruned** — deleted from the cluster |

That last row is not theoretical. Removing `namespace.yaml` from the Prometheus Application
would delete the `observability` namespace and everything in it — which is why that handover
was documented and not performed.

## 5. Hands-on Lab

No cluster required.

### Part A — run the revision gate

```sh
git clone https://github.com/nguyenlpn2015/NovaShop-GitOps.git ../NovaShop-GitOps
bash scripts/validate-gitops-revisions.sh --gitops-dir ../NovaShop-GitOps
```

Expect `PASS 30/30`.

### Part B — break it four different ways

Each time: edit, run the gate, read the message, revert.

```sh
cd ../NovaShop-GitOps
# 1. a branch instead of a SHA
sed -i 's/targetRevision: [0-9a-f]\{40\}/targetRevision: main/' \
  clusters/ubuntu-k3s/phases/tls-baseline/observability-loki-application.yaml

# 2. a SHA that is not an ancestor of main
sed -i 's/targetRevision: [0-9a-f]\{40\}/targetRevision: 0000000000000000000000000000000000000000/' \
  clusters/ubuntu-k3s/phases/tls-baseline/observability-loki-application.yaml

# 3. mismatched components — backend and frontend from different commits
# edit apps/novashop/values/development.yaml, change only the backend tag

# 4. an image tag that was never published
# set both tags to a real-looking but nonexistent 40-hex string
```

**Which of the four would a Kubernetes schema validator catch?** None. That is the point of a
separate gate.

### Part C — see the sync-wave ordering

```sh
grep -rn 'sync-wave' ../NovaShop-GitOps/clusters/ | sort -t'"' -k2 -n
```

Write down why cert-manager must precede Certificates.

### Verification

```sh
git -C ../NovaShop-GitOps checkout .
bash scripts/validate-gitops-revisions.sh --gitops-dir ../NovaShop-GitOps | tail -1
```

Must read `PASS`.

## 6. Exercises

**6.1** Add a `CronJob` to the Helm chart. Render it, then check
`namespaceResourceWhitelist` in `platform-project.yaml`. Would Argo CD create it? At what point
would you find out, and which gate catches it earlier?

**6.2** The root Application and the ApplicationSet's own repository reference track `main`.
Every other reference is pinned. Write three sentences justifying the asymmetry to someone who
says "pin everything".

**6.3** `PruneLast=true` and `PrunePropagationPolicy=foreground` are set. Look both up and
explain, for this platform specifically, what each prevents.

**6.4** Run `validate-platform.sh` and `validate-gitops-revisions.sh`. They check different
things and could have been one script. Give one reason they are separate. *(Hint: what does each
need in order to run?)*

## 7. Challenge

The `observability` namespace is a tracked resource inside the Prometheus Application.
Terraform cannot own it without a handover, and the handover is dangerous: removing a tracked
resource from an Application with `prune: true` **deletes it** — along with Prometheus, Grafana,
Loki, Alloy, Alertmanager, and four PersistentVolumeClaims.

The documented safe sequence is: annotate `Prune=false`, sync, confirm, remove from the source,
confirm survival, import into Terraform.

**Write the runbook for this**, in the style of
[`docs/observability/runbooks/`](../../observability/runbooks/). It must include: how to verify
each step took effect before proceeding; what to do if step 3 is executed while step 1 has not
propagated; and a statement of whether you would perform it at all.

The repository's answer is *no* — the value is consistency and the cost is a real chance of
deleting the observability stack. Argue either way, but argue.

## 8. Quiz

1. Why two repositories rather than one?
2. Which two references deliberately track `main`, and why?
3. What does the revision gate prove that `kubeconform` cannot?
4. Why is Prometheus at sync wave `-15`?
5. **True or false:** a manifest that passes all CI gates is guaranteed to be applied.
6. You `kubectl patch` a Deployment to test a theory. Ten minutes later nothing has changed.
   What are the two possible explanations?
7. What is `managedNamespaceMetadata` and why is it a trap?
8. Under `ServerSideApply`, which two states does sync status compare?
9. What happens if you remove a tracked resource from an Application's source?

<details>
<summary>Answers</summary>

1. It decouples the lifecycles. One repository makes every image build a potential deployment
   and every deployment a code change. The two-merge cost is the feature — the second merge is
   where a human decides a verified image should go live.
2. `novashop-root` and the ApplicationSet's own repository reference. Pinning the root would mean
   no GitOps change could ever take effect without editing the cluster.
3. That the revision is durable (an ancestor of `main`), that components come from one commit,
   and that the **images actually exist in the registry**.
4. Ahead of what it observes, so a target appearing during a rollout is collected from its first
   moment rather than after things settle.
5. **False.** The `AppProject` whitelist is enforced at sync time. Loki's `StatefulSet` merged
   cleanly and was refused afterwards.
6. Either the patch was reverted by `selfHeal` within about three minutes, or it was applied and
   your test is wrong. Distinguish them by reading the object's `resourceVersion`, or by pausing
   root's `selfHeal` and repeating.
7. An ApplicationSet field that reapplies namespace labels every sync. It is a trap because the
   namespaces carry **no tracking annotation**, so they look unmanaged to `kubectl` and are not.
8. `predictedLiveState` — a server-side apply dry-run — against `normalizedLiveState`. **Not**
   the rendered manifest against the live object.
9. It is pruned: deleted from the cluster. With a namespace, that takes everything inside it.

</details>

## 9. Troubleshooting

The two entries that cost this platform the most.

### OutOfSync, but the sync reports Succeeded

**Symptom.** `novashop-prometheus` reads `OutOfSync/Healthy`. The last sync says `Succeeded`.
Self-heal reapplies on schedule. The difference survives every attempt.

**What makes it misleading.** The obvious diagnostic:

```sh
helm template ... | kubectl diff -f -
```

reported **zero differences**.

**Why.** With `ServerSideApply`, sync status compares `predictedLiveState` — a server-side apply
dry-run — against `normalizedLiveState`. Not the rendered manifest. The real difference was
`apiVersion` and `kind` that Kubernetes adds inside a StatefulSet's `volumeClaimTemplate`, which
the dry-run does not reproduce.

**How to diagnose it properly:**

```sh
SIP=$(kubectl -n argocd get svc argocd-server -o jsonpath='{.spec.clusterIP}')
PW=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)
TOKEN=$(curl -sk "https://${SIP}/api/v1/session" -H 'Content-Type: application/json' \
  -d "{\"username\":\"admin\",\"password\":\"${PW}\"}" | jq -r .token)
curl -sk -H "Authorization: Bearer $TOKEN" \
  "https://${SIP}/api/v1/applications/<app>/managed-resources"
```

Compare `predictedLiveState` against `normalizedLiveState`. Fields showing `target: <absent>`
are server defaults Argo CD already ignores — on this platform, **41 of 42 differing fields were
noise.**

**What it cost.** Two consecutive wrong fixes, both shipped, both reverted. The first chased
`minReadySeconds`, which the *wrong* comparison flagged and the right one never did.

### A live patch that appears to change nothing

**Symptom.** You `kubectl patch` an Application to test a fix. You refresh, read the status,
and it is unchanged. You conclude the fix does not work.

**Why it is misleading.** `novashop-root` has `selfHeal: true`. Your patch was reverted —
usually **before** Argo CD recomputed the comparison. The status you read reflects the reverted
state.

**How this manifested.** A working `ignoreDifferences` fix was discarded on exactly this
evidence. Re-run with root's self-heal paused, it reached Synced immediately.

**The general lesson: an inconclusive experiment is not a negative result.**

**Testing safely:**

```sh
kubectl -n argocd patch application novashop-root --type merge \
  -p '{"spec":{"syncPolicy":{"automated":{"selfHeal":false}}}}'
# ... test, then restore immediately ...
kubectl -n argocd patch application novashop-root --type merge \
  -p '{"spec":{"syncPolicy":{"automated":{"selfHeal":true}}}}'
```

### A resource is Missing and nothing errored

Check the `AppProject` whitelist. Argo CD refuses kinds it does not permit, at sync time, so the
manifest merged cleanly and failed afterwards. `validate-observability.sh` now fails a pull
request that renders a kind the project does not allow.

### A stacked pull request that merged nowhere

**Symptom.** `gh pr list` shows nothing outstanding. The PR reads **MERGED**. The code is not on
`main`.

**Why.** It was stacked on another PR's branch and merged into *that* — which had already been
merged into `main`. 1,091 lines landed on an orphaned branch. CI was green throughout.

**How it was found.** Counting Terraform layer directories while gathering facts for a review.
**No tooling catches this.** Retarget a stacked PR to `main` before merging its base.

## 10. Best Practices

| Practice | Where |
|---|---|
| Desired state in a separate repository | `NovaShop-GitOps`, 28 files |
| Every reference pinned to a SHA, ancestor-verified | `validate-gitops-revisions.sh` |
| Registry existence checked before merge | Same gate, anonymous GHCR token |
| `AppProject` whitelist as a blast-radius boundary | `platform-project.yaml` |
| Sync-time refusals moved to pre-merge | `check_kinds_are_permitted` in the observability gate |
| Ordering by sync wave, not by hope | `-30` through `10` |
| Two unpinned references, both deliberate and documented | Root Application, ApplicationSet self-reference |

**Deliberately not done:** Argo CD Image Updater. It would remove the second merge — and the
second merge is the human decision point that [ADR 003](../../../adr/003-gitops-delivery.md)
exists to preserve. Automating it optimises away the control.

## 11. Interview Questions

- *An Application is OutOfSync but the sync reports Succeeded.* → [S2](../../interview/questions.md)
- *You patch a live resource and nothing changes.* → [S3](../../interview/questions.md)
- *What does the revision gate prove that the others do not?* → [S12](../../interview/questions.md)
- *Why Argo CD over Flux?* → [T3](../../interview/questions.md)
- *Why is the `argocd` namespace the only one Terraform owns?* → [S29](../../interview/questions.md)

## 12. Further Reading

- [Argo CD — Server-Side Apply](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-options/#server-side-apply)
- [Argo CD — Sync waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
- [ADR 003](../../../adr/003-gitops-delivery.md) · [ADR 005](../../../adr/005-gitops-controller.md) · [ADR 013](../../../adr/013-terraform-kubernetes-boundary.md)
- [ArgoSyncFailed runbook](../../observability/runbooks/argo-sync-failed.md) — the operational form of section 9

---

**Next:** Module 11 — Guardrails and Validation *(specified, not yet written)*.
Or jump to [Module 12 — Metrics with Prometheus](12-metrics-with-prometheus.md) ✅.
