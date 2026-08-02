# Network Policy

Ingress is default-deny in every NovaShop application namespace, with four explicit
exceptions. Cross-namespace reachability was verified blocked; the edge, kubelet probes, and
metrics scraping were verified still working.

## Enforcement was proven before anything was written

A NetworkPolicy on a cluster that does not enforce them is the worst kind of control: it
appears in `kubectl get networkpolicy` and does nothing. So the first thing checked was
whether k3s enforces them at all.

```
kube-router processes           2
netpol iptables chains        123

probe namespace, no policy    REACHABLE
probe namespace, deny-all     BLOCKED
```

k3s runs kube-router's network policy controller by default. Only `--disable-network-policy`
turns it off, and it is not set here.

## The policies

| Policy | Effect |
|---|---|
| `default-deny-ingress` | Nothing reaches these pods unless a rule below allows it |
| `allow-edge-and-probes` | Traefik in `kube-system`, plus the node network, to ports 8000 and 3000 |
| `allow-metrics-scrape` | The `observability` namespace to port 8000 |
| `allow-same-namespace` | Pods within the namespace reach each other |

Namespaces are matched on `kubernetes.io/metadata.name`, which the API server sets on every
namespace. No label had to be added anywhere.

## The kubelet is why one rule looks too broad

`allow-edge-and-probes` admits the node network, not just `kube-system`.

Readiness and liveness probes originate on the **node**, not from a pod. A namespace-only
rule takes every replica `NotReady` the moment it is applied — and with no ready endpoint,
Traefik returns 503. The node network is admitted for that reason and scoped to
`10.10.1.0/24` rather than left open.

This was verified rather than assumed: pods stayed `1/1 Running` and HTTPS stayed `200`
through the whole trial.

## Egress is deliberately not restricted

The backend reaches PostgreSQL and Redis on the node's LAN address over the pod network, and
`/ready` checks both. An egress rule that gets that wrong takes every replica unready — a
platform outage caused by a hardening change.

Ingress carries most of the value regardless: it stops a compromised pod in one environment
from reaching pods in another, which is the realistic lateral-movement path on a single-node
cluster running three environments side by side.

Egress restriction is a reasonable follow-up and should be trialled the same way: one
namespace, on a live cluster, with the datastore reachability checked before and after.

## Validation

Trialled against the live `novashop-development` namespace before being committed, then
removed so GitOps creates them as tracked resources.

| Check | Result |
|---|---|
| Control — staging to staging, no policy | **REACHABLE** |
| staging to development | **BLOCKED** |
| production to development | **BLOCKED** |
| development to itself, same namespace | **REACHABLE** |
| Pods stayed Ready — kubelet probes | **1/1 Running** throughout |
| Edge — `https://dev.novashop.smartdev.vn/` | **200** before and after |
| Prometheus scraping the backend | **1/1 targets up** |
| Argo CD | **12/12 Synced/Healthy** throughout |

### Two things the trial caught

**kube-router takes several seconds to program rules for a new pod.** The first isolation
run reported `BLOCKED` for same-namespace traffic, which would have meant the policy was
wrong. It was a race: a short-lived probe pod ran `wget` before its rules existed. With a
20-second settle the same test reports `REACHABLE`.

That cut both ways. The cross-namespace `BLOCKED` result from the same run was equally
suspect, so every probe was re-run with the settle and a no-policy control. Only then were
the results sound. A test that produces the answer you expected, for the wrong reason, is
worse than no test.

**Pod Security Admission is genuinely enforced.** The first probes returned nothing at all,
because `kubectl run busybox` does not satisfy `restricted`:

```
Error from server (Forbidden): pods "psa-check" is forbidden:
violates PodSecurity "restricted:latest": allowPrivilegeEscalation != false,
unrestricted capabilities, runAsNonRoot != true, seccompProfile
```

Worth recording as a positive finding — the application namespaces reject non-compliant pods
today — and worth knowing before writing any diagnostic pod for them.

## Reproducing

```sh
kubectl -n novashop-staging apply -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata: {name: xns}
spec:
  restartPolicy: Never
  securityContext: {runAsNonRoot: true, runAsUser: 10001, seccompProfile: {type: RuntimeDefault}}
  containers:
    - name: p
      image: public.ecr.aws/docker/library/busybox:1.36
      command: ["sh","-c","sleep 20; wget -q -T 5 -O- http://<dev-pod-ip>:8000/live >/dev/null 2>&1 && echo REACHABLE || echo BLOCKED"]
      securityContext:
        allowPrivilegeEscalation: false
        capabilities: {drop: ["ALL"]}
        readOnlyRootFilesystem: true
YAML
kubectl -n novashop-staging logs xns
```

The `sleep 20` is not padding. Without it the result is a race, and the race happens to
produce the answer you were hoping for.

## What is still open

| Gap | Note |
|---|---|
| `observability` has no policies | Prometheus needs broad egress to scrape; the ingress side is worth doing |
| `cert-manager` has no policies | Small surface, but unprotected |
| No egress restriction anywhere | See above |
| Host datastores reachable from any pod | A NetworkPolicy cannot express "only the backend may reach 10.10.1.45:5432"; that needs an egress policy plus host firewall rules |

## Related

- [Hardening](hardening.md)
- [Networking](../architecture/networking.md)
- [Repository audit](../AUDIT.md)
