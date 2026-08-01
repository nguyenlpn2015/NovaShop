# Input interface for the node layer.

variable "node_host" {
  description = "Address Terraform reaches the node on over SSH."
  type        = string

  validation {
    condition     = length(trimspace(var.node_host)) > 0
    error_message = "node_host must not be empty."
  }
}

variable "node_user" {
  description = "SSH user with sudo on the node."
  type        = string
}

variable "ssh_private_key" {
  description = "SSH private key for node_user. Supply through TF_VAR_ssh_private_key; never a file the repository tracks."
  type        = string
  sensitive   = true
}

variable "node_ip" {
  description = "LAN address of the node. Pods reach the host datastores here, so it is not interchangeable with localhost."
  type        = string

  validation {
    condition     = can(cidrhost("${var.node_ip}/32", 0))
    error_message = "Must be a valid IPv4 address."
  }
}

variable "pod_cidr" {
  description = "Pod network CIDR. Appears in pg_hba.conf and in the Redis bind configuration."
  type        = string
  default     = "10.42.0.0/16"

  validation {
    condition     = can(cidrhost(var.pod_cidr, 0))
    error_message = "Must be a valid CIDR block."
  }
}

# This is the variable that must never acquire a plausible default.
#
# The operator workstation on this platform is 192.168.3.2, which is not inside
# 10.10.0.0/16. A firewall rule written for the node's own subnet would lock the operator
# out of the only node in the platform, with no second machine to fix it from.
#
# configure-datastores.sh already refuses to enable UFW without this value. Modelling it as
# an optional variable with no default preserves that refusal in Terraform.
variable "management_cidr" {
  description = "Source network permitted to reach SSH. UFW stays disabled while this is null; a default here could lock the operator out of the only node."
  type        = string
  default     = null

  validation {
    condition     = var.management_cidr == null ? true : can(cidrhost(var.management_cidr, 0))
    error_message = "Must be a valid CIDR block, or null to leave UFW alone."
  }
}

variable "inotify_max_user_instances" {
  description = <<-EOT
    fs.inotify.max_user_instances.

    The kernel default of 128 was exhausted at 140 in use by config reloaders, log
    collectors, dashboard sidecars, and certificate watchers. A workload that cannot create
    a watcher does not fail — it keeps running with what it loaded at startup and silently
    stops noticing changes, which here means a renewed certificate or a synced manifest
    that never takes effect.
  EOT
  type        = number
  default     = 512

  validation {
    condition     = var.inotify_max_user_instances >= 256
    error_message = "Below 256 the observability stack exhausts the limit again; 128 is the default that caused the original incident."
  }
}

variable "inotify_max_user_watches" {
  description = "fs.inotify.max_user_watches."
  type        = number
  default     = 524288
}

variable "swap_enabled" {
  description = "Whether swap stays enabled. kubelet expects it off."
  type        = bool
  default     = false
}

variable "packages" {
  description = "Packages the platform requires on the node."
  type        = list(string)
  default = [
    "curl",
    "jq",
    "postgresql",
    "redis-server",
    "ufw",
  ]
}
