# GitOps Runtime

```mermaid
flowchart TD
    developer[Developer]
    github[GitHub<br/>NovaShop]
    actions[GitHub Actions]
    ghcr[GitHub Container Registry]
    gitops[GitHub<br/>NovaShop-GitOps]
    argocd[Argo CD]
    k3s[k3s]
    traefik[Traefik]
    novashop[NovaShop<br/>Frontend and Backend]
    browser[Browser]

    developer -->|Pull request| github
    github -->|Validated commit| actions
    actions -->|Immutable images| ghcr
    actions -.->|Future deployment PR| gitops
    developer -->|Reviewed desired state| gitops
    gitops -->|Reconcile| argocd
    argocd -->|Render pinned Helm chart| k3s
    ghcr -->|Pull images| k3s
    k3s --> traefik
    traefik --> novashop
    novashop --> browser
```
