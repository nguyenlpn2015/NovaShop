# ADR 012: Terraform codifies the platform outside the cluster

## Status

Accepted

## Date

2026-08-02

## Context

The platform is reproducible today only by reading documentation and running scripts in the
right order. Three parts are worse than that:

**DNS exists nowhere in the repository.** Four Cloudflare A records, configured by hand.
They are the least reproducible part of the platform and the one with the longest gap
between a mistake and its symptom — DNS is on the critical path for certificate renewal, so
an error surfaces up to sixty days later.

**Branch protection is a script plus JSON.** `scripts/apply-branch-protection.sh` applies
`.github/rulesets/*.json`. It works, but there is no drift detection: a ruleset changed in
the web UI stays changed until someone runs the script again and reads the output.

**Least privilege is a SQL snippet somebody ran once.** The metrics exporter's inability to
create tables — the fix for PostgreSQL 14 granting `CREATE` on `public` to `PUBLIC` — is
recorded in a document. Nothing detects it being undone.

There is no AWS, Azure, or GCP account, so this is not the usual Terraform use case. The
question is whether Terraform earns its place codifying infrastructure that already exists
on one Ubuntu node.

## Decision

Terraform manages the platform **outside the Kubernetes reconciliation loop**, in five
layers, each a root module with its own state:

| Layer | Manages | Provider |
|---|---|---|
| `0-node` | Packages, swap, sysctl, UFW | built-in |
| `1-datastores` | PostgreSQL roles, grants, databases; Redis configuration | `cyrilgdn/postgresql` |
| `2-k3s` | k3s version and server arguments | built-in |
| `3-github` | Two repositories, rulesets, Dependabot | `integrations/github` |
| `4-dns` | Cloudflare A records | `cloudflare/cloudflare` |

**Terraform never manages an object that Argo CD reconciles.**

State lives in the PostgreSQL instance already on the node, one schema per layer, using the
`pg` backend. Every layer declares a partial backend so the same code initialises against
local state during a rebuild.

For the node and Redis — where no provider models the resource — Terraform renders the
configuration from templates and triggers on the **hash of the rendered content**, with the
existing idempotent scripts as executors.

## Alternatives Considered

**Terraform everything, including Kubernetes objects.** This was explicitly requested, and
it was taken as far as it can go without breaking. The remaining boundary is not a
preference. Every Application has `selfHeal: true`, so a Terraform-managed Deployment is
reverted within about three minutes; `terraform plan` never converges and neither tool is
the source of truth. The only coherent way to include those objects is for Terraform to
*replace* the app-of-apps entirely — which would remove the two-merge review that
[ADR 003](003-gitops-delivery.md) exists to provide, and make an image tag change a
`terraform apply` instead of a reviewable GitOps pull request. Rejected on that trade, not
on scope.

**`remote-exec` wrapping the existing shell scripts, with no content trigger.** The usual
way "Terraform everything" is done and the reason it is often hollow. The plan is either
always empty or always dirty, Terraform knows nothing about the node, and state records
that something ran rather than what is true. Rejected in favour of template rendering plus
content hashing, which produces a plan that shows a specific difference when an input
changes and nothing when it does not.

**Ansible for the node layer.** A better configuration management tool than Terraform, and
genuinely the right answer for packages and services. Rejected because it would be a second
orchestration tool with a second state model for a single node whose scripts are already
idempotent and self-verifying. The marginal gain over `templatefile` plus a hash trigger did
not justify a new technology, and the project brief was explicit about not adding any.

**Leave everything as scripts.** Defensible: the scripts work, they are idempotent, and they
verify themselves. Rejected on the three specific gaps in Context — no drift detection on
GitHub, no representation of DNS at all, and no continuous enforcement of the database
grants. Those are the things Terraform is genuinely better at.

**A cloud state backend.** No account. Considered and unavailable.

**Local state, committed.** Rejected: state contains resource attributes and, for some
providers, credential material.

**`kubernetes` backend, state in a Secret.** Circular — Terraform prepares the node the
cluster runs on.

**Terraform Cloud.** A hosted dependency and an account, to hold state for a home lab.

**Workspaces instead of separate layers.** Workspaces share one backend configuration and
encourage varying by environment. These layers differ by lifecycle and by who can run them;
a DNS change and a node change have nothing in common except this repository. Separate
states also mean a mistaken `destroy` cannot cross a boundary.

**Managing the out-of-band Kubernetes Secrets.** Rejected, and this is the sharpest case
against maximal scope: Terraform state stores values in plaintext, whereas
`/root/.novashop-platform.env` is root-owned and mode 0600. Terraforming those secrets would
make the platform **less** secure than it is now. They stay as
[ADR 010](010-secret-management.md) describes.

## Consequences

**Easier.** DNS becomes reviewable, diffable, and reproducible for the first time. Branch
protection gains drift detection. The exporter's least privilege becomes desired state
rather than a historical event. The pending k3s control-plane flags become a declarative
change with a visible plan instead of a remembered task. Another engineer can reproduce the
platform from the repository plus a small number of credentials.

**Harder, and accepted.**

*Two state models.* Terraform owns some things, Argo CD owns others, and the boundary has to
be understood before touching either. It is documented in `terraform/README.md` and in every
layer README, and it is the first thing a reviewer should check.

*The `pg` backend creates an ordering dependency.* PostgreSQL must exist before Terraform can
store state. Layers that run before the node exists start on local state and migrate. In
disaster recovery, PostgreSQL is restored before Terraform runs — the same principle as
restoring certificates before Argo CD reconciles.

*A destroy in the DNS layer is an outage and a renewal failure.* Mitigated with
`prevent_destroy` on every record and a separate state, but the risk is real and worth
stating.

*Import is unavoidable and unforgiving.* Every resource already exists, so every layer lands
with `import` blocks and an acceptance gate of a **completely empty plan**. If the plan is
not empty after import, the configuration is wrong — and applying it would edit reality to
match a mistaken description.

*Provider tokens are new credentials.* A GitHub token with `administration:write` and a
Cloudflare token with `Zone:DNS:Edit` did not previously exist. Both are scoped to the
minimum and supplied through `TF_VAR_*` only.

*The node layer is honest but not elegant.* Content hashing plus `remote-exec` is better
than a bare provisioner and worse than a real provider. It is the best available shape for
this problem, and calling it anything more would be overselling it.

## Validation

Without credentials and without a backend:

```sh
terraform fmt -check -recursive terraform
cd terraform/layers/<layer> && terraform init -backend=false && terraform validate
```

The `Terraform` job in `.github/workflows/validation.yml` runs both across every layer on
every pull request.

Once resources land, the gate for each layer is:

```sh
terraform plan     # must report: 0 to add, 0 to change, 0 to destroy
```

And the boundary itself:

```sh
grep -rn 'kubernetes_\|helm_release' terraform/ && echo "BOUNDARY VIOLATED" || echo "boundary intact"
```
