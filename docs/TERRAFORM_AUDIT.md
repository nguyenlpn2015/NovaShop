# Terraform Audit

Production-quality review of the Terraform implementation delivered in Sprint 6.

**Date:** 2026-08-02 · **Scope:** `terraform/` in full — 7 layers, 2,408 lines of HCL ·
**Method:** `tflint` v0.55.0, `trivy` 0.58.1 (IaC misconfiguration and secrets),
`terraform validate` per layer, `terraform plan` against the live cluster, and manual review

## The number that frames everything

| | Count |
|---|---|
| Layers | 7 |
| **Resources** | **6** |
| Data sources | 6 |
| Variables | 74 |
| Outputs | 48 |
| `check` blocks | 21 |
| Variable `validation` blocks | 24 |

**Seventy-four variables and forty-eight outputs for six resources.** Five of the seven
layers manage nothing at all — they are interface without implementation, because Phase 1
was foundation-only and resources have landed in `5-cluster` and `6-gitops` only.

That ratio is not automatically wrong. Declaring the interface first is a defensible way to
land a large change in reviewable pieces, and the two layers that do manage something are in
good shape. But an audit has to say plainly that **most of this Terraform does not yet
manage anything**, and that a reader arriving at `terraform/` will find far more scaffolding
than substance.

## Scores

| Dimension | Score | One line |
|---|---|---|
| Folder structure | **5** / 5 | 7/7 layers carry an identical file set; examples and state cleanly separated |
| Validation | **4** / 5 | 45 guards, every one negative-tested; lint added during this audit, `plan` still absent |
| Security | **4** / 5 | No credential in state by construction, enforced; two real defects found and fixed |
| Documentation | **4** / 5 | Thorough and decision-led; contained three overclaims, now corrected |
| Maintainability | **4** / 5 | Consistent and commented; five layers are inert |
| Naming | **3** / 5 | One genuine collision: `repositories` means two different things |
| Variables | **3** / 5 | Strong validation coverage, **9 declared and unused** |
| Outputs | **2** / 5 | 48 outputs, **zero consumers** |
| Reusability | **2** / 5 | `modules/` is empty; 7 variables duplicated across layers |

**Overall: 3.4 / 5.** Strong foundations, correct boundaries, and honest documentation, held
back by an interface that has outrun its implementation and by nothing consuming the outputs.

---

## Findings

### F1 — Nothing consumes any output · Outputs · **Fixed (documentation)**

48 outputs; `grep -rn 'terraform output' scripts/ .github/` returns nothing.

Worse than the gap itself, three places asserted a consumer that does not exist —
`5-cluster/outputs.tf` said outputs "are asserted against by `scripts/linux/verify.sh`", and
`6-gitops/README.md` said "`verify.sh` asserts them". Both were untrue.

Corrected to state that `verify.sh` is the *intended* consumer and does not read them yet.
A document that describes wiring which does not exist is worse than one that says nothing:
the next reader stops looking.

### F2 — Unquoted interpolation into a root shell · Security · **Fixed**

`6-gitops/main.tf` interpolated operator-supplied variables into `remote-exec` commands
running as root on the node:

```hcl
"cd ${var.repository_root}",
"sudo -E env ARGOCD_VERSION=${var.argocd_version} ... bash scripts/linux/install-argocd.sh",
```

A path containing a space breaks it; a path containing `;` executes arbitrary commands as
root. That the operator supplies the value is not a reason to leave it unquoted — it is the
same argument that makes SQL injection acceptable in an admin tool. All interpolations are
now single-quoted.

### F3 — Nine unused variables and three unused locals · Variables · **Open**

`tflint` output, verbatim:

```
2-k3s:        node_host, node_user, ssh_private_key, kubeconfig_mode
0-node:       ssh_private_key, swap_enabled, packages
              local.connection, local.firewall_hash
1-datastores: revoke_public_schema_create
3-github:     local.required_checks_flat
4-dns:        cloudflare_zone_id
```

Most are inert because their layer has no resources yet, which is expected. `swap_enabled`,
`packages`, and `revoke_public_schema_create` are different: they describe behaviour nothing
implements, and a reader would reasonably assume setting them does something.

**A note on method.** My own first pass at this found only 7 and missed
`cloudflare_zone_id` and `kubeconfig_mode`, because the regex counted a variable's
self-reference inside its own `validation` block as a use. `tflint` found all 12. This is
the argument for a real linter over an ad-hoc script, and it applies to the audit itself.

### F4 — `repositories` means two different things · Naming · **Open**

| Layer | Type | Meaning |
|---|---|---|
| `3-github` | `map(object({description, visibility, has_issues, topics}))` | GitHub repositories to configure |
| `6-gitops` | `map(object({url, type}))` | Argo CD repository registrations |

Same name, incompatible shapes, adjacent layers. Someone copying a `.tfvars` block between
them gets a type error if they are lucky and a wrong configuration if they are not.

Rename to `github_repositories` and `argocd_repositories`.

### F5 — `modules/` is empty · Reusability · **Open**

`terraform/modules/README.md` promises `github-repository` and `dns-record-set`. Neither
exists, because neither layer has resources yet. The README is honest — it says "empty during
Phase 1" — but the directory currently contributes nothing.

### F6 — Seven variables duplicated across layers · Reusability · **Open**

```
node_host, node_user, ssh_private_key    0-node, 2-k3s, 6-gitops
kubeconfig_path, kubeconfig_context      5-cluster, 6-gitops
argocd_namespace                         5-cluster, 6-gitops
```

Three separate declarations of the SSH connection triple will drift. Terraform has no
cross-root variable sharing, so the options are a shared `connection` module, a generated
`common.auto.tfvars`, or `terraform_remote_state`. The last is the standard answer and would
also let `1-datastores` consume `0-node`'s `node_ip` instead of redeclaring it.

### F7 — No `plan` and no lint in CI · Validation · **Partly fixed**

CI runs `fmt -check` and `validate` per layer. It does not run `tflint`, so all twelve issues
in F3 were invisible to the pipeline, and it does not run `plan`, so nothing checks that a
change produces the diff its author intended.

`tflint` is now in the `Terraform` job, with `--minimum-failure-severity=error`. That is a
compromise and worth naming as one: all twelve warnings in F3 belong to layers whose
resources have not landed, so failing on them would mean deleting an interface that is about
to be used. **A warning nobody must act on is a warning that gets ignored**, so the count is
tracked here with a target of zero, and the setting becomes
`--minimum-failure-severity=warning` when it gets there.

**Warning count at this audit: 12.** Target: 0, via recommendation 5.

`plan` still is not in CI: it needs cluster and provider credentials, which a fork's pull
request cannot have. That is a real constraint, not an oversight.

### F8 — Provisioners carry known caveats that are not written down · Maintainability · **Open**

`terraform_data` with `remote-exec` is used in `6-gitops` and planned for `0-node` and
`2-k3s`. HashiCorp documents provisioners as a last resort. The choice is defensible here and
[ADR 012](../adr/012-terraform-scope.md) argues it, but two operational consequences are not
documented anywhere:

- A failed provisioner **taints** the resource, so the next apply re-runs it. Harmless for
  idempotent scripts; worth knowing before it happens at 03:00.
- `connection` blocks are not persisted to state, so `ssh_private_key` should not reach the
  state file. **This has not been verified empirically on this platform** — no layer using a
  provisioner has been applied. Stated as an expectation, not a fact.

### F9 — State encryption is not addressed · Security · **Open**

The `pg` backend stores state as plaintext in PostgreSQL. No layer currently writes a
credential to state — that is enforced by design and by a `check` block — so the exposure
today is resource metadata, not secrets.

It is still worth naming: the guarantee rests on *no layer ever adding a sensitive attribute*,
which is a discipline rather than a mechanism.

### Clean results

`trivy config` on `terraform/` — no HIGH, CRITICAL, or MEDIUM misconfiguration.
`trivy fs --scanners secret` — nothing.
`terraform fmt -check -recursive` — clean.
`terraform validate` — 7/7 layers pass.
File layout — 7/7 layers carry all seven expected files.

---

## Recommendations

Ordered by value per unit of effort. None requires a new technology.

| # | Recommendation | Addresses | Effort |
|---|---|---|---|
| 1 | Wire `verify.sh` to consume `verification_commands`, `acme_reachable_fqdns`, and `cluster_prerequisites` | F1 | S |
| 2 | Rename to `github_repositories` / `argocd_repositories` | F4 | S |
| 3 | Add `.tflint.hcl` with the ruleset pinned, so local and CI runs agree | F7 | S |
| 4 | Delete `swap_enabled`, `packages`, `revoke_public_schema_create` until the resources that honour them exist | F3 | S |
| 5 | Land resources in `0-node`, `1-datastores`, `2-k3s`, `3-github`, `4-dns` — the interfaces are designed and validated, and five inert layers is the single largest gap | F3, F5 | L |
| 6 | Introduce `terraform_remote_state` so `1-datastores` reads `0-node`'s outputs instead of redeclaring them | F6, F1 | M |
| 7 | Extract the SSH `connection` triple into a shared module once ≥2 layers use it | F6 | M |
| 8 | Document the provisioner taint behaviour in each layer README; verify empirically that the SSH key is absent from state after the first apply | F8 | S |
| 9 | Add `terraform plan` to CI for the credential-free layers only, posted as a comment | F7 | M |
| 10 | Record the state-encryption position in an ADR, or enable PostgreSQL TDE | F9 | M |

**Deliberately not recommended:** a wrapper tool such as Terragrunt. It would solve F6
directly, and it is the standard answer at larger scale. Seven layers with two shared
variables does not justify a second configuration language and a second set of failure modes,
and the brief was explicit about not adding technologies.

---

## Architecture updates

**Added:** [Terraform Flow](architecture/terraform-flow.md) — the thirteenth architecture
view. The layer sequence, the ownership boundary against Argo CD, the state model, and where
Terraform stops. Until now `terraform/` was described only in ADRs 012–014 and in its own
READMEs, so a reader following the architecture index would not have known it existed.

**Updated:** [architecture/README.md](architecture/README.md) index, and
[bootstrap-flow.md](architecture/bootstrap-flow.md) already carries the layer sequence from
Sprint 6.

---

## Sprint completion report

| Objective | Status | Evidence |
|---|---|---|
| Terraform foundation — providers, versions, backend, locals, variables, outputs, README, examples, validation, formatting | **Done** | 7 layers, identical file layout, `fmt` clean, 7/7 validate |
| Kubernetes provider — namespaces, secret templates, RBAC, StorageClass, prerequisites, validation | **Done** | `5-cluster`: `Plan: 1 to import, 1 to add, 0 to change` on the live cluster |
| GitOps bootstrap — Argo CD, projects, repository registration, application bootstrap, validation, recovery docs | **Done** | `6-gitops`: `Plan: 2 to add, 0 to change`, 7 assertions silent |
| Audit | **Done** | This document |
| Resources in layers 0–4 | **Not started** | Foundation only, by design of Phase 1 |
| Anything applied to the cluster | **Not applied** | Deliberate — awaiting approval |

### What Sprint 6 actually proved

The most valuable output was not the HCL. It was checking, twice, **who already owns a
resource** before declaring it:

`managedNamespaceMetadata` on the ApplicationSet reconciles three namespaces that carry no
tracking annotation. Declaring them in Terraform would have produced permanent drift on the
namespaces holding every application environment, with the usual evidence of Argo CD
ownership absent. That was found by reading the cluster, not by reasoning about it.

`kubernetes_manifest` does not support import, and the root Application carries a
`resources-finalizer`. Declaring it would have planned a create, failed on conflict, and the
obvious workaround — delete and recreate — cascades to everything the Application manages.

Both are the kind of finding that only appears when the design is checked against reality
before it is written.

### Cost

Three pull requests: [#49](https://github.com/nguyenlpn2015/NovaShop/pull/49),
[#50](https://github.com/nguyenlpn2015/NovaShop/pull/50),
[#51](https://github.com/nguyenlpn2015/NovaShop/pull/51). 2,408 lines of HCL, three ADRs, one
architecture view, and nothing applied.

---

## Terraform maturity score

**3.4 / 5 — Defined.**

| Level | | This implementation |
|---|---|---|
| 1 | Ad hoc — a single root, no state discipline | |
| 2 | Repeatable — layers or workspaces, remote state | |
| 3 | **Defined** — validation, locked providers, documented decisions, enforced boundaries | **← here** |
| 4 | Managed — resources cover the platform, outputs consumed, `plan` in CI, modules reused | |
| 5 | Optimising — policy as code, drift detection on a schedule, automated remediation | |

**Level 3 is earned.** Providers and Terraform are pinned with committed multi-platform lock
files. Every layer has its own state and a documented backend strategy. There are 45 guards
and each was negative-tested against reality rather than assumed. The boundary against Argo CD
is enforced and, twice, was corrected by evidence. Documentation carries the reasoning and the
rejected alternatives.

**Level 4 is blocked on two things**, both already in the recommendations: five layers manage
nothing, and no output has a consumer. Recommendations 1 and 5 close both. Until then this is
a well-built interface to a platform Terraform mostly does not manage yet — which is an honest
description of a foundation, not a criticism of one.

## Reproducing this audit

```sh
docker run --rm -v "$PWD:/data" -w /data \
  ghcr.io/terraform-linters/tflint:v0.55.0 --recursive --format compact

docker run --rm -v "$PWD:/repo" aquasec/trivy:0.58.1 \
  config --severity MEDIUM,HIGH,CRITICAL /repo/terraform

docker run --rm -v "$PWD:/repo" -w /repo hashicorp/terraform:1.9.8 \
  fmt -check -recursive terraform

grep -rn 'terraform output' scripts/ .github/     # F1: still empty?
grep -c 'variable "' terraform/layers/*/variables.tf
```
