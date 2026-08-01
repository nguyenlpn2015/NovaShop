# Disaster Recovery

Rebuilds NovaShop on a replacement Ubuntu 22.04 node from the GitOps repository,
the existing public DNS records, and a certificate backup.

Recovery is not bootstrap with a different name. Bootstrap converges a node
toward the desired state and may be rerun freely. Recovery runs when production is
already down, so it refuses to start unless every input it needs is present.
Discovering a missing input halfway through leaves the platform in a worse state
than before.

## What recovery does and does not reproduce

| Category | Source | Notes |
|----------|--------|-------|
| Namespaces, workloads, Services, Ingresses, Middlewares | Git | Rendered by Argo CD |
| cert-manager, ClusterIssuers, `Certificate` resources | Git | Declarative |
| Argo CD projects and applications | Git | Applied by bootstrap |
| Container images | GHCR | Referenced by immutable commit tag |
| TLS private keys | **backup** | Cannot be reproduced |
| ACME account key | **backup** | Cannot be reproduced |
| Runtime database and Redis credentials | platform environment file | Not in Git |
| Public DNS records | pre-existing infrastructure | Not created by recovery |
| Database contents | database backups | Out of scope for this runbook |

Only two items cannot be regenerated from Git, and both are certificate material.
That is the entire reason the backup exists.

## Prepare while the platform is healthy

```bash
bash scripts/backup-platform-state.sh --output-dir /srv/novashop-state
```

The directory is created with mode `0700` and every file with mode `0600`. It
contains private keys. Move it to protected storage outside the cluster and
outside this repository; `.gitignore` blocks the export filenames so they cannot
be committed by accident.

Include `--include-runtime-secrets` only when the platform environment file is not
part of the recovery plan. By default the database and Redis Secrets are skipped
because they are reproducible from that file.

Verify the backup contains what you expect:

```bash
ls -l /srv/novashop-state
cat /srv/novashop-state/platform-state.txt
```

The inventory records the Argo CD application revisions, the reconciled edge
phase per environment, and each certificate expiry date at the time of capture.

## Preconditions

Recovery checks all of these and reports them together:

- [ ] `/root/.novashop-platform.env` exists, is owned by root, has mode `0600`,
      and declares both `DATABASE_URL` and `REDIS_URL`.
- [ ] `https://github.com/nguyenlpn2015/NovaShop.git` is reachable on `main`.
- [ ] `https://github.com/nguyenlpn2015/NovaShop-GitOps.git` is reachable on `main`.
- [ ] Every environment hostname resolves in DNS.
- [ ] A certificate backup is available, or reissue is explicitly accepted.

A hostname that resolves to an address other than the node is reported as a note
rather than a failure, because a proxy or NAT in front of the node is a supported
topology.

## Recover

```bash
export NODE_IP='10.10.1.45'
bash scripts/linux/recover.sh --from-backup /srv/novashop-state
```

Without a backup:

```bash
bash scripts/linux/recover.sh --accept-certificate-reissue
```

Let's Encrypt permits five duplicate certificates per identical hostname set per
168 hours. A rebuild without a backup consumes one of those for each environment,
which can leave no headroom for a later rollback cycle. Prefer the backup.

## Sequence

1. Preconditions are verified. Any failure aborts before k3s is touched.
2. The platform environment file is loaded.
3. k3s is installed at the pinned version and the node becomes `Ready`.
4. Helm is installed with checksum verification.
5. Traefik, owned by k3s, becomes available.
6. Argo CD is installed from the digest-verified manifest.
7. **Certificate material is restored.** Namespaces are created so the Secrets can
   be placed before cert-manager reconciles.
8. `scripts/bootstrap.sh` applies the Argo CD project and root application, and
   Argo CD reconciles everything else from Git.
9. `scripts/linux/verify.sh` runs against the edge phase detected in the cluster.

Step 7 must precede step 8. cert-manager adopts an existing valid Secret and
schedules a normal renewal; if it reconciles first, it requests a new certificate
and the backup becomes pointless.

## After recovery

```bash
kubectl get applications --namespace argocd \
  --selector=app.kubernetes.io/part-of=novashop
bash scripts/linux/verify.sh
```

Confirm explicitly:

- [ ] Every Argo CD application is `Synced` and `Healthy`.
- [ ] Certificates are `Ready` with the expected remaining lifetime, and the
      restored expiry matches `platform-state.txt`.
- [ ] The reconciled edge phase matches what production ran before the incident.
- [ ] HTTPS serves a publicly trusted chain without `--insecure`.
- [ ] A fresh backup has been taken, because the previous one is now consumed
      history.

Record the incident, the recovery duration, and whether certificates were
restored or reissued.

## Node rebuild without a disaster

A planned rebuild follows the same path, with one addition: take the backup
first, then tear down explicitly.

```bash
bash scripts/backup-platform-state.sh --output-dir /srv/novashop-state
bash scripts/linux/cleanup.sh --confirm --include-argocd \
  --uninstall-k3s --confirm-k3s-uninstall
```

`scripts/cleanup.sh` refuses to delete namespaces holding TLS Secrets unless
`--accept-certificate-loss` is passed, so a rebuild cannot silently destroy
certificate material.

## Related

- [Platform Guardrails](../PLATFORM_GUARDRAILS.md)
- [Recovery, bootstrap, and release flows](../../diagrams/PLATFORM_GUARDRAILS.md)
- [Operations](../OPERATIONS.md)
- [ADR 001: Platform Guardrails](../../adr/001-platform-guardrails.md)
