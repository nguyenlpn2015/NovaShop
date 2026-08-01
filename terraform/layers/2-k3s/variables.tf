# Input interface for the k3s layer.

variable "node_host" {
  description = "Address Terraform reaches the node on over SSH."
  type        = string
}

variable "node_user" {
  description = "SSH user with sudo on the node."
  type        = string
}

variable "ssh_private_key" {
  description = "SSH private key for node_user. Supply through TF_VAR_ssh_private_key."
  type        = string
  sensitive   = true
}

variable "k3s_version" {
  description = "k3s version to install. Changing this is a control-plane restart on a single node."
  type        = string
  default     = "v1.33.13+k3s1"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+\\+k3s[0-9]+$", var.k3s_version))
    error_message = "Must look like v1.33.13+k3s1."
  }
}

variable "k3s_server_args" {
  description = <<-EOT
    Arguments passed to the k3s server.

    The two bind-address arguments are what make the scheduler and controller-manager
    scrapable. They were an outstanding item precisely because changing them requires a
    restart, and a restart on a single node is a control-plane outage that has to be
    scheduled. Expressing them here turns that from a remembered task into a declarative
    change with a visible plan.
  EOT
  type        = list(string)
  default = [
    "--kube-scheduler-arg=bind-address=0.0.0.0",
    "--kube-controller-manager-arg=bind-address=0.0.0.0",
  ]
}

variable "disable_components" {
  description = <<-EOT
    Bundled components to disable.

    Empty on purpose. Traefik and the local-path provisioner ship with k3s and are kept —
    see ADR 007. Disabling Traefik would mean installing an ingress controller to replace a
    working one, and the edge has to serve plain HTTP before any certificate exists for
    HTTP-01 to succeed at all.
  EOT
  type        = list(string)
  default     = []
}

variable "kubeconfig_mode" {
  description = "File mode for /etc/rancher/k3s/k3s.yaml. 0600 keeps the admin kubeconfig root-only."
  type        = string
  default     = "0600"

  validation {
    condition     = can(regex("^0[0-7]{3}$", var.kubeconfig_mode))
    error_message = "Must be a four-digit octal mode such as 0600."
  }
}
