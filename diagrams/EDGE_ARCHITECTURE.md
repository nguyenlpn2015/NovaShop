# NovaShop Edge Architecture

The request path is introduced in two stages. Phase 1 uses HTTP through
Traefik. Phase 2 adds the certificate path shown below only after a reviewed
GitOps activation:

```text
GitOps TLS phase (inactive by default)
        |
        v
cert-manager -> ACME ClusterIssuer -> Certificate -> TLS Secret
                                                    |
                                                    v
                                             Traefik websecure
```

```text
                                  Internet Users
                                        |
                                        | HTTP (Phase 1)
                                        | HTTPS (Phase 2)
                                        v
                              +--------------------+
                              | Cloudflare Edge    |
                              | DNS / Proxy / WAF  |
                              +---------+----------+
                                        |
                                        | Public DNS answer
                                        | and proxied HTTPS
                                        v
                              +--------------------+
                              | Public IPv4        |
                              +---------+----------+
                                        |
                                        v
                              +--------------------+
                              | FortiGate          |
                              | Firewall Policy    |
                              +---------+----------+
                                        |
                                        | VIP / destination NAT
                                        | 80  -> 10.10.1.45:80
                                        | 443 -> 10.10.1.45:443
                                        v
                         +-----------------------------+
                         | Ubuntu Server 22.04         |
                         | 10.10.1.45 / single-node k3s|
                         +--------------+--------------+
                                        |
                                        v
                              +--------------------+
                              | Traefik            |
                              | web / websecure    |
                              +---------+----------+
                                        |
                                        | Host and TLS routing
                                        v
                              +--------------------+
                              | Kubernetes Ingress |
                              +----+-----------+---+
                                   |           |
                      frontend host|           |API host
                                   v           |
                         +-------------+        |
                         | Frontend    |        |
                         | Service/Pods|        |
                         +------+------+        |
                                |               |
                                | API requests  |
                                v               v
                              +--------------------+
                              | Backend            |
                              | Service / Pods     |
                              +---------+----------+
                                        |
                            +-----------+-----------+
                            |                       |
                            v                       v
                    +---------------+       +---------------+
                    | PostgreSQL    |       | Redis         |
                    | 10.10.1.45    |       | 10.10.1.45    |
                    | private only  |       | private only  |
                    +---------------+       +---------------+
```

## Security Boundaries

- Cloudflare is the optional public reverse proxy and application security
  edge.
- FortiGate is the network-layer destination NAT and policy enforcement point.
- Traefik is the only public Kubernetes ingress path.
- PostgreSQL, Redis, SSH, Argo CD, and the Kubernetes API are not Internet
  services.
- Argo CD continues to reconcile application desired state from the separate
  GitOps repository; the edge extension does not change that delivery path.

## Host Routing

| Environment | Frontend | Backend |
|-------------|----------|---------|
| Development | `dev.novashop.smartdev.vn` | `api.dev.novashop.smartdev.vn` |
| Staging | `staging.novashop.smartdev.vn` | `api.staging.novashop.smartdev.vn` |
| Production | `novashop.smartdev.vn` | `api.novashop.smartdev.vn` |

See [Public Access Architecture](../docs/networking/public-access.md) for the
implementation and validation sequence.
