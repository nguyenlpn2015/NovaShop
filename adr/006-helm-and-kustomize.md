# ADR 006: Helm and Kustomize, each for what it is good at

## Status

Accepted

## Date

2026-08-01

## Context

The platform packages two kinds of thing, and they have opposite requirements.

**The application** is one chart deployed three times, differing by namespace, replica
count, image tag, hostname, and resource sizing. The variation is parametric — the same
shape with different numbers — and it is authored here.

**Platform components** are upstream charts: Traefik, cert-manager, Prometheus, Grafana,
Loki, Alloy, two exporters. They are not authored here and must not be forked. What is
needed is to supply values, and occasionally to compose and order a set of Argo CD
Application objects around them.

Using one tool for both means using the wrong tool for one of them. A chart whose
`values.yaml` has grown a boolean for every environmental difference, or a Kustomize
overlay patching an upstream chart's rendered output, are the two failure modes.

## Decision

**Helm** for anything installed: the NovaShop application chart in `helm/novashop`, and
every upstream platform component through its own values file.

**Kustomize** for composing and ordering Argo CD objects: `clusters/ubuntu-k3s` is an
overlay over `clusters/base`, assembling the three edge phases (`http`,
`tls-baseline`, `tls-enforced`).

Kustomize never patches rendered chart output. Helm never expresses phase composition.

Platform values files are named `*-values.yaml` — `helm-values.yaml`,
`alerting-values.yaml` — so they are distinguishable from manifests. This is not
cosmetic: `kubeconform` rejects a values file as a manifest missing `kind`, and
`validate-platform.sh` excludes them by that suffix.

## Alternatives Considered

**Helm only.** Every platform component gets a wrapper chart with the upstream as a
dependency, and phase ordering becomes conditionals in templates. Rejected because
expressing "these Applications belong to the TLS-baseline phase" as Helm conditionals
produces templates whose output nobody can predict by reading them, and because wrapper
charts add a version to bump for no functional gain.

**Kustomize only.** Render upstream charts once, commit the output, patch it. Rejected
decisively: a committed render is a fork. Upgrading a chart becomes a manual re-render
plus conflict resolution, and the values that produced the output are lost. The
`helm-values.yaml` files are readable statements of intent; a 1,500-line rendered
manifest is not.

**Kustomize's Helm chart inflator.** Tempting, since it appears to give both. Rejected
because Argo CD's Helm source support is first-class and its multi-source Applications
already compose a chart with values from another repository. Inflating through Kustomize
adds a layer that has to be enabled with `--enable-helm` and reasoned about in every
gate.

**Raw manifests, no templating.** Three copies of every application manifest. Rejected:
three copies drift, and the drift is silent because each copy is individually valid.

**Jsonnet or cdk8s.** Real answers to the same problem and both stronger at complex
logic. Rejected on a maintainability judgement: Helm and Kustomize are what a platform
engineer joining this repository will already know, and this platform's variation is
simple enough that a general-purpose language would be solving a problem it does not have.

## Consequences

**Easier.** Upgrading an upstream component is a version bump in one Application plus a
values review. Adding an environment is one entry in the `ApplicationSet` generator plus
a values file. Phase composition is readable as directories.

**Harder, and accepted.**

*Two tools to know.* The boundary has to be understood, or someone will patch a rendered
chart in a hurry.

*Two rendering paths to validate.* `validate-platform.sh` therefore runs both
`kustomize build` on every overlay and `helm lint` plus `helm template` per environment,
across both in-cluster and `ubuntu-k3s` value combinations — because a chart that renders
for one target and not another is a real failure mode.

*Values file ordering is load-bearing.* Prometheus now takes two values files — scrape
configuration and alerting. Helm merges later files over earlier ones, so the Argo CD
Application and the validation gate must list them in the same order. The gate renders
both, in that order, so what CI checks is what the cluster runs.

*Naming convention carries weight.* The `*-values.yaml` suffix is what keeps a values
file out of schema validation. It was originally the literal name `helm-values.yaml`,
which broke the moment a chart needed a second values file.

## Validation

```sh
bash scripts/validate-platform.sh --gitops-dir ../NovaShop-GitOps
```

Asserts every Kustomize overlay builds, every chart renders and lints per environment
and per target, and every rendered document passes `kubeconform`. `helm-values.yaml` and
`alerting-values.yaml` are excluded from schema validation by suffix, and the suffix is
verified to select only files with no `kind`.
