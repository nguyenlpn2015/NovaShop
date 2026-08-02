# tflint configuration.
#
# The terraform ruleset is bundled with tflint, so it is declared without a source or a
# version. That is deliberate: an external plugin needs `tflint --init`, which needs network
# access to GitHub on every CI run and on every workstation. The bundled ruleset covers what
# matters here — declarations nothing uses, which is exactly the drift a layer accumulates
# while its resources are still being written.
#
# The tflint binary itself is pinned in .github/workflows/validation.yml, so a local run and
# a CI run report the same thing as long as both use that version.

config {
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}
