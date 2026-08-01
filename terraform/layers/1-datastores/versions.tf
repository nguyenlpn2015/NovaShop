# Version pins for the datastore layer.
#
# cyrilgdn/postgresql is the reason this layer is worth having. It models roles, databases,
# and grants as real resources with real state, so least privilege becomes desired state
# with drift detection rather than a SQL snippet someone ran once and a sentence in a
# document.
#
# There is no comparable Redis provider. Redis configuration is handled the same way as the
# node layer: rendered from a template, applied by the existing idempotent script, with the
# template hash as the trigger.

terraform {
  required_version = "~> 1.9"

  required_providers {
    postgresql = {
      source  = "cyrilgdn/postgresql"
      version = "~> 1.25"
    }
  }
}
