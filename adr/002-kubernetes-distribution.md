# ADR 002: k3s as the Kubernetes distribution

## Status

Accepted

## Date

2026-08-01

## Context

The platform runs on one Ubuntu 22.04 server on a home lab network, with a single
operator. It has to be a real Kubernetes cluster — the point of the project is to
demonstrate platform engineering, and a container runtime with a reverse proxy would
not do that — but it also has to be operable and recoverable by one person without a
second machine to fall back on.

The hardware is 8GB of memory shared with PostgreSQL, Redis, and an observability
stack. Anything the control plane consumes is memory the workloads do not get.

Recovery matters more than usual here. With one node there is no rescheduling, so a
node loss is a total outage, and the restore path has to be something a person can
execute correctly while under pressure.

## Decision

k3s, currently v1.33.13+k3s1, single server node, with the default SQLite datastore.

The bundled Traefik and `local-path` provisioner are kept rather than replaced. Argo
CD, cert-manager, and the observability stack are installed on top.

## Alternatives Considered

**Full upstream Kubernetes (kubeadm).** The most faithful to what a production cluster
looks like, and the reason it was rejected is etcd. On a single node etcd is both a
memory cost and the component most likely to require expert intervention when it goes
wrong. Recovering an etcd cluster of one is a worse experience than restoring a file,
and the difference is felt precisely when things are already broken.

**Managed Kubernetes (EKS, GKE, AKS).** Removes the interesting parts. Bootstrap
reliability, disaster recovery from bare metal, and node-level concerns like inotify
limits and datastore configuration are the substance of this project, and a managed
control plane hides all of them. It also costs money indefinitely for a portfolio.

**MicroK8s.** Comparable footprint and a reasonable choice. Rejected because its
snap-based lifecycle is harder to script idempotently — the requirement that bootstrap
be safe to rerun is central here, and snap refresh behaviour is not something the
scripts control.

**k0s.** Also credible, also small. Rejected on ecosystem familiarity: k3s is the
distribution an interviewer is most likely to have opinions about, which makes the
decisions in this repository easier to discuss. A weaker technical argument than the
others, and stated as such.

**Docker Compose.** Genuinely simpler and genuinely sufficient for the application. It
cannot demonstrate GitOps reconciliation, admission-time policy, or progressive
delivery, which is the entire subject. Retained for local development only.

## Consequences

**Easier.** Single-binary install and teardown, so bootstrap and cleanup scripts are
short and idempotent. Backup is a file copy of
`/var/lib/rancher/k3s/server/db` rather than an etcd snapshot. Traefik and a storage
class exist from the first boot, so the platform can serve traffic before any of its
own components are installed.

**Harder, and accepted.**

*No high availability.* One node, no rescheduling, and every document says so rather
than implying otherwise. This is why [recovery](../docs/architecture/recovery-flow.md)
is a rehearsed procedure rather than an assumption about redundancy.

*SQLite is a single point of failure on the write path.* A corrupted datastore is
restored from backup; there is no quorum to repair it from.

*`local-path` is the only storage class.* Volumes are node-local and cannot outlive the
node. Persistent data is either in the backup or explicitly accepted as disposable —
Prometheus history, Loki chunks, and Alertmanager silences are the latter. Two traps
came with it: the provisioner writes the bound volume name back into the claim, needing
an `ignoreDifferences` entry, and the Helm key is `storageClass` in some charts and
`storageClassName` in others, where getting it wrong silently provisions from the
default.

*Bundled components are versioned by k3s.* Traefik arrives as chart 40.1.3+up40.1.0.
Upgrading Traefik independently means taking over its Helm release.

*Some control-plane metrics need flag changes.* Scraping the scheduler and
controller-manager requires `--kube-scheduler-arg` and `--kube-controller-manager-arg`
bind-address changes and a k3s restart, which is a maintenance window on a single node.
Deferred, and on the [roadmap](../docs/ROADMAP.md).

## Validation

```sh
kubectl version --short
k3s --version
kubectl get storageclass          # local-path, and only local-path
sudo ls /var/lib/rancher/k3s/server/db/state.db   # SQLite, not etcd
```

`scripts/validate-platform.sh` asserts the runtime version alignment that depends on
this choice, and `scripts/linux/verify.sh` asserts the cluster is serving in its
detected edge phase.
