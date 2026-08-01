# Examples

Backend configurations and per-layer variable examples. Every file here is committed, and
none contains a real credential.

## Backend configurations

| File | Use |
|---|---|
| [`backend-local-override.tf.example`](backend-local-override.tf.example) | Bootstrap, rebuilds, and any run before PostgreSQL exists. Copy into the layer as `backend_override.tf`, which is git-ignored. |
| [`backend-pg.hcl.example`](backend-pg.hcl.example) | Steady state with locking. Copy to `backend-pg.hcl`, which is git-ignored, because the connection string carries a password. |

```sh
cp ../../examples/backend-local-override.tf.example backend_override.tf
terraform init
```

`-backend-config` supplies *arguments* to the backend type declared in code; it cannot
change the type. A layer declaring `backend "pg" {}` cannot be initialised as local by
passing a path. Terraform merges any `*_override.tf` file over the configuration, which is
the supported way to substitute a backend for a local run.

Moving to PostgreSQL once the node exists:

```sh
rm backend_override.tf
terraform init -migrate-state -backend-config=../../examples/backend-pg.hcl
```

## Variable examples

One `.tfvars.example` per layer. Copy to `terraform.tfvars` inside the layer directory —
`*.tfvars` is git-ignored so a real value cannot be committed by accident.

```sh
cd ../layers/3-github
cp ../../examples/3-github.tfvars.example terraform.tfvars
```

## Credentials never appear in a tfvars file

Every variable marked `sensitive` has no default and is supplied through the environment:

```sh
export TF_VAR_github_token=...
export TF_VAR_cloudflare_api_token=...
export TF_VAR_postgres_superuser_password=...
export TF_VAR_ssh_private_key="$(cat ~/.ssh/novashop)"
```

This is the same rule as the rest of the platform: runtime credentials live in
`/root/.novashop-platform.env` at 0600, and Kubernetes Secrets are created outside Git. See
[ADR 010](../../adr/010-secret-management.md).

A `.tfvars.example` containing a placeholder token is how a real token eventually gets
committed — someone edits the example instead of the copy. Placeholders here are obviously
invalid, and the real values have nowhere in the repository to live.
