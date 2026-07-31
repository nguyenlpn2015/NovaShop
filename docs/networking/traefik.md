# Traefik Edge Routing

k3s provides Traefik as the Kubernetes Ingress controller for Deployment
Target B. Traefik accepts traffic forwarded by FortiGate and routes it by SNI,
hostname, and path to cluster Services.

## Entry Points

| Entry point | Port | Purpose |
|-------------|------|---------|
| `web` | TCP 80 | ACME HTTP challenge and redirect to HTTPS |
| `websecure` | TCP 443 | TLS termination and application routing |

Confirm the installed Traefik configuration before depending on these names:

```bash
kubectl --namespace kube-system get deployment traefik
kubectl --namespace kube-system get service traefik
kubectl --namespace kube-system get pods \
  --selector=app.kubernetes.io/name=traefik
```

Do not expose the Traefik dashboard publicly. Use Kubernetes authorization and
a local port-forward for temporary operator access if the dashboard is enabled.

## Ingress and Host Routing

Each environment declares exact frontend and API hosts. Traefik routes the
frontend host to `novashop-frontend` and the API host to
`novashop-backend`. Avoid catch-all public routers.

Public Ingress resources should specify:

- `spec.ingressClassName: traefik`;
- exact `rules[].host` values;
- the `websecure` router entrypoint;
- `spec.tls[].hosts` and a cert-manager-managed TLS Secret;
- named Service ports;
- reviewed Middleware references.

Examples are available under
[`kubernetes/ingress/examples`](../../kubernetes/ingress/examples/).
The Ubuntu k3s GitOps overlay reconciles these resources. The Docker Desktop
overlay does not consume them.

## TLS

Traefik terminates TLS at the origin. The certificate Secret must:

- use type `kubernetes.io/tls`;
- contain `tls.crt` with the leaf certificate followed by intermediates;
- contain an unencrypted private key in `tls.key`;
- match every frontend and API hostname listed in the Ingress;
- be created outside Git and protected by Kubernetes RBAC.

Cloudflare should use Full (strict) mode after the origin certificate is valid.
Never select Flexible mode to compensate for missing origin TLS.

## HTTP-to-HTTPS Redirect

Use one of these reviewed approaches:

1. a Traefik `RedirectScheme` Middleware attached to HTTP Ingress routers; or
2. a global `web` entrypoint redirect configured in Traefik static settings.

A Middleware is explicit per namespace and minimizes cluster-wide impact. A
global redirect is simpler but affects every HTTP router. Keep TCP 80 available
if the selected ACME challenge requires it.

When Traefik is behind Cloudflare, forwarded headers influence scheme
detection. Trust forwarding headers only from the known last-hop proxy ranges;
do not trust arbitrary Internet clients.

## Middleware Policy

Recommended Middleware chain:

```text
HTTP router
  -> redirect-to-https

HTTPS router
  -> security-headers
  -> compression
  -> optional rate-limit
  -> Kubernetes Service
```

### Security Headers

Introduce headers in a controlled order:

- `Strict-Transport-Security` only after HTTPS is stable;
- `X-Content-Type-Options: nosniff`;
- `X-Frame-Options: DENY` unless framing is required;
- `Referrer-Policy: strict-origin-when-cross-origin`;
- a tested Content Security Policy in a later application-aware change.

Middleware headers overwrite response headers with the same name. Assign clear
ownership to avoid conflicting application and proxy policies.

### Compression

Traefik compression can reduce eligible response sizes when clients advertise
a supported encoding. Do not recompress already encoded responses. Validate
CPU impact and exclude content types that should not be compressed.

### Rate Limiting

Use Cloudflare for Internet-scale edge controls and Traefik for origin
protection. Establish separate policies for frontend pages and API endpoints.
Account for trusted-proxy configuration before deriving limits from client
addresses.

## Validation

```bash
kubectl get ingress --all-namespaces
kubectl get middleware.traefik.io --all-namespaces
kubectl --namespace kube-system logs deployment/traefik --tail=100

curl --head http://novashop.smartdev.vn
curl --head https://novashop.smartdev.vn
curl --silent --show-error https://api.novashop.smartdev.vn/health
```

Expected behavior:

- HTTP returns a redirect to the same HTTPS hostname;
- HTTPS presents a valid certificate and returns HTTP 200;
- frontend and API hosts route to different Services;
- responses include the approved security headers.

## cert-manager Integration

cert-manager issues and renews the environment certificates through ACME
HTTP-01. It owns only certificate lifecycle; Traefik remains the Ingress
controller and Argo CD remains the desired-state reconciler. See the
[cert-manager manifests](../../kubernetes/cert-manager/README.md).

## References

- [Traefik Kubernetes Ingress provider](https://doc.traefik.io/traefik/providers/kubernetes-ingress/)
- [Traefik RedirectScheme Middleware](https://doc.traefik.io/traefik/reference/routing-configuration/http/middlewares/redirectscheme/)
- [Traefik Headers Middleware](https://doc.traefik.io/traefik/reference/routing-configuration/http/middlewares/headers/)
- [Traefik Compress Middleware](https://doc.traefik.io/traefik/reference/routing-configuration/http/middlewares/compress/)
