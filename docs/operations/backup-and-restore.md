# Backup and Restore

What is protected, what is not, and how to prove a backup works before you need it.

## Two scripts, and you need both

Neither covers what the other does. This trips people up, and it tripped up the
documentation: two architecture documents claimed `backup-platform-state.sh` captured the
SQLite datastore and the runtime environment. It never did — it exports Kubernetes Secrets.
`backup-datastores.sh` exists because of that gap.

| Script | Captures |
|---|---|
| [`backup-platform-state.sh`](../../scripts/backup-platform-state.sh) | TLS certificate Secrets, ACME account keys |
| [`backup-datastores.sh`](../../scripts/backup-datastores.sh) | PostgreSQL dumps, k3s SQLite datastore, the platform environment file |

```sh
sudo scripts/backup-platform-state.sh --output-dir /srv/novashop-state
sudo scripts/backup-datastores.sh     --output-dir /srv/novashop-backup
sudo scripts/verify-backup.sh /srv/novashop-backup/<timestamp>
```

## What is deliberately not backed up

The platform is mostly reproducible from Git. Backing up what Argo CD already reconciles
would grow a 12MB backup set to 650MB to protect data that regenerates.

| Not captured | Why |
|---|---|
| Redis | A cache. Losing it costs a warm-up, not data. |
| Prometheus, Loki, Grafana, Alertmanager volumes | 550MB of observational data already bounded by retention — 7 days and 5 days respectively |
| Every workload, Service, Ingress, Helm release | Reconciled from Git |

The k3s datastore *is* captured even though it is rebuildable, because it is cheap and turns
a ten-minute reconcile into a two-minute restore.

## The current state of the application database

`novashop` has **zero tables**. The application has no schema, no models, and no migrations.

So the backup currently protects an empty database. That is worth knowing and is not an
argument against having it: the right time to get backup and restore working is before there
is data to lose. `verify-backup.sh` reports an empty archive as a NOTE rather than a failure
for exactly this reason, and the note says plainly that the same output is a disaster once a
schema exists.

## Two things that are easy to get wrong

**Never copy the k3s datastore with `cp`.** k3s writes to SQLite continuously. A byte-for-byte
copy can capture a half-written page and produce a file that looks fine and is corrupt —
discovered at the moment it is needed. `backup-datastores.sh` uses `sqlite3 .backup`, the
online backup API, and verifies the result with `PRAGMA integrity_check`. k3s ships snapshot
support for etcd only; single-server k3s uses SQLite, so this has to be done here.

**`/ready` does not check that the database has data.** The backend probe checks that
PostgreSQL is *reachable*. Skip the data restore during recovery and the pods go Ready, every
Application reports Healthy, no alert fires, and the application serves an empty database.
Nothing on the platform catches that. `recover.sh` restores datastore contents before Argo CD
reconciles for this reason.

## Restore

```sh
sudo scripts/verify-backup.sh /srv/novashop-backup/<timestamp>
sudo scripts/restore-datastores.sh --from /srv/novashop-backup/<timestamp> --dry-run
sudo scripts/restore-datastores.sh --from /srv/novashop-backup/<timestamp>
```

| Flag | Use |
|---|---|
| `--dry-run` | Runs every precondition and reports what would happen. Changes nothing. |
| `--database NAME` | Restore into a scratch database. This is how you rehearse without touching production. |
| `--force` | Required to restore over a database that already has tables |
| `--include-k3s` | Stops k3s, replaces the datastore, restarts it |
| `--include-environment` | Restores `/root/.novashop-platform.env` |

**`--force` is deliberately required.** The realistic mistake is running a restore against a
healthy node, so overwriting populated tables has to be refused rather than warned about.

Preconditions are all checked before anything is modified. A restore that stops halfway has
produced a third state that is neither the old one nor the new one — and that has to be
diagnosed on top of the original outage.

## Full recovery

`recover.sh` orchestrates the sequence and the ordering is not negotiable:

1. Preconditions — all checked, nothing changed
2. Platform environment loaded
3. Cluster rebuilt
4. **Certificate material restored** — before Argo CD, or cert-manager requests a new
   certificate and spends one of five duplicates per 168 hours
5. **Datastore contents restored** — verified first, then restored
6. Argo CD reconciles everything from Git
7. `verify.sh` against the detected edge phase

```sh
sudo scripts/linux/recover.sh --from-backup /srv/novashop-backup/<timestamp>
```

## Rehearsing a restore

A backup that has never been restored is a hypothesis. Restore into a scratch database and
compare content, not just row counts:

```sh
sudo -u postgres psql -c 'DROP DATABASE IF EXISTS novashop_rehearsal;'
sudo scripts/restore-datastores.sh --from /srv/novashop-backup/<ts> --database novashop_rehearsal

# Compare source and restored. A row count alone will not catch truncated text.
sudo -u postgres psql -tAd novashop \
  -c "SELECT count(*) || '|' || md5(string_agg(t::text, ',' ORDER BY t::text)) FROM <table> t;"
sudo -u postgres psql -tAd novashop_rehearsal -c "<the same query>"

sudo -u postgres psql -c 'DROP DATABASE novashop_rehearsal;'
```

Monthly. Quarterly, do the whole thing onto a replacement node.

## Validation results

Run against the live platform on 2026-08-02.

| Test | Result |
|---|---|
| Backup captures PostgreSQL, SQLite, environment file | **PASS** — 27M set, manifest with a checksum per artefact |
| `verify-backup.sh` on a healthy set | **PASS** — 7 checks |
| Refuses to overwrite a populated database without `--force` | **PASS** — refused, nothing changed |
| `--dry-run` changes nothing | **PASS** |
| **Database recovery** — 137 rows into a scratch database | **PASS** — 137 rows out, content md5 identical |
| **GitOps recovery** — Service deleted from a live namespace | **PASS** — recreated in **5 seconds** with a new UID, endpoints healthy, 12/12 Applications Synced |
| Fresh VM restore | **NOT TESTED** — no second machine available |
| Node replacement | **NOT TESTED** — same reason |

The last two are the ones that matter most and the ones that could not be run. Every
component they depend on has been exercised individually, which is not the same as having
exercised the sequence. Until a replacement node has actually been built from a backup, full
recovery is a documented procedure rather than a demonstrated capability, and it should be
described that way.

## Bugs found by running this, not by reading it

Recorded because they are the argument for validating rather than reviewing:

**`sqlite3` was not installed on the node.** The backup script requires it. Added to the
bootstrap package list.

**The backup directory is `0700` root-owned, so the `postgres` user could not read the dump
it had just written.** `pg_restore --list` now runs as root — it only parses the archive
header and needs no database connection — and the restore feeds the archive on **stdin**, so
root opens the file and the postgres process inherits the descriptor. The alternative was
loosening permissions on a directory full of database dumps.

**`su` inherits the working directory**, so running from `/root/NovaShop` produced "could not
change directory" on every PostgreSQL call. Every `su` now runs from `/`.

**`IFS` was set to newline-and-tab**, which is correct for filenames and wrong for reading a
space-separated manifest: every artefact read as missing. Scoped per-loop.

**The node runs Ubuntu 22.04.5 LTS, not 24.04**, which five documents claimed. Corrected.

## Still open

**No off-node copy.** The backup lives on the disk it protects against losing, which is the
single failure mode this platform actually has. This needs a destination decision — another
machine on the LAN, or an S3-compatible endpoint — and until it is made, the backup protects
against a bad migration and nothing else.

**No schedule.** Nothing runs these automatically. A systemd timer plus a `BackupStale` alert
is the obvious next step: the platform already has Prometheus, node-exporter's textfile
collector, and fourteen runbook-backed alerts, so it needs no new technology.

**No point-in-time recovery.** PostgreSQL runs `archive_mode=off`, so the best possible RPO
is the last dump.

## Related

- [Disaster Recovery](../recovery/disaster-recovery.md)
- [Recovery Flow](../architecture/recovery-flow.md)
- [ADR 010: Secret management](../../adr/010-secret-management.md)
