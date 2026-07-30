# NovaShop Deployment Targets

```text
                              NovaShop
                                  |
                   +--------------+--------------+
                   |                             |
        Deployment Target A          Deployment Target B
        Docker Desktop Kubernetes    Ubuntu Server + k3s
        Windows 11                    Linux
        Development workstation       Production-like platform lab
                   |                             |
                   +--------------+--------------+
                                  |
                    Shared delivery contract
                                  |
                    +-------------+-------------+
                    |             |             |
               Same Helm     Same GitOps   Same Argo CD
                  Chart       Repository
                    |             |             |
                    +-------------+-------------+
                                  |
                         GitHub Actions
                                  |
                                GHCR
```

## Shared Contract

Both targets consume:

- the same NovaShop application repository;
- the same versioned Helm chart;
- the same `NovaShop-GitOps` desired state;
- the same Argo CD AppProject, root Application, and ApplicationSet;
- the same immutable GHCR images;
- the same GitHub Actions build and release pipeline.

Target-specific automation stops at the platform boundary. Application
promotion, synchronization, self-healing, pruning, and rollback remain GitOps
operations on both targets.

## Platform Boundaries

| Boundary | Target A | Target B |
|----------|----------|----------|
| Host | Windows 11 workstation | Ubuntu Server 22.04 VM |
| Kubernetes | Docker Desktop Kubernetes | Single-node k3s |
| Ingress | Helm-managed Traefik | k3s-bundled Traefik |
| Access | Local port-forward and hosts file | Private LAN DNS and SSH tunnel |
| Purpose | Fast local development and validation | Persistent production-like operations lab |
| Lifecycle | Developer-controlled | systemd and infrastructure operations |
| Availability claim | Local-only | Single-node; not highly available |
