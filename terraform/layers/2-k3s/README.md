# Layer 2 — k3s

The k3s version and the arguments the server runs with.

> **Phase 1: foundation only.** No resources are declared. `terraform plan` produces an
> empty plan and evaluates the outputs from variables alone.

## What this layer does not do

It installs k3s and stops. There is **no `kubernetes` provider and no `helm` provider here,
and there will not be one.**

Everything inside the cluster belongs to Argo CD. A `kubernetes` provider configured in this
layer is the first step toward two controllers reconciling one object: `selfHeal` would
revert Terraform every three minutes and `terraform plan` would never converge. See
[../../README.md](../../README.md) for the boundary and
[ADR 012](../../../adr/012-terraform-scope.md) for why it is drawn there.

## The control-plane metrics flags

```hcl
k3s_server_args = [
  "--kube-scheduler-arg=bind-address=0.0.0.0",
  "--kube-controller-manager-arg=bind-address=0.0.0.0",
]
```

These are what make the scheduler and controller-manager scrapable. They have been an
outstanding item precisely because applying them needs a k3s restart, and on a single node a
restart is a control-plane outage that has to be scheduled.

Expressing them as a variable turns "remember to add these flags during the next maintenance
window" into a declarative change with a plan a reviewer can see before it happens. The
`control_plane_metrics_enabled` output lets the observability gate assert the property rather
than infer it.

## Traefik stays

`disable_components` is empty and a `check` block refuses to accept `traefik` in it.

Disabling Traefik would leave the cluster with no ingress, and therefore nothing able to
answer an HTTP-01 challenge — so no certificate could ever be issued. The edge has to serve
plain HTTP before any certificate exists; that ordering is the whole reason the TLS phases
exist. See [ADR 007](../../../adr/007-ingress-controller.md).

## Changing the version is disruptive

A k3s upgrade restarts the API server. Workloads keep running, but nothing can be observed or
changed while it happens, and Traefik is a bundled component versioned by k3s — so an upgrade
aimed at the API server can move the ingress too.

Take a backup first, and re-run the observability gate afterwards. The procedure is in
[docs/operations/platform-upgrade.md](../../../docs/operations/platform-upgrade.md).

## Configuration

This layer does **not** read an SSH private key, and does not read `node_user` either. Both are
declared so every node-facing layer takes the same inputs; neither is consumed here. The only
layer that consumes `ssh_private_key` is [`6-gitops`](../6-gitops/README.md), whose `main.tf`
passes it to a connection block.

The instruction to export it used to be here, and it was wrong: it taught an operator to put a
private key into the environment of a process that never reads it.

```sh
cp ../../examples/2-k3s.tfvars.example terraform.tfvars

cp ../../examples/backend-local-override.tf.example backend_override.tf
terraform init
terraform plan
```
