# Layer 3 — GitHub

Repository settings, branch protection rulesets, and Dependabot configuration for both
`NovaShop` and `NovaShop-GitOps`.

> **Phase 1: foundation only.** No resources are declared. `terraform plan` produces an
> empty plan and evaluates the outputs from variables alone, which is what makes the
> intended protection reviewable before anything is managed.

## What this layer will manage

| Resource | Replaces |
|---|---|
| `github_repository` | Settings changed by hand in the web UI |
| `github_repository_ruleset` | `scripts/apply-branch-protection.sh` + `.github/rulesets/*.json` |
| `github_repository_dependabot_security_updates` | Repository setting |

`scripts/apply-branch-protection.sh` stays until this layer has imported the rulesets and
produced an empty plan. Two mechanisms writing the same ruleset is the same double-ownership
mistake as Terraform fighting Argo CD, on a smaller scale.

## The hard part is check names

GitHub matches required checks by the name it *reports*, which is the rendered job name —
not the workflow file name, and not the job key. A required check whose name never appears
blocks every merge while waiting for something that will never arrive.

Two known traps, both already handled by the script this layer replaces:

**Checks from `pull_request`-only workflows never appear on the default branch.** Discovery
has to look at pull-request head commits as well, or the GitOps repository — whose
validation workflow only runs on pull requests — returns nothing.

**`jq` on Windows emits CRLF while `gh api` emits LF.** Without stripping `\r`, every
required check compares unequal and reports as "never reported". This cost a full debugging
session; it is not hypothetical.

The `required_check_names` output exists so the intent can be diffed against reality:

```sh
terraform output -json required_check_names
gh api repos/OWNER/REPO/commits/main/check-runs --jq '.check_runs[].name' | sort -u
```

## Configuration

```sh
export TF_VAR_github_token=...        # administration:write on both repositories
cp ../../examples/3-github.tfvars.example terraform.tfvars

cp ../../examples/backend-local-override.tf.example backend_override.tf
terraform init
terraform plan
```

## `enforce_admins` defaults to false

A rule an administrator cannot bypass is correct with a team and wrong with one operator on
a single-node cluster: during an incident it converts an outage into a longer outage. This
is a deliberate trade and it is the first thing to change if this platform ever gains a
second engineer.

## Import, not create

Both repositories exist. Later phases land `import` blocks and the acceptance gate is a
**completely empty plan**. If the plan wants to change something after import, the
configuration is wrong — applying it would edit reality to match a mistaken description.

```hcl
import {
  to = github_repository.this["NovaShop"]
  id = "NovaShop"
}
```
