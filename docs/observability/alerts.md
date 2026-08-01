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

## Notification routing is not configured

Alertmanager has a single receiver named `default` with no destination.

This is deliberate rather than unfinished. Routing to Slack, email, or PagerDuty
needs a credential this repository does not hold and a decision about who is on
call, and neither belongs in a default that nobody reviewed. Alerts still
evaluate, still appear in the Alertmanager UI, and are still queryable as
`ALERTS{alertstate="firing"}` in Prometheus and on the Grafana dashboards, so the
rules are useful before delivery exists.

Adding a destination is a values change plus a Secret, in the same pattern as the
Grafana admin credential:

```sh
# 1. Create the Secret outside Git, as with novashop-grafana-admin.
kubectl -n observability create secret generic novashop-alertmanager-slack \
  --from-literal=webhook-url='https://hooks.slack.com/services/...'
```

```yaml
# 2. In alerting-values.yaml, mount it and reference the file.
alertmanager:
  extraSecretMounts:
    - name: slack
      secretName: novashop-alertmanager-slack
      mountPath: /etc/alertmanager/secrets
      readOnly: true
  config:
    receivers:
      - name: default
        slack_configs:
          - api_url_file: /etc/alertmanager/secrets/webhook-url
            channel: "#novashop-alerts"
            title: '{{ .CommonLabels.alertname }}'
            text: '{{ range .Alerts }}{{ .Annotations.summary }}
              <{{ .Annotations.runbook_url }}|runbook>
              {{ end }}'
```

The `runbook_url` is included in the message body on purpose: the link is most
useful at the moment the notification arrives, not after someone has found the
right document.

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
