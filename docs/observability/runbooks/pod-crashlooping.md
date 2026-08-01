# Runbook: PodCrashLooping

**Severity:** critical · **Fires after:** 5 minutes · **Threshold:** more than 3 restarts in 15 minutes

## What it means

A container is starting and dying repeatedly. Kubernetes backs off between
restarts, so a crash loop can persist indefinitely without ever recovering on its
own.

## Diagnose

Read the *previous* container's logs, not the current one — the current container
is usually too young to have logged the fault:

```sh
NS=novashop-production
POD=<pod>
sudo k3s kubectl -n $NS logs $POD --previous --tail=100
sudo k3s kubectl -n $NS describe pod $POD | sed -n '/Last State/,/Events/p'
```

The exit code narrows it immediately:

| Exit code | Meaning |
|---|---|
| 137 | OOM killed — limit too low, or the workload leaked |
| 143 | SIGTERM, usually a failing probe |
| 1 or 2 | Application error — read the logs |
| 127 | Command not found — wrong image or entrypoint |

Logs outlive the pod in Loki, which matters when the container is restarting
faster than you can attach:

```logql
{source="kubernetes", namespace="novashop-production"} |= "error"
```

## Fix

- **137** — raise the memory limit in Git, or fix the leak. When this hit the Loki
  rules sidecar at 64Mi the correct fix was removing the sidecar, not growing it:
  nothing on this platform uses Loki rules.
- **Probe failure** — confirm the probe targets a port the container actually
  listens on. A scrape annotation pointing at the Service port rather than the
  container port produced exactly this class of bug here.
- **Application error** — roll back by reverting the GitOps commit that changed
  the image tag.

## Do not

Use `kubectl delete pod` as a fix. It restarts the loop from zero and destroys the
evidence in `--previous`.
