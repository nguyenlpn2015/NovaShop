# No provider configuration.
#
# This layer reaches the node over SSH through provisioner connection blocks rather than a
# provider. The file exists so that every layer has the same seven files and a reader does
# not have to wonder whether one is missing.
#
# SSH connection details are variables rather than hard-coded, and the private key is
# supplied through the environment.
