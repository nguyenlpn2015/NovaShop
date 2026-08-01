# Runbook: MemoryHigh

**Severity:** warning · **Fires after:** 15 minutes · **Threshold:** above 85% used

## What it means

The node is close to memory exhaustion. This platform is knowingly overcommitted:
container memory *limits* sum to more than allocatable memory, which is safe only
while workloads stay near their requests.

## Impact

Once memory runs out the kernel OOM killer chooses a victim by score, not by
importance. It has already killed the Loki rules sidecar on this node. A killed
container restarts, so the visible symptom is usually a crash loop rather than
anything that says "out of memory".

## Diagnose

```sh
free -h
sudo k3s kubectl top pods -A --sort-by=memory | head -20
sudo dmesg -T | grep -i 'killed process' | tail
```

Compare real usage against what each workload asked for:

```sh
sudo k3s kubectl get pods -A -o custom-columns='NS:.metadata.namespace,POD:.metadata.name,REQ:.spec.containers[*].resources.requests.memory,LIM:.spec.containers[*].resources.limits.memory'
```

## Fix

If one workload sits far above its request, the request is wrong. Correct it in
Git and let Argo CD apply it — a live edit is reverted by self-heal within three
minutes.

If total usage is legitimately high, reduce replicas. The production backend runs
six replicas on a single node, which demonstrates scaling rather than meeting a
capacity requirement.

## Context

Node capacity at last measurement: CPU limits 150% and memory limits 153% of
allocatable. Overcommit is intentional and documented, but it means this alert
deserves a real look rather than a threshold bump.
