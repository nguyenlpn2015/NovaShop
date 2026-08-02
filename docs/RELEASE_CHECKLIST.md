# Release Checklist

Run before tagging any release. Every item is either a command whose output you paste, or a
question with a yes/no answer — nothing here is satisfied by "looks fine".

The items marked **⚠** exist because that exact step went wrong on a previous release.

## 1. The gates

```sh
bash scripts/validate-platform.sh          --gitops-dir ../NovaShop-GitOps   # 38 checks
bash scripts/validate-gitops-revisions.sh  --gitops-dir ../NovaShop-GitOps   # 30 checks
bash scripts/validate-observability.sh     --gitops-dir ../NovaShop-GitOps   # 25 checks

docker run --rm -v "$PWD:/repo" -w /repo hashicorp/terraform:1.9.8 \
  fmt -check -recursive terraform
```

- [ ] All three gates pass; paste each `RESULT` line into the release pull request
- [ ] Terraform is `fmt` clean
- [ ] CI is green on the commit being tagged — **the commit, not the branch**

## 2. The live platform

- [ ] `kubectl get applications -n argocd` — every Application Synced and Healthy
- [ ] Prometheus `/targets` — every target up, and the count matches what the README claims
- [ ] Prometheus `/alerts` — nothing firing or pending, or the exception is stated in the notes
- [ ] `kubectl get certificate -A` — all Ready, none inside the renewal window
- [ ] `curl -o /dev/null -w '%{http_code}'` returns 200 for production, staging, and development

## 3. Documentation truth

This is the section that has caught the most problems.

- [ ] Every number in `README.md` re-measured, not copied forward
- [ ] **⚠ Document counts updated.** Adding files makes them stale, and it has happened twice
- [ ] `docs/AUDIT.md` rescored, including anything that got worse
- [ ] `docs/ROADMAP.md` moves delivered work out of the pending sections
- [ ] `CHANGELOG.md` has an entry with the release date and a Known limitations section
- [ ] Link audit reports zero broken links across the repository
- [ ] **⚠** No document claims a capability that is documented rather than demonstrated

Link audit — there is no CI gate for this, so it must be run by hand:

```sh
python3 - <<'PY'
import re, os
bad = []
skip = {'node_modules', '.git', '__pycache__', '.next', 'venv'}
for dp, dn, fn in os.walk('.'):
    dn[:] = [d for d in dn if d not in skip]
    for f in (x for x in fn if x.endswith('.md')):
        p = os.path.join(dp, f)
        t = open(p, encoding='utf-8', errors='replace').read()
        for m in re.finditer(r'\[[^\]]*\]\(([^)\s]+)\)', t):
            tg = m.group(1)
            if tg.startswith(('http://', 'https://', '#', 'mailto:')):
                continue
            path = tg.split('#')[0]
            if path and not os.path.exists(os.path.normpath(os.path.join(dp, path))):
                bad.append(f"{p} -> {tg}")
print(f"broken: {len(bad)}")
for b in bad:
    print(" ", b)
PY
```

## 4. Security

- [ ] No secrets in the diff, and none in the history being published
- [ ] **⚠ Node credentials rotated** if any were shared during development
- [ ] Dependabot pull requests triaged — merged, or a decision recorded
- [ ] Trivy findings on the released images reviewed; anything unfixed is named in the notes
- [ ] Nothing newly exposed to the internet without an explicit decision

## 5. The tag

- [ ] Tag from `main`, after the release pull request has merged
- [ ] **⚠ Do not use `git tag -F` with a message containing markdown headings.** Git strips
      lines beginning with `#` unless you pass `--cleanup=verbatim`. This silently removed
      every heading from the v1.0.0 notes, including *Known limitations*

```sh
git checkout main && git pull
git tag -a vX.Y.Z -F release-notes.md --cleanup=verbatim
git push origin vX.Y.Z
```

## 6. The GitHub release

- [ ] **⚠ `--notes-from-tag` is incompatible with `--repo`.** The error is only visible if you
      are not truncating command output
- [ ] Notes lead with what the release *is*, then verified numbers, then **Known limitations**
- [ ] Limitations appear in the notes, the CHANGELOG, and the README — not one of the three
- [ ] Release marked latest, and the tag points at the intended commit

```sh
gh release create vX.Y.Z --title "NovaShop vX.Y.Z" --notes-file release-notes.md
```

If the notes need repair afterwards, `gh release edit vX.Y.Z --notes-file <file>` fixes the
release without force-updating a tag other people may already have fetched.

## 7. The repository as a landing page

Judged as a stranger arriving from a search result.

- [ ] Repository description and topics set, and they say what this is
- [ ] Badges render and point somewhere useful
- [ ] `README.md` answers *what is this* above the fold
- [ ] Quick start works from a clean clone — actually run it
- [ ] `CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md`, `LICENSE` present
- [ ] Issue templates and a pull request template exist, and CONTRIBUTING does not promise
      anything that is missing
- [ ] Private vulnerability reporting enabled in repository settings

## 8. Pull request hygiene

- [ ] **⚠ Every open pull request is based on `main`.** A stacked pull request merges into its
      stated base; if that base merges first, the stack lands nowhere. This orphaned 1,091
      lines in #51 with CI green throughout
- [ ] No branch contains work that never reached `main` — compare the branch list against the
      merged pull requests

## After the release

- [ ] Read the published release page as a stranger would
- [ ] Confirm the tag, the CHANGELOG entry, and the README all state the same version
- [ ] Open the follow-up issues for anything deferred, rather than leaving it in a document
