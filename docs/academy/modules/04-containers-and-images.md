# Module 4 — Containers and Images

*Part 2 · Packaging and delivery · Beginner to Intermediate*

Two Dockerfiles, forty-eight lines each. They contain a security lesson most container
tutorials never reach: **the vulnerabilities in your image are often not in your dependency
manifest.**

## 1. Learning Objectives

After this module you can:

- Explain what each stage of a multi-stage build contributes and why the runtime stage is small
- Say why the containers run as **numeric** uid 10001 rather than a named user
- Explain how CVEs appeared in a scan that were **not** in `package-lock.json`, and why deleting
  npm was the correct fix
- Describe why `readOnlyRootFilesystem: true` works for these images
- Explain how CI guarantees an unscanned image cannot reach the registry

## 2. Theory

**Multi-stage builds** let you compile in one image and ship in another. The build stage can
carry compilers, package managers, and source; the runtime stage carries only what runs.

**Why non-root matters.** A container process running as root is root **in the container's user
namespace**, which on a default cluster maps to real root on the host for anything that escapes.
Running as an unprivileged uid removes an entire class of escalation.

**Why *numeric* uid matters.** Kubernetes' `runAsNonRoot: true` must decide, before starting the
container, whether the user is root. If the image specifies `USER novashop` — a name — the
kubelet cannot resolve it without reading `/etc/passwd` inside the image, and the check can
fail. A numeric `USER 10001` is unambiguous.

**Scanning finds what is in the image, not what is in your lockfile.** Base images vendor their
own software. A Node base image ships npm, and npm ships its own dependency tree.

## 3. Repository Walkthrough

### `backend/Dockerfile`

```dockerfile
FROM python:3.12.13-slim-bookworm AS builder
COPY pyproject.toml ./
COPY app ./app
RUN pip wheel --wheel-dir /wheels .

FROM python:3.12.13-slim-bookworm AS runtime
RUN groupadd --system --gid 10001 novashop && ...
COPY --from=builder /wheels /wheels
RUN pip install --no-cache-dir /wheels/*
USER novashop
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--no-access-log"]
```

Four things worth noticing:

**The base image is pinned to a patch version**, `3.12.13-slim-bookworm`, not `3.12` or
`3-slim`. A floating tag means the image you scanned is not necessarily the image you ship.

**Wheels are built in one stage and installed in another**, so the compiler toolchain never
reaches the runtime image.

**`--no-access-log`.** Uvicorn's access log duplicates what Traefik already records, and every
duplicated log line is Loki storage spent twice.

**uid 10001 is created explicitly**, not inherited.

### `frontend/Dockerfile` — the interesting one

Three stages: `dependencies`, `builder`, `runtime`. Then this, verbatim from the file:

```dockerfile
# The standalone server starts with `node server.js`, so no package manager is
# needed at runtime. npm, corepack, and yarn each vendor their own dependency
# tree into the image, and those trees are the only source of the CRITICAL and
# HIGH findings this image reports. Removing them fixes the scan at its cause
# and drops a large amount of unused, network-capable tooling from a container
# that serves public traffic.
RUN rm -rf \
      /usr/local/lib/node_modules/npm \
      /usr/local/lib/node_modules/corepack \
      /opt/yarn-v1.22.22 \
      /usr/local/bin/npm \
      /usr/local/bin/npx \
      /usr/local/bin/corepack \
      /usr/local/bin/yarn \
      /usr/local/bin/yarnpkg
```

**Read that comment carefully — it is the module.** Trivy reported CRITICAL and HIGH findings in
`tar`, `sigstore`, `brace-expansion`, and `picomatch`. None of those appears in
`package-lock.json`. They were vendored inside npm, inside the Node base image.

Three responses were possible. Wait for a Node base image rebuild — passive, and the CVEs are in
npm rather than Node. Add ignore rules — makes the scan green while the code stays present.
**Delete the package managers** — fixes the cause, and a container serving public traffic has no
business carrying network-capable tooling it never runs.

### `npm ci --ignore-scripts`

In the `dependencies` stage. Lifecycle scripts in transitive dependencies are a supply-chain
execution vector; `--ignore-scripts` refuses to run them at build time.

### Where the security context lives

Not in the Dockerfile. See `helm/novashop/templates/backend-deployment.yaml`:

```yaml
securityContext:                 # pod
  runAsNonRoot: true
  runAsUser: 10001
  runAsGroup: 10001
  fsGroup: 10001
  seccompProfile: { type: RuntimeDefault }
```

```yaml
securityContext:                 # container
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
  capabilities: { drop: ["ALL"] }
```

The Dockerfile declares the user; the Deployment enforces the constraints. Both are needed —
Kubernetes cannot know an image is safe just because the image says so.

## 4. Architecture Explanation

See [CI/CD Flow](../../architecture/cicd-flow.md).

Images are tagged by the **full 40-character commit SHA**. That is what makes GitOps pinning
meaningful — `validate-gitops-revisions.sh` can query GHCR and prove the tag exists.

**What breaks elsewhere if this is wrong:**

| Image mistake | Symptom |
|---|---|
| Not non-root | Pod rejected by Pod Security Admission `restricted` |
| Writes to the root filesystem | `CrashLoopBackOff` under `readOnlyRootFilesystem` |
| Floating base tag | Scanned image differs from shipped image |
| Tag not a commit SHA | GitOps revision gate fails the pull request |

## 5. Hands-on Lab

### Part A — see the vulnerability that is not in your lockfile

```sh
cd frontend
grep -c 'sigstore\|brace-expansion' package-lock.json    # likely 0 for sigstore
```

Now scan an unmodified Node image:

```sh
docker run --rm aquasec/trivy:0.58.1 image \
  --severity HIGH,CRITICAL --quiet node:22.23.2-alpine | head -30
```

Findings will reference paths under `/usr/local/lib/node_modules/npm/`. **Those packages are not
your dependencies.** They arrived with the base image.

### Part B — build NovaShop's image and compare

```sh
docker build -t novashop-frontend:lab .
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy:0.58.1 image --severity HIGH,CRITICAL --quiet novashop-frontend:lab
```

### Part C — prove the runtime has no package manager

```sh
docker run --rm --entrypoint sh novashop-frontend:lab -c 'which npm npx yarn || echo "none present"'
docker run --rm --entrypoint id novashop-frontend:lab
```

### Part D — prove a read-only root filesystem is survivable

```sh
docker run --rm --read-only --user 1001 novashop-frontend:lab node -e 'console.log("ok")'
```

### Verification

```sh
docker run --rm --entrypoint sh novashop-frontend:lab -c \
  'test ! -e /usr/local/bin/npm && echo PASS || echo FAIL'
docker run --rm --entrypoint id -u novashop-frontend:lab | grep -qv '^0$' && echo "PASS non-root"
```

## 6. Exercises

**6.1** Add `RUN npm --version` to the runtime stage of `frontend/Dockerfile` and rebuild. It
fails. Explain in one sentence why that failure is *desirable*.

**6.2** `backend/Dockerfile` runs `pip install` in the runtime stage while `frontend/Dockerfile`
copies build output. Why the difference, and does the backend leak build tooling?

**6.3** Change the backend base to `python:3.12-slim-bookworm` (floating patch). Run
`bash scripts/validate-platform.sh --gitops-dir ../NovaShop-GitOps`. Does it fail? Should it?
Write two sentences on whether the gate should enforce patch pinning.

**6.4** Run the backend container with `--read-only` and no writable mount. Does it start? If
not, find the smallest `tmpfs` that makes it work, and explain why that is better than dropping
`readOnlyRootFilesystem`.

## 7. Challenge

The frontend Dockerfile deletes package managers by path — a list of eight hard-coded locations.
That list is **coupled to the base image layout**. A Node minor upgrade could move
`/opt/yarn-v1.22.22`, the `rm -rf` would silently remove nothing, and the CVEs would return
without any signal.

**Design a durable fix.** Consider: a distroless or `node:*-slim` base that never ships npm; a
build-time assertion that fails if `npm` still exists after the `rm`; a Trivy policy that fails
CI when specific package names reappear; or accepting the coupling and pinning the base image
tightly.

Write it as an ADR. The *Alternatives Considered* section is the deliverable — each option needs
a specific drawback, not a preference.

## 8. Quiz

1. Why numeric `USER 10001` rather than a username?
2. Where did the frontend's CRITICAL findings come from?
3. Why is deleting npm better than a Trivy ignore rule?
4. What does `npm ci --ignore-scripts` prevent?
5. Why is `--no-access-log` set on uvicorn?
6. **True or false:** `readOnlyRootFilesystem: true` in the Deployment makes the Dockerfile's
   `USER` line unnecessary.
7. Why is the base image pinned to a patch version?
8. At what point in CI are registry credentials acquired, and why does the ordering matter?

<details>
<summary>Answers</summary>

1. `runAsNonRoot: true` must determine before start whether the user is root. A name requires
   resolving `/etc/passwd` inside the image; a numeric uid is unambiguous.
2. From npm, corepack, and yarn — vendored inside the Node base image, not present in
   `package-lock.json`.
3. An ignore rule makes the scan green while the vulnerable code is still in a container serving
   public traffic. Deleting it removes the cause *and* a large amount of unused network-capable
   tooling.
4. Execution of lifecycle scripts from transitive dependencies at build time — a supply-chain
   execution vector.
5. It duplicates what Traefik already records, and every duplicated line is Loki storage spent
   twice.
6. **False.** They solve different problems: `USER` sets the identity, `readOnlyRootFilesystem`
   constrains what that identity can write. Pod Security Admission `restricted` requires both.
7. So the image you scanned is the image you ship. A floating tag can change between scan and
   deploy.
8. **After** Trivy passes. The build loads the image locally, Trivy scans, and only then does the
   workflow log in to GHCR. There is no path from a failing scan to a push because the
   credentials do not exist yet.

</details>

## 9. Troubleshooting

### Trivy reports CVEs you cannot find in your lockfile

**Symptom.** CRITICAL findings in `tar`, `sigstore`, `brace-expansion`. `grep` in
`package-lock.json` finds nothing.

**Why it is misleading.** You look for a dependency to bump and there is none. The natural next
step is an ignore rule — which hides the finding rather than removing the code.

**How it was found.** Reading the *paths* in the Trivy output rather than only the package
names. They were all under `/usr/local/lib/node_modules/npm/`.

### `fail-fast` hides which image is actually broken

**Symptom.** Three consecutive releases blocked; the run shows the frontend job red and the
backend job cancelled.

**Why it is misleading.** You cannot tell whether the backend was clean, so you cannot tell
whether fixing the frontend is sufficient.

**Fix.** `fail-fast: false` in the image matrix. Costs a few minutes; converts "something
failed" into "this failed and that did not".

### Pod rejected by Pod Security Admission

**Symptom.**

```
violates PodSecurity "restricted:latest": allowPrivilegeEscalation != false,
unrestricted capabilities, runAsNonRoot != true, seccompProfile
```

**Why it is worth knowing.** This is what a working admission control looks like. It happened to
this platform's own author when running a diagnostic pod — which is how PSA enforcement was
*proven* rather than assumed. Any debug pod you run in `novashop-*` needs a compliant
`securityContext`; there is a copy-paste example in
[`docs/security/network-policy.md`](../../security/network-policy.md).

## 10. Best Practices

| Practice | Where |
|---|---|
| Multi-stage build; no toolchain in runtime | Both Dockerfiles |
| Base image pinned to a patch version | `python:3.12.13-slim-bookworm`, `node:22.23.2-alpine` |
| Numeric non-root user | `USER novashop` (uid 10001), `USER nextjs` (uid 1001) |
| `--ignore-scripts` at install time | `frontend/Dockerfile` |
| Remove tooling the runtime never uses | The `rm -rf` block |
| Scan before push, credentials acquired after | `.github/workflows/release.yml` |
| Tag by commit SHA | Release workflow; enforced by the GitOps gate |

**Deliberately not done:** images are **scanned but not signed**. No cosign, no SLSA
provenance. [AUDIT.md](../../AUDIT.md) lists it as an open item. For a single-operator lab where
the registry and the CI are the same trust domain, signing adds ceremony without changing who
could publish — but that argument weakens the moment a second person has push access.

## 11. Interview Questions

- *Why remove npm from the frontend runtime image?* → [S15](../../interview/questions.md)
- *How do you guarantee an unscanned image never reaches the registry?* → [S10](../../interview/questions.md)
- *What does `fail-fast: false` solve here?* → [I19](../../interview/questions.md)
- *How are images tagged?* → [B17](../../interview/questions.md)

## 12. Further Reading

- [Docker multi-stage builds](https://docs.docker.com/build/building/multi-stage/)
- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/) — the `restricted` profile
- [ADR 008 — CI platform](../../../adr/008-ci-platform.md) — scan-before-push ordering
- [CI/CD Flow](../../architecture/cicd-flow.md)

---

**Next:** Module 5 — CI/CD with GitHub Actions *(specified, not yet written)*.
Or jump to [Module 10 — GitOps and Argo CD](10-gitops-and-argocd.md) ✅.
