# Deployment Target B Portfolio Evidence

Capture a coherent deployment sequence. Show timestamps and resource names,
but redact passwords, tokens, kubeconfigs, Secret data, private repository
credentials, SSH private keys, and internal database endpoints.

## Infrastructure

- [ ] Hypervisor view showing the Ubuntu VM powered on.
- [ ] VM summary showing CPU, RAM, disk, and network allocation.
- [ ] Ubuntu Server 22.04 console or SSH session.
- [ ] `hostnamectl` showing `novashop-k3s`.
- [ ] `ip -brief -4 address` showing `10.10.1.45`.
- [ ] `timedatectl status` showing synchronized time.
- [ ] `df -hT` and `lsblk --fs` showing persistent storage.
- [ ] `sudo ufw status verbose` showing restricted management access and
      public ingress ports.

## k3s Platform

- [ ] `k3s --version`.
- [ ] `sudo systemctl status k3s` showing `active (running)`.
- [ ] `kubectl cluster-info`.
- [ ] `kubectl get nodes -o wide` showing the node `Ready`.
- [ ] `kubectl get pods -A` showing platform and application pods ready.
- [ ] `kubectl top nodes`.
- [ ] `kubectl top pods -A`.
- [ ] k3s-bundled containerd version.
- [ ] Traefik Deployment, Service, and Pods.
- [ ] NovaShop Ingress objects with address `10.10.1.45`.

## GitOps

- [ ] Argo CD version and control-plane pods.
- [ ] Argo CD login page reached through an SSH port forward.
- [ ] Argo CD dashboard showing `novashop-root`.
- [ ] ApplicationSet `novashop`.
- [ ] Development, staging, and production Applications.
- [ ] `Synced` status for every Application.
- [ ] `Healthy` status for every Application.
- [ ] Argo CD resource tree for `novashop-development`.
- [ ] Application source panels showing both public HTTPS repositories and no
      repository comparison errors.
- [ ] GitOps pull request that selected the deployed immutable image SHA.

## Application

- [ ] `kubectl get deployments -A` showing expected replica availability.
- [ ] GHCR image references from all NovaShop Deployments.
- [ ] NovaShop homepage with the browser URL visible.
- [ ] Backend `/health` response with the browser URL visible.
- [ ] Traefik access evidence for the development hostname.
- [ ] Backend and frontend startup logs without errors.

## Delivery Chain

- [ ] NovaShop GitHub repository overview.
- [ ] NovaShop-GitOps repository overview and directory structure.
- [ ] Successful CI workflow.
- [ ] Successful release workflow.
- [ ] Backend GHCR package and immutable tag.
- [ ] Frontend GHCR package and immutable tag.
- [ ] Image provenance/SBOM evidence.
- [ ] Git commit or release SHA matching the running Deployments.

## Operations

- [ ] Validation script completing successfully.
- [ ] Backup artifact name and checksum, without exposing backup contents.
- [ ] A documented rollback commit or controlled rollback exercise.
- [ ] k3s restart followed by node and Application health verification.
- [ ] Metrics output demonstrating post-deployment resource consumption.

## Suggested Storyboard

1. VM specification and Ubuntu identity.
2. Network, time, firewall, and storage preparation.
3. k3s installation and node readiness.
4. Traefik and Argo CD readiness.
5. GitOps repository and ApplicationSet reconciliation.
6. All Applications `Synced` and `Healthy`.
7. Immutable images running from GHCR.
8. Frontend and backend browser verification.
9. CI, release, and GitOps pull-request audit trail.
10. Backup, validation, and operational evidence.
