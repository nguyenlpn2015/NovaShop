# Sprint 5.0 Validation Checklist

Evidence that each guardrail is enforced rather than described. Every item is a
command whose result can be shown, not a statement to be trusted.

Set the repository paths once:

```bash
export NOVASHOP_DIR="${PWD}"
export GITOPS_DIR='../NovaShop-GitOps'
```

## A. GitOps Safety

- [ ] The full gate passes for the current desired state.

  ```bash
  bash scripts/validate-platform.sh --gitops-dir "${GITOPS_DIR}"
  ```

  Expect `RESULT: PASS`.

- [ ] Revision durability is enforced independently.

  ```bash
  bash scripts/validate-gitops-revisions.sh --gitops-dir "${GITOPS_DIR}"
  ```

- [ ] The durability rule actually fails a non-durable pin. Introduce a pin that
      is not on `main` in a scratch copy and confirm the gate rejects it.

  ```bash
  cp -r "${GITOPS_DIR}" /tmp/gitops-negative
  sed -i 's/targetRevision: [0-9a-f]\{40\}/targetRevision: 0000000000000000000000000000000000000000/' \
    /tmp/gitops-negative/clusters/base/novashop-applicationset.yaml
  bash scripts/validate-gitops-revisions.sh --gitops-dir /tmp/gitops-negative \
    && echo 'UNEXPECTED PASS' || echo 'correctly rejected'
  rm -rf /tmp/gitops-negative
  ```

  A guardrail that has never failed has not been tested.

- [ ] Every cluster overlay and phase builds.

  ```bash
  for path in in-cluster ubuntu-k3s; do
    kubectl kustomize "${GITOPS_DIR}/clusters/${path}" >/dev/null && echo "ok ${path}"
  done
  for path in "${GITOPS_DIR}"/clusters/ubuntu-k3s/phases/*/; do
    kubectl kustomize "${path}" >/dev/null && echo "ok $(basename "${path}")"
  done
  ```

- [ ] YAML lint covers tracked documents and excludes vendored trees.

  ```bash
  git ls-files -- '*.yaml' '*.yml' | grep -c .
  ```

- [ ] Schema validation covers CRDs, not only core Kubernetes types.
      Confirm the summary reports Argo CD, cert-manager, and Traefik resources
      as valid rather than skipped.

- [ ] Runtime declarations agree across the image, CI, and the manifest.

  ```bash
  bash scripts/validate-platform.sh --scope application --skip-lint
  ```

  Expect `Node.js major version is consistent` and
  `Python minor version is consistent`.

- [ ] The alignment check rejects a one-sided runtime bump.

  ```bash
  sed -i 's/^FROM node:22\.19-alpine/FROM node:26.4-alpine/' frontend/Dockerfile
  bash scripts/validate-platform.sh --scope application --skip-lint \
    && echo 'UNEXPECTED PASS' || echo 'correctly rejected'
  git checkout -- frontend/Dockerfile
  ```

- [ ] Both default branches are protected.

  ```bash
  gh api repos/nguyenlpn2015/NovaShop/rulesets --jq '.[] | "\(.name) \(.enforcement)"'
  gh api repos/nguyenlpn2015/NovaShop-GitOps/rulesets --jq '.[] | "\(.name) \(.enforcement)"'
  ```

- [ ] Required status checks are real. The apply script must report every context
      as observed before it is run with `--apply`.

  ```bash
  bash scripts/apply-branch-protection.sh \
    --repo nguyenlpn2015/NovaShop \
    --ruleset .github/rulesets/novashop-main.json
  ```

- [ ] A direct push to a protected branch is rejected.

  ```bash
  git push origin HEAD:main --dry-run
  ```

- [ ] Secret scanning and push protection are enabled.

  ```bash
  gh api repos/nguyenlpn2015/NovaShop \
    --jq '.security_and_analysis.secret_scanning.status,
          .security_and_analysis.secret_scanning_push_protection.status'
  ```

## B. Release Safety

- [ ] `ci.yml` does not run on `main`, so validation on `main` belongs to the
      release graph and cannot race it.

  ```bash
  grep -A6 '^on:' .github/workflows/ci.yml
  ```

- [ ] `release.yml` declares validation as a dependency and publishes nothing
      before it.

  ```bash
  grep -nE 'needs:|uses:|push:|load:|imagetools' .github/workflows/release.yml
  ```

- [ ] The image is scanned before any push. Confirm the `Scan built image` step
      precedes `Publish immutable commit tag` in the job log.

- [ ] `latest` is promoted only after both components publish. Confirm the
      `promote` job declares `needs: publish` and that a failed component
      prevents it from running.

- [ ] `latest` and the commit tag reference the same digest after a release.

  ```bash
  for component in backend frontend; do
    image="ghcr.io/nguyenlpn2015/novashop-${component}"
    docker buildx imagetools inspect "${image}:latest" | head -3
  done
  ```

- [ ] No desired state references a mutable tag.

  ```bash
  grep -rn 'tag:' "${GITOPS_DIR}/apps/novashop/values/" | grep -v ':[[:space:]]*"[0-9a-f]\{40\}"'
  ```

  Expect no output.

## C. Bootstrap Reliability

- [ ] The Argo CD manifest digest is pinned and verified.

  ```bash
  grep -v '^#' argocd/install-manifest.sha256
  curl --fail --silent --location \
    "https://raw.githubusercontent.com/argoproj/argo-cd/v3.4.4/manifests/install.yaml" \
    | sha256sum
  ```

  The two digests must match.

- [ ] A tampered digest is rejected. Temporarily alter the pinned value and
      confirm `scripts/install-argocd.sh` refuses to apply.

- [ ] Bootstrap is idempotent. Run it twice on a healthy node; the second run
      must succeed and change nothing.

  ```bash
  bash scripts/bootstrap.sh && bash scripts/bootstrap.sh
  ```

- [ ] A phase disagreement is refused.

  ```bash
  EXPECTED_EDGE_SOURCE_PATH=kubernetes/ingress/http bash scripts/bootstrap.sh \
    && echo 'UNEXPECTED PASS' || echo 'correctly refused'
  ```

- [ ] Traefik entrypoints are asserted.

  ```bash
  kubectl --namespace kube-system get service traefik \
    --output=jsonpath='{range .spec.ports[*]}{.name}{"\n"}{end}'
  ```

  Expect `web` and `websecure`.

- [ ] An incomplete runtime Secret is detected.

  ```bash
  kubectl create secret generic novashop-development-secrets \
    --namespace novashop-development \
    --from-literal=DATABASE_URL=placeholder --dry-run=client -o yaml \
    | kubectl apply -f -
  bash scripts/bootstrap.sh && echo 'UNEXPECTED PASS' || echo 'correctly refused'
  ```

  Restore the correct Secret afterwards.

- [ ] A rerun does not perform a system upgrade unless requested.

  ```bash
  grep -n 'ENABLE_SYSTEM_UPGRADE' scripts/linux/bootstrap.sh
  ```

## D. Recovery

- [ ] A backup captures certificate material and an inventory.

  ```bash
  bash scripts/backup-platform-state.sh --output-dir /tmp/novashop-state
  ls -l /tmp/novashop-state
  ```

  Expect three `tls-*.json` files, at least one `acme-*.json`, and
  `platform-state.txt`.

- [ ] Exported Secrets carry no cluster identity. An `ownerReferences` entry
      would make the garbage collector delete the restored Secret immediately.

  ```bash
  jq '.metadata | keys' /tmp/novashop-state/tls-production.json
  ```

  Expect no `uid`, `resourceVersion`, or `ownerReferences`.

- [ ] Exported files are not world readable.

  ```bash
  stat --format='%a %n' /tmp/novashop-state/*
  ```

  Expect `600` for every file.

- [ ] Recovery refuses to start with unmet preconditions.

  ```bash
  bash scripts/linux/recover.sh && echo 'UNEXPECTED PASS' || echo 'correctly refused'
  ```

- [ ] Recovery restores certificates before cert-manager reconciles. Confirm the
      log order: `Restoring certificate material` precedes the bootstrap output.

- [ ] After recovery, certificates were adopted rather than reissued.

  ```bash
  kubectl get certificate --all-namespaces \
    --output=custom-columns='NS:.metadata.namespace,NAME:.metadata.name,READY:.status.conditions[0].status,RENEWAL:.status.renewalTime'
  ```

  The expiry must match `platform-state.txt` from the backup.

- [ ] Teardown refuses to destroy TLS Secrets without acknowledgement.

  ```bash
  bash scripts/cleanup.sh --confirm && echo 'UNEXPECTED PASS' || echo 'correctly refused'
  ```

## Rollback

- [ ] The baseline phase builds and renders.

  ```bash
  kubectl kustomize "${GITOPS_DIR}/clusters/ubuntu-k3s/phases/tls-baseline" >/dev/null
  ```

- [ ] Baseline manifests keep the TLS Secret reference and drop the redirect.

  ```bash
  grep -L 'novashop-redirect' kubernetes/ingress/baseline/*.yaml
  grep -l 'secretName: novashop-.*-tls' kubernetes/ingress/baseline/*.yaml
  ```

- [ ] Baseline advertises `max-age=0` so browsers release the HSTS pin.

  ```bash
  grep -n 'Strict-Transport-Security' kubernetes/ingress/baseline/production.yaml
  ```

- [ ] After a rollback to baseline, no certificate was pruned.

  ```bash
  kubectl get certificate --all-namespaces
  curl --silent --head https://novashop.smartdev.vn/ | grep -i strict-transport
  ```

  Expect three certificates present and `max-age=0`.

## Scope

- [ ] No observability component was introduced by this sprint.

  ```bash
  { git diff --name-only origin/main...HEAD; \
    git ls-files --others --exclude-standard; } \
    | sort --unique \
    | grep -E '\.(ya?ml|sh|json)$' \
    | while read -r file; do
        [ -f "${file}" ] \
          && grep -HniE '\b(prometheus|grafana|loki|tempo|opentelemetry|otel)\b' "${file}"
      done
  ```

  Expect no output. The match must be word-bounded and scoped to the changed
  files: an unbounded search reports `TEMPORARY_DIRECTORY` for `tempo` and the
  pre-existing cert-manager value below, which makes the check useless.

  One pre-existing reference is expected and is not in scope for Sprint 5.0:
  `kubernetes/cert-manager/helm-values.yaml` sets `prometheus.enabled: true`,
  which only exposes the cert-manager metrics port. It creates no
  `ServiceMonitor` and therefore depends on no Prometheus Operator CRD. Sprint
  5.1 decides what scrapes it.
