# Shared ingress/identity and bridge networks remain in the built-in default project.
# Create application projects at stage 1 so their persistent volumes exist before guests.
resource "incus_project" "ai" {
  name        = "ai"
  description = "Digital Garden user-facing AI applications"
  remote      = var.incus_remote

  config = {
    "features.images"          = "true"
    "features.profiles"        = "true"
    "features.storage.volumes" = "true"
    "features.storage.buckets" = "true"
    "features.networks"        = "false"
    "features.networks.zones"  = "false"
  }
}

resource "incus_project" "inference" {
  name        = "inference"
  description = "Digital Garden GPU inference and model storage"
  remote      = var.incus_remote

  config = {
    "features.images"          = "true"
    "features.profiles"        = "true"
    "features.storage.volumes" = "true"
    "features.storage.buckets" = "true"
    "features.networks"        = "false"
    "features.networks.zones"  = "false"
  }
}
