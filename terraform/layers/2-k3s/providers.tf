# No provider configuration. The node is reached over SSH through provisioner connection
# blocks; see ../0-node/providers.tf.
#
# Note what is deliberately absent: no kubernetes provider and no helm provider. This layer
# installs k3s and stops. Everything inside the cluster belongs to Argo CD, and a
# kubernetes provider configured here would be the first step toward two controllers
# fighting over one object. See ../../README.md.
