# Disaster Recovery Exercise — 2026-08-02

Objective: exercise total node loss and validate recovery, bootstrap, GitOps, applications,
observability, TLS, and certificates.

## Headline

**Total node loss was not exercised.** What was exercised found that the recovery script
**could not have run at all** — it aborted at its first precondition on a completely healthy
platform, for a reason unrelated to any disaster.

That defect is fixed. It was found without destroying anything, and it would have been found
by nobody until the first real outage.

## Why total node loss was not exercised

Three reasons, in descending order of importance.

**The only backup lived on the node.** Simulating the loss of a node while reading the backup
from that node's disk tests the restore procedure and explicitly does not test the disaster.
Calling that a total-node-loss exercise would be a false claim. This has now been fixed —
see below — but it was true at the start of the exercise.

**There is no second machine.** Access to this platform is SSH to `10.10.1.45` and nothing
else. No console, no hypervisor, no out-of-band management. A rebuild that broke networking
or SSH would leave the platform unrecoverable remotely, and the operator would need physical
access.

**Certificate reissue is rate limited.** Let's Encrypt allows five duplicate certificates per
hostname set per 168 hours. The current certificates were issued around 2026-07-31, so part
of that budget is already spent. A failed restore during the exercise would consume more, on
three environments.

## What was fixed during the exercise

### The backup now exists off the node

For the first time, the irreplaceable material is stored somewhere other than the disk it
protects:

```
21,702 bytes — 3 TLS Secrets, 2 ACME account keys, PostgreSQL dump,
               platform environment file, manifest with checksums
```

Verified away from the node: 0 checksum mismatches, all three certificates parse as valid
PEM with private keys present, both ACME account keys present, the environment file declares
all seven credentials.

The size is the point. The full on-node backup set is 27 MB and the platform's local-path
volumes are 550 MB; the part that genuinely cannot be regenerated is **21 KB**. That
validates the tiering in the backup strategy — the useful backup is small because Git
reproduces almost everything.

### `recover.sh` could not run

```
[linux/recover] MISSING: platform environment file declares DATABASE_URL and REDIS_URL
[linux/recover] ERROR: 1 precondition(s) are unmet.
```

The check grepped `^[[:space:]]*DATABASE_URL=`. The real file declares
`export DATABASE_URL=`. Zero matches. Recovery aborted before touching anything, on a healthy
platform.

Two things make this worse than a typo:

**The same mismatch was found and fixed in `configure-datastores.sh` earlier in this
project.** It survived in `recover.sh` because that script had never been executed.

**Every review had passed it.** The logic reads correctly. Only running it exposes the gap
between what the script expects and what the platform actually writes.

Fixed to accept the optional `export` prefix. Preconditions now pass:

```
OK: platform environment file /root/.novashop-platform.env
OK: repository reachable: NovaShop.git
OK: repository reachable: NovaShop-GitOps.git
OK: public DNS records resolve
OK: certificate backup /srv/dr-exercise/certs
All preconditions are satisfied.
```

## Validation results

| Area | Result | Evidence |
|---|---|---|
| **Recovery — preconditions** | **PASS after fix** | Was a hard abort; now all five pass |
| **Recovery — full sequence** | **NOT EXERCISED** | See above |
| **Bootstrap** | **PARTIAL** | `rebuild_cluster` ran against the live node and was correctly idempotent — k3s uptime unchanged at 2d5h, nothing restarted. Not proof it works on a bare node. |
| **GitOps** | **PASS** | Service deleted from a live namespace, recreated by Argo CD in **5 s** with a new UID, endpoints healthy |
| **Applications** | **PASS (steady state)** | 12/12 Synced/Healthy before and after every test |
| **Observability** | **PASS (steady state)** | 9/9 pods Running; not exercised through a rebuild |
| **TLS** | **PARTIAL** | Certificates verified restorable from the off-node copy; the restore path itself was not run |
| **Certificates** | **PASS (material)** | 3 certificates + 2 ACME account keys extracted, parsed, and validated away from the node |
| **Database recovery** | **PASS** | 137 rows restored into a scratch database, content md5 identical |

## RTO

**Not measured end to end.** Component timings that were measured:

| Step | Measured | Source |
|---|---|---|
| Preconditions | ~10 s | this exercise |
| Single resource reconcile | **5 s** | Service deleted and restored |
| Slowest single Application sync | **62 s** | cert-manager, from `operationState` |
| Other Application syncs | 0–3 s | all eleven others |
| Database restore (empty schema) | < 5 s | this exercise |

**Estimated RTO: 30–45 minutes** on a prepared replacement node, dominated by OS
preparation, k3s installation, and image pulls — none of which were measured, because that
requires the node this exercise could not destroy.

Treat that number as an engineering estimate, not a demonstrated figure. The honest
statement is that **RTO is unknown** until a replacement node has actually been built.

## RPO

**Currently unbounded.** Backups are manual. Nothing schedules them, so the recovery point is
"whenever someone last remembered", which for the datastore backup was today, because this
exercise created it.

| If implemented | RPO |
|---|---|
| Daily timer (designed, not built) | 24 hours |
| PostgreSQL WAL archiving (`archive_mode=off` today) | minutes |

One mitigating fact and one aggravating one. Mitigating: the `novashop` database has **zero
tables**, so the current data loss exposure is nil. Aggravating: that will stop being true
the day the application gains a schema, and nothing about the backup schedule will change on
its own that day.

## Lessons learned

**A recovery script that has never been run has not been tested, and review does not
substitute.** The `export` prefix bug passed every reading of the code. It took thirty
seconds of execution to surface. This is the second time the same class of bug has appeared
in this project.

**A backup on the disk it protects is not a backup for the failure mode you have.** This
platform's only real failure is losing the node. Until today every backup was on that node.
The fix was cheap — 21 KB moved off — and the reason it had not been done was that nobody
had asked what the backup was actually protecting against.

**Documentation drifts toward optimism.** Two documents claimed `backup-platform-state.sh`
captured the SQLite datastore and the runtime environment. It never did. Someone reading
that claim stops looking, which is how the database went unprotected while the repository
described a working backup.

**"Assume total node loss" cannot be assumed away.** The parts of recovery that are cheap to
test — preconditions, GitOps reconciliation, database restore — were tested and pass. The
parts that are expensive — OS rebuild, k3s from bare metal, certificate adoption on a fresh
cluster, observability restart — are exactly the parts most likely to contain the next
`export` bug, and they remain untested.

**I ran further than intended.** `recover.sh` was invoked with a timeout to observe its
preconditions, and it proceeded into `rebuild_cluster` before the timeout fired. No harm
resulted, because the install scripts are idempotent — verified afterwards: k3s uptime
unchanged, 12/12 Applications healthy, certificates untouched. Relying on that was luck
rather than design. A `--preconditions-only` flag would have made the safe thing the easy
thing, and is the first recommendation below.

## Recommendations

| # | Action | Why |
|---|---|---|
| 1 | Add `--preconditions-only` to `recover.sh` | Makes the safe inspection safe by construction |
| 2 | Automate the off-node copy | Today's copy was created by hand and will go stale |
| 3 | systemd timer plus a `BackupStale` alert | The platform already has Prometheus and 14 runbook-backed alerts; this needs no new technology |
| 4 | **Rehearse on a real replacement node** | The only way RTO becomes a number rather than an estimate |
| 5 | Enable PostgreSQL WAL archiving before the application gains a schema | Moves RPO from 24 hours to minutes, and the right time is before there is data |
| 6 | Add a `verify.sh` assertion that recovery preconditions pass | This defect would have been caught the day it was introduced |

Recommendation 4 is the one that matters. Everything else is preparation for it.

## Exercise artefacts

The off-node backup is held outside the repository and outside the node. It contains private
keys and credentials and must not be committed — `.gitignore` blocks `tls-*.json`,
`acme-*.json`, `runtime-*.json`, and `platform-state*/` for that reason.

On the node, `/srv/dr-exercise` holds the same set and should be moved or removed once a
scheduled off-node copy exists.
