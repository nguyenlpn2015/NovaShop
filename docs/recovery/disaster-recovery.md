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

## Recovering through Terraform

`recover.sh` remains the shortest path and is what a rehearsal should exercise. Since
Sprint 6 the same sequence is also expressible as Terraform layers, which is the route to
take when the node is being rebuilt from nothing rather than restored in place — the layers
carry the declarative inputs, so nothing depends on remembering flags.

```sh
cd terraform/layers/0-node      && terraform apply
cd ../1-datastores              && terraform apply
cd ../2-k3s                     && terraform apply
# restore certificate material here — before 6-gitops, for the reason above
cd ../5-cluster                 && terraform apply
cd ../6-gitops                  && terraform apply -var run_bootstrap=true
```

Then stop. Argo CD reconciles the remaining twelve Applications from Git on its own.
Terraform's last act is creating the root Application; see
[ADR 014](../../adr/014-terraform-gitops-handover.md).

Two orderings are not negotiable, and both are the same principle — restore state before the
thing that would otherwise recreate it:

**PostgreSQL is restored before Terraform runs at all.** The `pg` state backend lives in it.
A rebuild that starts Terraform first has nowhere to write state and, worse, may plan against
an empty state as though nothing exists. Where PostgreSQL is not yet available, the layers
run on local state via `backend-local-override.tf.example` and migrate afterwards.

**Certificate material is restored before `6-gitops`**, for the reason in step 7 above.

`terraform apply` in `6-gitops` needs `run_bootstrap=true`. The default is false so that a
routine apply on a healthy cluster does not silently re-run an installer that waits on
rollouts.

### Verifying the handover afterwards

```sh
cd terraform/layers/6-gitops
terraform output -json handover
terraform output -json verification_commands | jq -r '.[]'
```

Seven assertions run at plan time and report if the root Application has drifted — wrong
repository, pinned revision, `selfHeal` disabled, a registered repository the AppProject does
not permit, or a running Argo CD version that does not match the pinned digest. All five are
states in which `kubectl get applications` still reads `Synced/Healthy`, which is exactly why
they are worth asserting rather than eyeballing.

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
