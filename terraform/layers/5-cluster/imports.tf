# Import blocks.
#
# The Argo CD namespace already exists — the bootstrap script created it. Terraform adopts
# it rather than creating it, and the acceptance gate is a completely empty plan.
#
# Import blocks are used rather than the `terraform import` command because they are
# reviewable in a pull request and they appear in the plan. An import performed at a
# terminal leaves no trace anyone can review.
#
# If the plan is not empty after this, the configuration is wrong, not the cluster.
# Applying it would edit reality to match a mistaken description — most likely by stripping
# labels that are genuinely there.

import {
  to = kubernetes_namespace_v1.argocd
  id = "argocd"
}

# The read-only ClusterRole and its binding are new. They have no import block because
# there is nothing to adopt, which is also why this layer's first apply is not a no-op.
