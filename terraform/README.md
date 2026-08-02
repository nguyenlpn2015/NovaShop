# Terraform

Terraform codifies the NovaShop platform so another engineer can reproduce it with
minimal manual work. It does **not** provision cloud resources — there is no AWS, Azure,
or GCP account. It manages the platform that exists: a GitHub organisation, a DNS zone, an
Ubuntu node, and the datastores on it.

Decision and rationale: [ADR 012](../adr/012-terraform-scope.md),
[ADR 013](../adr/013-terraform-kubernetes-boundary.md),
[ADR 014](../adr/014-terraform-gitops-handover.md).

Review, findings, and maturity score: [Terraform audit](../docs/TERRAFORM_AUDIT.md).
Architecture view: [Terraform Flow](../docs/architecture/terraform-flow.md).

> **Status.** Two of seven layers declare resources: **`5-cluster`** and **`6-gitops`**. The
> other five — `0-node`, `1-datastores`, `2-k3s`, `3-github`, `4-dns` — are foundation only:
> providers, version pins, backend abstraction, variables, locals, outputs, and validation.
> `terraform plan` in those five produces an empty plan.
>
> That is a real limitation, not a phrasing. The node, the datastores, k3s, the GitHub
> repositories and the DNS records are **configured by scripts and by hand**; those five
> layers describe the interface Terraform would use, and manage nothing today. Anything they
> would manage already exists, so the path is `terraform import`, never `apply` — which is
> why [`5-cluster/imports.tf`](layers/5-cluster/imports.tf) exists and why that layer asserts
> eleven properties while owning two resources.

## The ownership boundary

The single most important rule in this directory, and the one that decides whether the
platform works.

```
Terraform  →  the node, the datastores, k3s, GitHub, DNS, and the Argo CD seed
Argo CD    →  everything inside the cluster, once the seed exists
```

**Terraform must never manage an object that Argo CD reconciles.** Every Application has
`selfHeal: true`, so a Terraform-managed Deployment would be reverted within about three
minutes, `terraform plan` would never converge, and neither tool would be the source of
truth.

This is a functional constraint, not a stylistic preference. Where the boundary is drawn
and why is in [ADR 012](../adr/012-terraform-scope.md).

## Layers

Each layer is a separate root module with its own state. Numbered by dependency order.

| Layer | Manages | Provider | Phase |
|---|---|---|---|
| [`0-node`](layers/0-node/) | Packages, swap, sysctl, UFW | built-in | 2 |
| [`1-datastores`](layers/1-datastores/) | PostgreSQL roles, grants, databases; Redis config | `postgresql` | 3 |
| [`2-k3s`](layers/2-k3s/) | k3s version and server arguments | built-in | 4 |
| [`3-github`](layers/3-github/) | Two repositories, rulesets, Dependabot | `github` | 5 |
| [`4-dns`](layers/4-dns/) | Cloudflare A records | `cloudflare` | 6 |
| [`5-cluster`](layers/5-cluster/) | The one namespace Argo CD does not reconcile, a read-only role, and cluster prerequisites | `kubernetes` | 7 |
| [`6-gitops`](layers/6-gitops/) | Argo CD install, the `novashop` AppProject, the root Application, repository registration | `kubernetes` | 8 |

Layers are separate rather than workspaces because they differ in **lifecycle** and in
**who can run them** — a DNS change and a node change have nothing in common except this
repository. Workspaces share one backend configuration and encourage `count` by
environment, which is not the axis this platform varies on.

`6-gitops` is the last layer Terraform runs. It creates the root Application and stops;
everything downstream reconciles from Git. See
[ADR 014](../adr/014-terraform-gitops-handover.md).

`5-cluster` is a layer inside the cluster, and it **asserts far more than it owns** —
two resources against eleven assertions. Checking what Argo CD actually reconciles, rather
than assuming, found that five of six namespaces are reconciled and three of those carry no
tracking annotation at all: `managedNamespaceMetadata` on the ApplicationSet reapplies their
labels every sync. See [ADR 013](../adr/013-terraform-kubernetes-boundary.md).

## Running a layer

```sh
cd terraform/layers/3-github

cp ../../examples/backend-local-override.tf.example backend_override.tf
terraform init
terraform plan  -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

Credentials are **never** in `.tfvars`. They come from the environment:

```sh
export TF_VAR_github_token=...
export TF_VAR_cloudflare_api_token=...
```

## Backend abstraction

No layer hard-codes a backend. Every layer declares a partial configuration:

```hcl
terraform {
  backend "pg" {}   # no arguments — supplied at init time
}
```

Arguments come from a file at init time:

| File | Use |
|---|---|
| [`examples/backend-pg.hcl.example`](examples/backend-pg.hcl.example) | Steady state, with locking |
| [`examples/backend-local-override.tf.example`](examples/backend-local-override.tf.example) | Bootstrap and rebuilds, before the node exists |

`-backend-config` supplies *arguments* to the declared backend type — it cannot change the
type. Running a layer on local state therefore uses an override file, which Terraform merges
over the configuration, rather than a second `-backend-config`. Copying the wrong one
produces `Backend initialization required ... Reason: Initial configuration of the requested
backend "pg"`, which is what that error means.

**Why PostgreSQL and not a cloud bucket.** There is no cloud account. PostgreSQL already
runs on the node, is already in the platform backup, and the `pg` backend gives real state
locking. It adds no infrastructure.

**The ordering dependency this creates.** The `pg` backend requires PostgreSQL, so a layer
that must run before the node exists — GitHub and DNS during a rebuild — starts on local
state and is migrated with `terraform state push` once the node is up. In disaster
recovery, PostgreSQL is restored before Terraform runs, in the same way certificates are
restored before Argo CD reconciles.

One schema per layer, so a mistaken `destroy` in one layer cannot reach another.

## Conventions

**File layout is identical in every layer.** `versions.tf`, `backend.tf`, `providers.tf`,
`variables.tf`, `locals.tf`, `outputs.tf`, `README.md`. Predictability beats brevity when
five directories do structurally similar things.

**Terraform and providers are pinned.** `required_version` uses `~>` on the minor, and
`.terraform.lock.hcl` is committed — the same reasoning that pins GitHub Actions to commit
SHAs. A provider is code that runs with credentials.

**Variables carrying credentials are `sensitive` and have no default.** A default for a
credential is a credential in the repository.

**Validation rules are on the variables that have caused incidents.** An IP that is not an
IP and a SHA-256 that is not 64 hex characters both fail at plan time rather than at apply
time.

**Nothing is created; everything is imported.** Every resource on this platform already
exists. Recreating a DNS record is an outage; recreating a ruleset is a window with no
branch protection. Each layer lands with `import` blocks and the acceptance gate is a
**completely empty plan**. If the plan is not empty after import, the configuration is
wrong — not the infrastructure.

## Validation

Runs without credentials and without a backend:

```sh
terraform fmt -check -recursive
cd layers/<layer> && terraform init -backend=false && terraform validate
```

`-backend=false` is what makes this work in CI: `terraform validate` requires `init`, and
`init` would otherwise try to reach the backend. With it, validation needs no secrets and
no network beyond the provider registry.

The `terraform` job in [`validation.yml`](../.github/workflows/validation.yml) runs both
across every layer. Later phases add `terraform plan` on pull requests so a reviewer sees
the effect; **`apply` is never automated.** On a single-node platform where Terraform holds
DNS and the cluster seed, an automatic apply is a blast radius out of proportion to the
convenience.

## Examples

[`examples/`](examples/) holds backend configurations and a `.tfvars.example` per layer.
Every example is committed; no file containing a real credential is.

## What Terraform deliberately does not manage

| Not managed | Why |
|---|---|
| Anything Argo CD reconciles | Two controllers, one object — see the boundary above |
| Helm releases and Applications | Argo CD's, without exception |
| The out-of-band Kubernetes Secrets | Terraform state stores values in plaintext, and **importing or even reading one puts it there**. `/root/.novashop-platform.env` is root-owned and 0600, which is stronger. `5-cluster` codifies their shape and never their values. See [ADR 010](../adr/010-secret-management.md) and [ADR 013](../adr/013-terraform-kubernetes-boundary.md) |
| FortiGate NAT policy | No provider worth depending on |
| Let's Encrypt certificates | cert-manager owns these, and issuance is rate limited |
