# Evidence Catalog

Every artefact worth capturing, numbered in the order a demonstration should run. Filenames
are fixed here so that the images, the recordings, and the transcripts sort into the demo
sequence on their own.

Related: [Portfolio Evidence](PORTFOLIO_EVIDENCE.md) for what to *say*,
[screenshots/](screenshots/) for how to reach each console and the redaction rules.

## Screenshots

| # | Evidence | File | Where | Caption |
|---|---|---|---|---|
| 01 | Public homepage | `01-homepage.png` | novashop.smartdev.vn | Production, serving over HTTPS |
| 02 | HTTPS certificate | `02-tls.png` | Padlock → certificate | Let's Encrypt production, renewal monitored |
| 03 | Three environments | `03-environments.png` | Three tabs | One Helm chart, three value sets |
| 04 | Health endpoints | `04-health-endpoints.png` | `api.…/health`, `/live`, `/ready` | `/live` checks nothing; `/ready` checks dependencies |
| 05 | GitHub Actions | `05-github-actions.png` | Actions, latest green run | Five required checks |
| 06 | Scan before push | `06-scan-before-push.png` | `release.yml` job graph | Registry login only after Trivy passes |
| 07 | GHCR images | `07-ghcr-images.png` | Packages | Both components, one commit SHA |
| 08 | Pinned revision | `08-gitops-pinned-sha.png` | An Application in NovaShop-GitOps | Desired state pins source by SHA, never a branch |
| 09 | Argo CD applications | `09-argocd.png` | Applications list | 12/12 Synced and Healthy |
| 10 | Argo CD resource tree | `10-argocd-tree.png` | `novashop-production`, expanded | Ownership and sync-wave ordering |
| 11 | Prometheus targets | `11-prometheus-targets.png` | `/targets` | 31/31 up — where the scrape-port defect was found |
| 12 | Grafana overview | `12-grafana.png` | Platform dashboard | Dashboards provisioned from Git, not the UI |
| 13 | Loki logs | `13-loki.png` | Grafana → Explore → Loki | Journal and container logs, distinctly labelled |
| 14 | Alert rules | `14-alert-rules.png` | Prometheus `/alerts` | 14 rules, none firing |
| 15 | Alertmanager | `15-alertmanager.png` | `localhost:9093` | Grouping and inhibition; routing deliberately unset |
| 16 | Runbook | `16-runbook.png` | `observability/runbooks/argo-sync-failed.md` | The response is written before the alert can fire |
| 17 | Kubernetes pods | `17-k8s-pods.png` | `kubectl get pods -A` | One node, everything on it |
| 18 | Namespaces and PSA | `18-namespaces-psa.png` | `kubectl get ns --show-labels` | `restricted` enforced on application namespaces |
| 19 | Network policies | `19-network-policies.png` | `kubectl get netpol -A` | Default-deny ingress, trialled live with a control group |
| 20 | Terraform plan | `20-terraform-plan.png` | `terraform plan` in `5-cluster` | No changes — import-not-create, proven by a clean plan |
| 21 | Backup verification | `21-backup-verify.png` | `verify-backup.sh` | SHA-256 per artefact, not a file count |
| 22 | Audit scores | `22-audit-scores.png` | [AUDIT.md](AUDIT.md) | Production Readiness 2/5, self-scored |

Images 09 to 15 need a port-forward — commands in [screenshots/](screenshots/).

## Screen recordings

| # | Evidence | File | Length | Must show |
|---|---|---|---|---|
| V1 | Deployment walkthrough | `v1-gitops-deployment.mp4` | 3–4 min | Merge → Actions → GHCR → GitOps pull request → Argo CD sync, unedited |
| V2 | Argo CD tour | `v2-argocd-tour.mp4` | 2 min | App-of-apps, ApplicationSet, resource tree, a sync |
| V3 | Observability tour | `v3-observability-tour.mp4` | 2–3 min | Grafana → targets → a Loki query → the alert rules |
| V4 | Guardrail rejection | `v4-guardrail-blocks.mp4` | 90 s | Break a pin, run the gate, watch it refuse |
| V5 | Pod Security rejection | `v5-psa-rejects-pod.mp4` | 60 s | Apply a privileged pod; the API server refuses it |
| V6 | Backup and restore | `v6-backup-restore.mp4` | 3 min | Backup, verify, restore; row count and checksum match |

V4 is the most persuasive ninety seconds available. A guardrail described is a claim; a
guardrail refusing a change on camera is not.

## CLI transcripts

Save as text alongside the images. Text is greppable and ages better than a screenshot.

| # | Evidence | File | Command |
|---|---|---|---|
| C1 | Platform gate | `c1-validate-platform.txt` | `validate-platform.sh --gitops-dir ../NovaShop-GitOps` |
| C2 | Revision gate | `c2-validate-revisions.txt` | `validate-gitops-revisions.sh --gitops-dir ../NovaShop-GitOps` |
| C3 | Observability gate | `c3-validate-observability.txt` | `validate-observability.sh --gitops-dir ../NovaShop-GitOps` |
| C4 | Application state | `c4-argocd-applications.txt` | `kubectl get applications -n argocd` |
| C5 | Sync-wave ordering | `c5-sync-waves.txt` | `grep -rn sync-wave ../NovaShop-GitOps/clusters/ \| sort -t'"' -k2 -n` |
| C6 | Node resources | `c6-node-resources.txt` | `kubectl top node && kubectl describe node \| grep -A5 Allocated` |
| C7 | Certificates | `c7-certificates.txt` | `kubectl get certificate -A` |
| C8 | Terraform plan | `c8-terraform-plan.txt` | `terraform plan` in `5-cluster` |
| C9 | Recovery preconditions | `c9-recovery-preconditions.txt` | `recover.sh --preconditions-only` |
| C10 | Link audit | `c10-link-audit.txt` | The script in [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md) §3 |

**C6 matters more than it looks.** It shows the node at roughly 150 percent committed memory
limits. Volunteering that is worth more than any green dashboard.

## Deliberate absences

Worth one slide. Naming these is stronger than skipping them silently.

| Not captured | Why | Reference |
|---|---|---|
| Tempo trace | Not deployed. Instrumentation exists and is disabled | [ADR 011](../adr/011-distributed-tracing.md) |
| OpenTelemetry Collector | Nothing sends OTLP | Same |
| Swagger in production | `/docs` returns 404; enabled for local development only | `localhost:8000/docs` |
| Traefik dashboard | Not configured, and not to be exposed | [traefik.md](networking/traefik.md) |
| Kubernetes Dashboard | Not deployed | — |
| Alert notification | Alerts evaluate but route nowhere | Needs a credential and an on-call decision |
| Full recovery run | Never exercised on a replacement node; RTO is an estimate | [AUDIT.md](AUDIT.md) |

The node's hostname is `sd-tempo-mcp`. It appears in
`kubernetes/observability/prometheus/helm-values.yaml` and has nothing to do with Grafana
Tempo. Do not let a grep mislead a viewer into thinking tracing is deployed.

## Two capture warnings specific to this platform

**Do not capture `api.novashop.smartdev.vn/metrics`.** It is publicly reachable and exposes
the build version, the full route inventory, and traffic volumes.

**Do not curate the Argo CD page.** If something is OutOfSync, capture it OutOfSync and
caption why. A screenshot arranged to look green is the same category of claim as a document
that overstates a backup — and this repository's credibility rests on not doing that.
