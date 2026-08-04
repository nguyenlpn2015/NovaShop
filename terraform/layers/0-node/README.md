# Layer 0 — Node

Packages, swap, kernel settings, and the firewall on the Ubuntu node.

> **Phase 1: foundation only.** No resources are declared. `terraform plan` produces an
> empty plan and evaluates the outputs from variables alone.

## How this layer avoids being a sham

Wrapping shell scripts in `remote-exec` and calling it Infrastructure as Code is the usual
way this goes wrong. The plan is either always empty or always dirty, Terraform has no idea
what is on the node, and the state records that something ran rather than what is true.

This layer works differently. The **desired state is rendered by Terraform** from templates,
and the **hash of the rendered content is the trigger**:

```hcl
resource "terraform_data" "sysctl" {
  triggers_replace = { content = local.sysctl_hash }
  provisioner "remote-exec" { inline = ["/opt/novashop/apply-sysctl.sh"] }
}
```

Change `inotify_max_user_instances` and the hash changes, so the plan shows a specific,
reviewable difference. Change nothing and the plan is empty. Terraform owns the inputs; the
existing idempotent scripts remain the executors, because they already verify their work and
restart services only when content actually changed.

That is the honest division of labour. Terraform is a good state engine and a poor
configuration management tool, and pretending otherwise produces a layer nobody can trust.

## `management_cidr` has no default, deliberately

UFW is left alone unless a management network is stated explicitly.

The operator workstation on this platform is `192.168.3.2`, which is **not** inside
`10.10.0.0/16`. A rule written for the node's own subnet would look entirely reasonable and
would lock the operator out of the only node in the platform, with no second machine to fix
it from.

`configure-datastores.sh` already refuses to enable UFW without this value. Modelling it as
an optional variable defaulting to `null`, plus a `check` block, preserves that refusal in
Terraform rather than quietly reintroducing the hazard.

## inotify is a correctness setting, not tuning

The kernel default of 128 instances was exhausted at 140 in use — every config reloader, log
collector, dashboard sidecar, and certificate watcher consumes one. Traefik logged:

```
failed to create fsnotify watcher: too many open files
```

A workload that cannot create a watcher **does not fail**. It keeps running with whatever it
loaded at startup and silently stops noticing changes, which here means a renewed certificate
or a synced manifest that never takes effect. The variable validation refuses anything below
256 for that reason.

## Configuration

This layer does **not** read an SSH private key. It declares `ssh_private_key` so every
node-facing layer takes the same inputs, but nothing here consumes it — the only layer that
does is [`6-gitops`](../6-gitops/README.md), whose `main.tf` passes it to a connection block.

The instruction to export it used to be here, and it was wrong: it taught an operator to put a
private key into the environment of a process that never reads it. A habit formed for no
benefit is still a habit.

```sh
cp ../../examples/0-node.tfvars.example terraform.tfvars

cp ../../examples/backend-local-override.tf.example backend_override.tf
terraform init
terraform plan
```

## Backend ordering

This layer prepares the host that PostgreSQL runs on, so on a first build it cannot store
state in a database it has not yet enabled. It runs on local state and is migrated with
`terraform state push` afterwards. In disaster recovery, PostgreSQL is restored before
Terraform runs at all — the same ordering principle as restoring certificates before Argo CD
reconciles.
