# Portfolio Evidence Checklist

Capture screenshots only after validation passes. Keep the current context,
resource names, image tags, and status columns visible. Redact passwords,
tokens, repository credentials, and Secret values.

- [ ] Docker Desktop Kubernetes view showing the cluster running.
- [ ] `docker desktop kubernetes status`.
- [ ] `kubectl config current-context` showing `docker-desktop`.
- [ ] `kubectl get nodes -o wide` with every node `Ready`.
- [ ] `kubectl get namespaces`.
- [ ] `kubectl get pods -A` with Argo CD, Traefik, and NovaShop ready.
- [ ] `kubectl get services -A`.
- [ ] `kubectl get ingress -A`.
- [ ] Argo CD login page at `https://localhost:8080`.
- [ ] Argo CD applications dashboard.
- [ ] `novashop-root` showing `Synced` and `Healthy`.
- [ ] `novashop-development` showing `Synced` and `Healthy`.
- [ ] `novashop` ApplicationSet showing three generated applications.
- [ ] Argo CD application resource tree.
- [ ] Traefik Service and NovaShop Ingress.
- [ ] NovaShop homepage with `dev.novashop.local` visible in the browser.
- [ ] Backend `/health` response with the browser URL visible.
- [ ] GitHub Actions CI and release workflows passing.
- [ ] GHCR backend image with immutable Git SHA tag.
- [ ] GHCR frontend image with the same immutable Git SHA tag.
- [ ] NovaShop-GitOps pull request or commit that selected the deployed SHA.
