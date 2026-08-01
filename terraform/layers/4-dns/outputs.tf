# Outputs for the DNS layer.
#
# These exist to be asserted against, not read. scripts/linux/verify.sh can consume them to
# prove that what Terraform intends and what the internet resolves are the same thing.

output "fqdns" {
  description = "Fully qualified names this layer manages."
  value       = sort(values(local.fqdns))
}

output "acme_reachable_fqdns" {
  description = <<-EOT
    Names that must answer on port 80 for HTTP-01 validation to succeed.

    The most useful output in this layer. It turns an implicit chain — public DNS resolves
    here, port 80 reaches this node, Traefik routes /.well-known/acme-challenge/, the
    certificate renews — into a machine-readable list.

    A 404 from the challenge path is the healthy answer: it proves the request arrived and
    was routed. A timeout means DNS or DNAT.

      for n in $(terraform output -json acme_reachable_fqdns | jq -r '.[]'); do
        curl -so /dev/null -w "%%{http_code} $n\n" "http://$n/.well-known/acme-challenge/probe"
      done
  EOT
  value       = local.acme_required_fqdns
}

output "record_set" {
  description = "Resolved record definitions, for review in a pull request before any resource exists."
  value       = local.record_set
}

output "target_address" {
  description = "Address every managed record points at."
  value       = var.site_public_ip
}

output "proxied" {
  description = "Cloudflare proxy state. Must be false while ACME validation is HTTP-01."
  value       = var.proxied
}
