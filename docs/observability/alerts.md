# Alerting

Prometheus evaluates the rules in
[`kubernetes/observability/prometheus/alerting-values.yaml`](../../kubernetes/observability/prometheus/alerting-values.yaml)
and sends anything firing to Alertmanager, which runs as a StatefulSet in the
`observability` namespace and is discovered by pod service discovery.

## The rules

| Alert | Severity | For | Fires when |
|---|---|---|---|
| [NodeDown](runbooks/node-down.md) | critical | 2m | The kubelet stops answering scrapes |
| [DiskFull](runbooks/disk-full.md) | critical | 10m | Root filesystem below 15% free |
| [MemoryHigh](runbooks/memory-high.md) | warning | 15m | Node memory above 85% |
| [CPUHigh](runbooks/cpu-high.md) | warning | 15m | Node CPU above 85% |
| [PodCrashLooping](runbooks/pod-crashlooping.md) | critical | 5m | More than 3 restarts in 15 minutes |
| [DeploymentFailed](runbooks/deployment-failed.md) | critical | 10m | Available replicas below desired |
| [ArgoSyncFailed](runbooks/argo-sync-failed.md) | warning | 30m | An Application is not Synced |
| [DatabaseDown](runbooks/database-down.md) | critical | 2m | `pg_up == 0` |
| [RedisDown](runbooks/redis-down.md) | critical | 2m | `redis_up == 0` |
| [CertificateExpiring](runbooks/certificate-expiring.md) | critical | 1h | Fewer than 21 days remaining |
| [IngressErrors](runbooks/ingress-errors.md) | critical | 10m | Over 5% 5xx at the edge |
| [HighLatency](runbooks/high-latency.md) | warning | 10m | Edge p95 above one second |
| [ApplicationErrorRate](runbooks/application-error-rate.md) | critical | 10m | Over 5% 5xx inside the application |
| [ObservabilityVolumeFilling](runbooks/observability-volume-filling.md) | warning | 15m | An observability PVC below 20% free |

Fourteen rather than the thirteen originally scoped. `ObservabilityVolumeFilling`
was added because every other alert here depends on Prometheus having somewhere
to write; without it, the failure that blinds the whole stack is the one nothing
watches.

## Why each rule looks the way it does

**Every alert names a runbook, and the runbook exists.** This is enforced by
`scripts/validate-observability.sh`, which reads the rendered rules, requires a
`runbook_url` on each alert, and resolves it to a file in this repository. A link
to a document nobody wrote is worse than no link, because it is only discovered by
whoever is following it during an incident.

**Every expression was evaluated against live data before merge.** Not for whether
it fires — most should not — but for whether its label selectors match anything at
all. An alert built on a mistyped label name parses, renders, deploys, and never
fires, and looks exactly like a healthy platform. Checking this caught that the
edge alerts needed pinning to `job="traefik"`, because Traefik is currently
scraped by two jobs at once.

**Durations are set so that normal operation does not trigger them.** A rolling
update completes well inside `DeploymentFailed`'s ten minutes. Argo CD self-heals
inside `ArgoSyncFailed`'s thirty. `CertificateExpiring` fires at 21 days because
cert-manager renews at about 30, so reaching the threshold proves renewal has
already been failing for a week.

**Severity means something.** `critical` is user-visible or imminent data loss.
`warning` is a trend that becomes critical if ignored. `ArgoSyncFailed` is a
warning even though it sounds severe: the cluster keeps serving what it last
converged to, and what is broken is the ability to deploy.

## Grouping and inhibition

Alerts are grouped by `alertname` and `namespace`, so one fault across six backend
replicas produces one notification. `repeat_interval` is twelve hours; anything
shorter trains people to mute the channel, which is worse than not alerting.

Two inhibition rules suppress derived noise:

- A `critical` alert suppresses a `warning` with the same `alertname` and
  `instance`.
- `NodeDown` suppresses everything else for that instance. A node that is down
  also breaches CPU, memory, and disk. Reporting all four turns one fault into
  four pages, and the three extra ones point at the wrong problem.

## Notification routing

Alertmanager routes every alert to one receiver, `email`, which delivers to the
on-call mailbox `nguyen.lephuoc@smartdev.com` from `nguyenlpn2015@gmail.com`.

This closes the gap the README and [AUDIT.md](../AUDIT.md) both recorded: fourteen
alerts, each with a runbook, and nowhere for any of them to go. An alerting
system that cannot notify is a monitoring system.

`send_resolved` is on. Without it the mailbox records that something broke and
never that it recovered, so the reader has to open Alertmanager to find out —
which defeats the point of sending mail.

The message body is Alertmanager's default, which renders every annotation. That
means `runbook_url` arrives with the alert without any template here having to
know about it, and the link is available at the moment it is most useful rather
than after someone has gone looking for the right document.

### The credential is not in Git

The SMTP password is read from a file that a Secret provides, using
Alertmanager's `smtp_auth_password_file`. Same pattern as the Grafana admin
credential, and the reason is the same: ADR 010 keeps credentials out of this
repository.

**The Secret must exist before Alertmanager is rolled out.** kubelet cannot mount
a Secret that does not exist, so the pod would sit in `ContainerCreating`
indefinitely — taking down a component that currently works.

```sh
# A Google App Password, NOT the account password. Google has refused plain
# account passwords for SMTP since 2022, and the failure is a 535 at send time,
# long after every config check has passed. Generate one at
# https://myaccount.google.com/apppasswords (requires 2-Step Verification).
kubectl -n observability create secret generic novashop-alertmanager-smtp \
  --from-literal=password='<16-character app password, no spaces>'
```

The key name matters: `extraSecretMounts` mounts the whole Secret at
`/etc/alertmanager-smtp`, so the key becomes the filename, and
`smtp_auth_password_file` points at `/etc/alertmanager-smtp/password`.

### Why Gmail forces two specific settings

**Port 587, not 465.** 465 is implicit TLS and `smtp_smarthost` does not
negotiate it — the connection hangs rather than failing loudly.

**`smtp_from` must equal `smtp_auth_username`.** Gmail rewrites or rejects a
`From` it did not authenticate, and a rejected message is dropped with only a
line in the Alertmanager log to record it.

### One receiver, not a severity split

A second route with a shorter `repeat_interval` for criticals is the obvious next
step and is deliberately absent. There is one recipient and no rota, so "page
faster" would mean the same mailbox at a higher rate — which is how a channel
gets muted, and a muted channel is worse than no channel.

### Confirming delivery actually works

A config that parses is not a config that sends. After the Secret exists and the
rollout completes:

```sh
# 1. The pod mounted the Secret and started.
kubectl -n observability get pod -l app.kubernetes.io/name=alertmanager

# 2. Alertmanager loaded the config it was given.
kubectl -n observability port-forward svc/novashop-prometheus-alertmanager 9093:9093
curl -s localhost:9093/api/v2/status | python3 -c "import json,sys;print(json.load(sys.stdin)['config']['original'][:400])"

# 3. Send a synthetic alert and watch for it in the mailbox.
curl -s -XPOST localhost:9093/api/v2/alerts -H 'content-type: application/json' -d '[{
  "labels": {"alertname": "RoutingSmokeTest", "severity": "warning", "namespace": "observability"},
  "annotations": {"summary": "Synthetic alert confirming email delivery"}
}]'

# 4. If nothing arrives, the reason is in the log -- a 535 means the password is
#    wrong or is not an App Password.
kubectl -n observability logs -l app.kubernetes.io/name=alertmanager --tail=50 | grep -i "notify\|smtp\|error"
```

Step 3 is the only step that proves the path end to end. Steps 1 and 2 prove
Alertmanager is happy, which is not the same claim.

## Verification

`scripts/validate-observability.sh` runs in CI and, for alerting specifically:

1. Renders Prometheus with **both** values files, in the order the Argo CD
   Application lists them, so the gate validates what the cluster actually runs.
2. Runs `promtool check rules` on the generated `alerting_rules.yml`. A rule file
   that does not parse is refused whole, so one bad expression silences every
   alert in the file while all of them still look correct in Git.
3. Asserts every alert has a `severity`, a `summary`, and a `runbook_url`
   resolving to a file that exists.

What the gate cannot check is whether an expression matches real label names. That
was verified by hand against live Prometheus before merge, and the results are in
the pull request.
