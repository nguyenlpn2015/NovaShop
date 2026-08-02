# Glossary

General terms, and the platform-specific ones that appear throughout this repository and
are not obvious from their names.

## Platform-specific

| Term | Meaning here |
|---|---|
| **Edge phase** | Which TLS stage the cluster has reconciled: `http`, `tls-baseline`, or `tls-enforced`. Detected from live state by `scripts/lib/edge-phase.sh`, never assumed — see [TLS Flow](architecture/tls-flow.md) |
| **App-of-apps** | `novashop-root`, the single Argo CD Application every other object descends from. Terraform creates it and stops — [ADR 014](../adr/014-terraform-gitops-handover.md) |
| **Sync wave** | Argo CD ordering annotation, most negative first. Ranges from `-30` (AppProject) to `10` (applications) |
| **`managedNamespaceMetadata`** | ApplicationSet field that reapplies namespace labels every sync. Why three namespaces look unmanaged and are not — [ADR 013](../adr/013-terraform-kubernetes-boundary.md) |
| **Durable pin** | A `targetRevision` that is a 40-character SHA **and** an ancestor of `origin/main`, so a force-push cannot orphan it |
| **Guardrail** | A pre-merge check that fails a pull request. 93 of them across three scripts |
| **Silent success** | A change that renders, validates, deploys, and does nothing — the failure mode most of this platform's checks exist to catch. See the [Engineering Log](LEARNING_LOG.md) |
| **Predicted live state** | Argo CD's server-side apply dry-run. With `ServerSideApply`, this and not the rendered manifest is what sync status compares against |
| **Layer** (Terraform) | A root module with its own state and backend schema. Seven of them, numbered by dependency order |

## General

| Term | Description |
|---|---|
| ADR | Architecture Decision Record |
| ACME | Automated Certificate Management Environment — the Let's Encrypt protocol |
| CNI | Container Network Interface. k3s uses flannel, with kube-router for NetworkPolicy |
| GitOps | Git as the single source of truth, reconciled by a controller in the cluster |
| HPA | Horizontal Pod Autoscaler — not used here; replica counts are fixed in values files |
| HSTS | HTTP Strict Transport Security. Why rollback must serve `max-age=0` first |
| IaC | Infrastructure as Code |
| OCI | Open Container Initiative |
| OTEL | OpenTelemetry — instrumented, not deployed ([ADR 011](../adr/011-distributed-tracing.md)) |
| PDB | Pod Disruption Budget — meaningless on one node |
| PSA | Pod Security Admission. Enforced at `restricted` in application namespaces |
| RPO / RTO | Recovery Point / Time Objective — see the [DR exercise](recovery/dr-exercise-2026-08-02.md) |
| SBOM | Software Bill of Materials — not yet produced |
| SRE | Site Reliability Engineering |
