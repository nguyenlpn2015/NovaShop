# Module 1 — Linux and the Node

*Part 1 · Foundations · Beginner to Intermediate*

Everything in NovaShop runs on one Ubuntu 22.04 machine at `10.10.1.45`. Before Kubernetes,
before GitOps, there is a Linux box that has to be prepared correctly — and the most
instructive failure in this entire repository is a kernel limit.

## 1. Learning Objectives

After this module you can:

- Explain why every bootstrap script here uses **marked managed blocks** rather than appending
- Describe what `fs.inotify.max_user_instances` does and why exhausting it is a **correctness**
  problem, not a performance one
- Explain why enabling UFW without `MANAGEMENT_CIDR` would have locked the operator out
- Read `scripts/linux/bootstrap.sh` and say what each phase guarantees
- Say why swap must be off and why the reboot check runs *before* package installation

## 2. Theory

**Idempotence** means running something twice produces the same result as running it once. For
a bootstrap script it means more: it must be safe to run *during an incident*, on a machine
that is already half-configured, without making things worse.

The naive way to configure a service is to append lines to its config file. Run it twice and
you have duplicates. The pattern used throughout NovaShop is a **marked managed block**:

```
# BEGIN novashop managed block
...content...
# END novashop managed block
```

The script renders the block it wants, compares it with what is on disk, and **restarts the
service only if the content actually changed**. That last clause is what makes it safe to run
during an outage.

**sysctl** exposes kernel parameters. Settings applied with `sysctl -w` are lost on reboot;
settings written to `/etc/sysctl.d/*.conf` persist.

**inotify** is the kernel subsystem that lets a process watch files for changes. Two limits
matter: `max_user_watches` (how many files can be watched) and `max_user_instances` (how many
watchers can exist per user). The default for instances is **128**.

## 3. Repository Walkthrough

Open each of these.

| File | What to look for |
|---|---|
| `scripts/linux/bootstrap.sh` | `main()` at the bottom — read it first; it is the whole story in twenty lines |
| `scripts/linux/bootstrap.sh` → `prepare_server()` | The reboot check runs **before** `apt-get`. Why? |
| `scripts/linux/bootstrap.sh` → `configure_firewall()` | It does nothing unless `ENABLE_UFW=true` |
| `scripts/linux/configure-node-limits.sh` | The whole file — it is 100 lines and the header comment is the lesson |
| `scripts/linux/configure-datastores.sh` | The managed-block pattern, applied to PostgreSQL and Redis |
| `scripts/lib/edge-phase.sh` | Note it has **no** `set -Eeuo pipefail` — and that is correct |

### The bootstrap sequence

```
load_platform_environment   →  refuse to start without credentials
prepare_server              →  reboot check, packages, swap, time, hostname
configure_firewall          →  only if MANAGEMENT_CIDR is set
verify_remote_repository    →  both Git repos reachable BEFORE handing over control
install-k3s.sh
install-helm.sh
install-argocd.sh           →  manifest verified against a pinned SHA-256
bootstrap.sh                →  applies the root Application; Argo CD takes over
detect_edge_phase           →  read what actually reconciled
verify.sh                   →  assert the properties of that phase
```

Three details worth pausing on.

**The reboot check runs first.** `prepare_server()` refuses to continue if
`/var/run/reboot-required` exists — *before* running `apt-get`. Upgrading first can create that
flag and abort a rerun through the script's own side effect, which is the opposite of
rerun-safe.

**Repository reachability is checked before Argo CD is handed control.** Applying the root
Application against an unreachable repository leaves Argo CD installed, in charge, and unable
to render anything — a state that looks like a cluster problem and is a network problem.

**The edge phase is detected, not assumed.** A script that can be *told* which phase it is in
can be told the wrong one.

## 4. Architecture Explanation

This module is the bottom of [Deployment](../../architecture/deployment.md) and the first half
of [Bootstrap Flow](../../architecture/bootstrap-flow.md).

**What breaks elsewhere if this is wrong:**

| Node-level mistake | Symptom, far away |
|---|---|
| inotify limit too low | Traefik stops noticing certificate renewals; cert-manager stops noticing work |
| PostgreSQL bound to loopback only | Every backend replica goes NotReady; Traefik returns 503 |
| Swap enabled | kubelet refuses to start, or behaves unpredictably under memory pressure |
| Clock not synchronised | TLS validation and Kubernetes token expiry both misbehave |
| UFW without `MANAGEMENT_CIDR` | You lose SSH to the only node in the platform |

## 5. Hands-on Lab

You need a throwaway Linux VM or container with root. **Do not run this on the live node.**

### Part A — see the limit that caused the incident

```sh
sysctl fs.inotify.max_user_instances    # very likely 128
sysctl fs.inotify.max_user_watches
```

Now exhaust it deliberately:

```sh
# Each background inotifywait consumes one instance.
# apt-get install -y inotify-tools
for i in $(seq 1 200); do inotifywait -q -m /tmp >/dev/null 2>&1 & done
sleep 2
inotifywait -q -m /tmp
```

You should see `Failed to watch /tmp; ... upper limit on inotify instances reached`.

```sh
kill %1 %2 %3 2>/dev/null; pkill inotifywait
```

**The lesson is the failure mode, not the error.** A well-written program prints that message
and exits. Traefik printed it and **kept running** — with whatever configuration it had loaded
at startup, silently deaf to every subsequent change.

### Part B — apply the fix the way NovaShop does

```sh
sudo bash scripts/linux/configure-node-limits.sh
```

Read the output. Then run it **again**. Note that the second run reports the file is already
correct and changes nothing — that is idempotence, and it is why this is safe during an
incident.

```sh
cat /etc/sysctl.d/90-novashop-inotify.conf
sysctl fs.inotify.max_user_instances    # now 512
```

### Verification

```sh
test "$(sysctl -n fs.inotify.max_user_instances)" -ge 512 && echo PASS || echo FAIL
```

The script itself asserts this before exiting — it does not trust that writing the file worked.

## 6. Exercises

**6.1** Change `MAX_USER_INSTANCES` to `128` and run the script. Read the error. Why does the
script refuse a value the kernel would accept?

**6.2** In `configure-datastores.sh`, find where the script decides whether to restart
PostgreSQL. Write in one sentence the condition under which it does *not* restart, and why that
matters during an incident.

**6.3** `scripts/lib/edge-phase.sh` has no `set -Eeuo pipefail` while all nineteen other scripts
do. Explain why that is correct rather than an oversight. *(Hint: how is this file used?)*

**6.4** Run `bash scripts/linux/recover.sh --preconditions-only` on a machine with no
`/root/.novashop-platform.env`. What does it report, and what does it **not** do?

## 7. Challenge

`configure_firewall()` refuses to enable UFW unless `MANAGEMENT_CIDR` is set explicitly. The
operator's workstation is `192.168.3.2`; the node is `10.10.1.45`.

**Design a safer UFW enablement.** Requirements: it must not be possible to lock yourself out,
and it must work when the operator's source address is unknown in advance.

Consider — and reject or accept with reasons — each of: a default of `10.10.0.0/16`; deriving
the CIDR from the current SSH connection's source; a dead-man's-switch that disables UFW after
five minutes unless confirmed; simply not managing the firewall from a script.

Write your answer as an ADR using [`adr/000-template.md`](../../../adr/000-template.md). It must
have an *Alternatives Considered* section where each rejected option carries a specific
drawback.

## 8. Quiz

1. What is the default `fs.inotify.max_user_instances` on Ubuntu 22.04?
2. Why is inotify exhaustion described as a correctness problem rather than a performance one?
3. Why does `prepare_server()` check for a pending reboot *before* installing packages?
4. What does a "marked managed block" give you that appending does not?
5. Why does `verify_remote_repository` run before the root Application is applied?
6. Why does `edge-phase.sh` omit strict mode?
7. **True or false:** setting `sysctl -w fs.inotify.max_user_instances=512` is sufficient.
8. Why must swap be disabled?

<details>
<summary>Answers</summary>

1. 128. This node reached 140 in use.
2. Because a workload that cannot create a watcher does not fail — it keeps running with the
   configuration it loaded at startup and silently stops noticing changes. On this platform that
   means a renewed certificate or a synced manifest that never takes effect.
3. Because installing or upgrading packages can itself create `/var/run/reboot-required`, and a
   rerun would then abort because of the script's own side effect.
4. Idempotence, plus the ability to compare desired against actual and **restart only on
   change** — which is what makes it safe to run during an incident.
5. Otherwise Argo CD ends up installed and in charge but unable to render anything, which
   presents as a cluster problem and is a network problem.
6. It is sourced by other scripts. `set -e` in a sourced file changes the *caller's* behaviour.
7. **False.** It is lost on reboot. The setting must go in `/etc/sysctl.d/`, which is what the
   script does — and it then verifies the applied value rather than trusting the write.
8. kubelet expects swap off; memory accounting and eviction behave unpredictably otherwise.
   `prepare_server()` refuses to continue if swap is active rather than disabling it silently.

</details>

## 9. Troubleshooting

Real defects from this platform.

### "failed to create fsnotify watcher: too many open files"

**Symptom.** Traefik logs it once at startup. Nothing else appears wrong: pods Running, HTTPS
serving, Argo CD Synced.

**Why it is misleading.** The message looks like a warning. It is not — Traefik watches its
dynamic configuration, and a Traefik that cannot create a watcher keeps serving the routes it
already has and never learns about new ones.

**How it was found.** Reading logs while investigating something else. Nothing alerted.

**Fix.** `configure-node-limits.sh`, then **restart anything that already logged it** — a
process that failed to create a watcher does not retry.

### PostgreSQL reachable from the node but not from pods

**Symptom.** `psql` works on the node. Every backend replica is NotReady. Traefik returns 503.

**Why it is misleading.** The database is genuinely up. The fault is `listen_addresses` or
`pg_hba.conf`, and from inside a pod `localhost` is the pod.

**Fix.** Rerun `configure-datastores.sh` — idempotent, and it writes both settings into managed
blocks.

### `recover.sh` aborts on a healthy platform

**Symptom.** `MISSING: platform environment file declares DATABASE_URL and REDIS_URL`.

**Why it is misleading.** The file *does* declare them — as `export DATABASE_URL=`. The check
grepped `^[[:space:]]*DATABASE_URL=` and matched nothing.

**How it was found.** By running the script. It had survived the entire project because nobody
had. The same mismatch had already been fixed in `configure-datastores.sh`.

## 10. Best Practices

| Practice | Where NovaShop demonstrates it |
|---|---|
| Strict mode in every executable script | 19 of 20 scripts; the exception is a sourced library |
| Managed blocks, restart only on change | `configure-datastores.sh`, `configure-node-limits.sh` |
| Verify the result, do not trust the write | `configure-node-limits.sh` re-reads the applied sysctl |
| Refuse rather than guess a dangerous default | UFW requires an explicit `MANAGEMENT_CIDR` |
| Check reachability before handing over control | `verify_remote_repository` before the root Application |
| Detect state, do not accept it as a parameter | `detect_edge_phase` |

**Deliberately not followed:** the node layer is **not** managed by a configuration management
tool. Ansible is genuinely the better tool for this job, and
[ADR 012](../../../adr/012-terraform-scope.md) rejects it — a second orchestration tool with a
second state model, for one node whose scripts are already idempotent and self-verifying. That
argument is thin and the ADR says so. Form your own view.

## 11. Interview Questions

- *Why is inotify exhaustion a correctness problem?* → [S16](../../interview/questions.md)
- *Why is `MANAGEMENT_CIDR` required before UFW is enabled?* → [S21](../../interview/questions.md)
- *What does `scripts/linux/bootstrap.sh` do?* → [B20](../../interview/questions.md)
- *Why does `verify.sh` detect the edge phase rather than take it as input?* → [I7](../../interview/questions.md)

## 12. Further Reading

- [`inotify(7)`](https://man7.org/linux/man-pages/man7/inotify.7.html) — the `max_user_instances` limit
- [`sysctl.d(5)`](https://man7.org/linux/man-pages/man5/sysctl.d.5.html)
- [ADR 002 — Kubernetes distribution](../../../adr/002-kubernetes-distribution.md) — why one node, and what follows
- [Bootstrap Flow](../../architecture/bootstrap-flow.md)
- [`scripts/README.md`](../../../scripts/README.md)

---

**Next:** Module 2 — Git and GitHub as a Platform *(specified, not yet written)*.
Or jump to [Module 4 — Containers and Images](04-containers-and-images.md) ✅.
