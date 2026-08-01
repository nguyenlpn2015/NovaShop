# Runbook: NodeDown

**Severity:** critical · **Fires after:** 2 minutes · **Expression:** `up{job="kubernetes-nodes"} == 0`

## What it means

Prometheus cannot scrape the kubelet. This is a single node cluster, so the node
being unreachable and the cluster being down are the same event.

It does *not* prove workloads have stopped. Containers keep running when the
kubelet stops answering; what is lost is the ability to observe and control them.

## Impact

Everything. There is no second node to reschedule onto.

## Diagnose

```sh
ssh smartdev@10.10.1.45            # if this fails, the fault is below Kubernetes
sudo systemctl status k3s
sudo journalctl -u k3s -n 200 --no-pager
sudo k3s kubectl get nodes -o wide
```

Distinguish three cases:

| Symptom | Cause |
|---|---|
| SSH fails | Host or network down — the cluster is a symptom, not the fault |
| SSH works, k3s inactive | The k3s service died; read the journal for why |
| k3s active, node `NotReady` | kubelet is up but a node condition is failing |

## Fix

If k3s is not running:

```sh
sudo systemctl start k3s
sudo systemctl status k3s
```

If it starts and immediately exits, the journal names the reason. The two seen on
this platform are a full disk ([DiskFull](disk-full.md)) and exhausted inotify
instances, which `scripts/linux/configure-node-limits.sh` corrects.

If the host itself is gone, this is a disaster recovery event:
[disaster-recovery.md](../../recovery/disaster-recovery.md).

## Verify

```sh
sudo k3s kubectl get nodes
sudo k3s kubectl get applications -n argocd
```

All twelve Argo CD applications should return to Synced/Healthy without help.
