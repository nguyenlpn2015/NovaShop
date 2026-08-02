<!--
Keep this short. The sections exist because reviewers here have been burned by
their absence, not because a template ought to be long.

Delete any section that genuinely does not apply, and say why rather than
leaving it blank.
-->

## What this changes

<!-- The problem first, then the change. One or two paragraphs. -->

## Why this way

<!--
What you rejected, and why it lost. If this changes a component, a guardrail,
or a decision, add an ADR in adr/ and link it here.
-->

## Validation evidence

<!--
Paste the RESULT line, not a claim that you ran it. Any change to helm/,
kubernetes/, argocd/, terraform/, or .github/workflows/ needs at least the
platform gate.
-->

```
bash scripts/validate-platform.sh --gitops-dir ../NovaShop-GitOps
RESULT:
```

- [ ] Ran the gates affected by this change and pasted the output above
- [ ] Changes to `helm/`, `kubernetes/`, or `argocd/` render and validate
- [ ] Terraform changes are `fmt` clean and `validate` cleanly
- [ ] Documentation updated in the same pull request, and links resolve

## Risk and rollback

<!--
What breaks if this is wrong, how you would notice, and how you would undo it.

"None" is an acceptable answer for a documentation-only change. It is rarely
the right answer for anything that reaches the cluster — this platform runs on
one node, and Argo CD prunes what leaves Git.
-->

## Anything a reviewer should not assume

<!--
State what you did NOT verify. An untested path named here costs a reviewer a
question; the same path unnamed costs an incident.

Examples that have mattered here: a fix verified by rendering but not on the
cluster; a script exercised only up to its preconditions; a NetworkPolicy
change not re-tested after a rule-propagation delay.
-->

<!--
Before requesting review:
  - Is the base branch `main`? A pull request stacked on another branch merges
    into that branch, not into main. That mistake orphaned 1,091 lines here.
  - If you renamed a job in .github/workflows/validation.yml, you changed a
    required check context. Update .github/rulesets/ in THIS pull request or
    every later pull request becomes unmergeable.
-->
