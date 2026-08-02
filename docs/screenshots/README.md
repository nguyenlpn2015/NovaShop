# Screenshots

**This directory holds no images yet.** It holds the procedure for capturing them, so that
whoever does has a list rather than an instinct.

That is stated first because the alternative — a section promising screenshots and a folder
that does not have them — is the failure this repository keeps finding in its own
documentation.

## Why so few

Most of what this platform does is better shown as text than as a picture. `12/12 Synced and
Healthy` is a claim anyone can reproduce with one command; a screenshot of it is a claim
nobody can verify. Command output belongs in the documents that make the claim, and the
[README](../../README.md) links the live site directly.

Screenshots earn their place for exactly one thing: **consoles that are not publicly
reachable.** Argo CD and Grafana hold cluster state and sit behind no SSO, so they are not
exposed. A reader cannot see them any other way.

## What to capture

Six images, in this order. Each has a stated purpose — if a capture does not serve its
purpose, it is not worth adding.

| File | Shows | Purpose |
|---|---|---|
| `argocd-applications.png` | The Applications list, all 12 Synced and Healthy | The single most legible proof that GitOps is real here |
| `argocd-resource-tree.png` | `novashop-production` expanded to its resources | Shows sync waves and ownership, which no table conveys |
| `grafana-platform.png` | The platform dashboard with live data | Metrics are being collected, not merely configured |
| `grafana-logs.png` | Loki with a query returning journal and container logs | Two log sources, correctly labelled |
| `prometheus-targets.png` | `/targets`, 31 up | The page on which the scrape-port defect was found |
| `alerts-rules.png` | The rules list, 14 rules, none firing | Alerting exists and evaluates |

## How to reach each console

None is exposed publicly. Port-forward from a machine with cluster access.

```sh
# Argo CD — https://localhost:8080
kubectl -n argocd port-forward svc/argocd-server 8080:443
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d ; echo

# Grafana — http://localhost:3001
kubectl -n observability port-forward svc/novashop-grafana 3001:80
kubectl -n observability get secret novashop-grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d ; echo

# Prometheus — http://localhost:9090, then /targets and /alerts
kubectl -n observability port-forward svc/novashop-prometheus-server 9090:80
```

`scripts/port-forward.sh` does the same thing if you would rather not remember the names.

## Rules for a capture

**Redact before you save, not after you notice.** Tokens, passwords, Secret values,
repository credentials, internal hostnames and IP ranges. The Argo CD Applications page shows
repository URLs; the Grafana log panel will show whatever the logs contain.

**Leave the context visible.** Namespace, resource names, image tags, status columns, and the
timestamp. A cropped screenshot showing only green is worth nothing — the point is that a
reader can see *what* is green.

**Do not capture a state you arranged.** If something is OutOfSync, capture it OutOfSync and
say so in the caption. A dashboard curated for a portfolio is the same category of claim as a
document that overstates a backup.

**Keep them small.** PNG, under 500 KB, no wider than 1600 px. These are committed to Git
forever.

## Adding them

1. Save into this directory using the filenames above.
2. Add a row to the table in the [README](../../README.md) "Seeing it run" section.
3. Delete the sentence there that says this directory holds the procedure rather than images.
4. Include the capture date in the pull request — a screenshot is a point-in-time claim and
   ages differently from the text around it.
