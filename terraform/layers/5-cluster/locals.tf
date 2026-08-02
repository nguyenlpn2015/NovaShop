# Derived values and prerequisite assertions for the cluster layer.

locals {
  managed_by = "terraform"

  node_names = sort([for n in data.kubernetes_nodes.all.nodes : n.metadata[0].name])
  node_count = length(data.kubernetes_nodes.all.nodes)

  # kubeletVersion looks like v1.33.13+k3s1. The minor is what determines whether the
  # platform's manifests render, so it is extracted rather than string-compared.
  kubelet_versions = sort(distinct([
    for n in data.kubernetes_nodes.all.nodes : n.status[0].node_info[0].kubelet_version
  ]))

  kubernetes_minor = tonumber(
    regex("^v[0-9]+\\.([0-9]+)\\.", local.kubelet_versions[0])[0]
  )

  # Pod Security enforcement actually in force, per tracked namespace.
  observed_enforce = {
    for name, ns in data.kubernetes_namespace_v1.tracked :
    name => lookup(ns.metadata[0].labels, "pod-security.kubernetes.io/enforce", "<unset>")
  }

  # Namespaces whose enforcement level differs from what this layer expects. A drift here is
  # a security posture change nobody declared.
  pod_security_drift = {
    for name, expected in var.argocd_tracked_namespaces :
    name => {
      expected = expected.enforce
      observed = local.observed_enforce[name]
    }
    if local.observed_enforce[name] != expected.enforce
  }

  # Rendered kubectl invocation per required secret. This is what makes the contract
  # reproducible: an engineer rebuilding the platform gets the exact commands rather than
  # having to reconstruct key names from chart values.
  secret_commands = {
    for name, spec in var.required_secrets :
    name => join(" ", concat(
      ["kubectl -n ${spec.namespace} create secret generic ${name}"],
      [for k in spec.keys : "--from-literal=${k}=REPLACE_ME"],
    ))
  }

  # One command that reports which required secrets are missing, without printing a value.
  secret_verification_command = join(" ", [
    "for s in ${join(" ", keys(var.required_secrets))};",
    "do kubectl -n observability get secret \"$s\" >/dev/null 2>&1",
    "&& echo \"present $s\" || echo \"MISSING $s\"; done",
  ])
}

# ---------------------------------------------------------------------------
# Prerequisite assertions.
#
# check blocks report at plan time and do not block apply, which is the correct severity:
# these describe the platform's assumptions, and a violated assumption is something an
# operator must see rather than something Terraform should refuse to proceed past.
# ---------------------------------------------------------------------------

# Must come first. A StorageClass that does not exist returns an empty object rather than
# failing the data source, so without this the two checks below fire with messages that
# describe the wrong problem — "is not the default" when the truth is "is not there".
check "storage_class_exists" {
  assert {
    # coalesce, not length(): a missing StorageClass returns null for this attribute, and
    # length(null) raises rather than evaluating to false — which would replace the message
    # below with a Terraform internal error.
    condition     = try(coalesce(data.kubernetes_storage_class_v1.primary.storage_provisioner, ""), "") != ""
    error_message = "StorageClass ${var.storage_class_name} does not exist. A missing StorageClass reads back as an empty object rather than an error, so the assertions below will also fail with misleading messages. Fix this one first."
  }
}

check "storage_class_is_the_default" {
  assert {
    condition = lookup(
      data.kubernetes_storage_class_v1.primary.metadata[0].annotations,
      "storageclass.kubernetes.io/is-default-class",
      "false",
    ) == "true"
    error_message = "${var.storage_class_name} is not the default StorageClass. A PersistentVolumeClaim without an explicit storageClassName would bind elsewhere, which is how a volume silently ends up on the wrong provisioner."
  }
}

check "storage_class_binds_late" {
  assert {
    condition     = data.kubernetes_storage_class_v1.primary.volume_binding_mode == "WaitForFirstConsumer"
    error_message = "${var.storage_class_name} should use WaitForFirstConsumer so a volume is provisioned where its pod is scheduled."
  }
}

check "node_count_matches_expectation" {
  assert {
    condition = local.node_count == var.expected_node_count
    error_message = format(
      "Expected %d node(s), found %d (%s). Every document in this repository states single-node behaviour: no rescheduling, node-local volumes, and recovery as a rehearsed procedure. A change here invalidates those claims.",
      var.expected_node_count, local.node_count, join(", ", local.node_names),
    )
  }
}

check "kubernetes_version_is_supported" {
  assert {
    condition = local.kubernetes_minor >= var.minimum_kubernetes_minor
    error_message = format(
      "Kubernetes minor %d is below the supported floor of %d. Observed: %s.",
      local.kubernetes_minor, var.minimum_kubernetes_minor, join(", ", local.kubelet_versions),
    )
  }
}

check "pod_security_posture_is_unchanged" {
  assert {
    condition = length(local.pod_security_drift) == 0
    error_message = format(
      "Pod Security enforcement differs from the declared posture: %s. observability is expected to be privileged because node-exporter needs host network and host mounts; everything else is expected to be restricted.",
      jsonencode(local.pod_security_drift),
    )
  }
}
