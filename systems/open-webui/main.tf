# Retirement root: retain these resource addresses and protected volumes.
# A whole plan removes the former instance and seed image; see the handbook.
resource "incus_storage_volume" "webui" {
  name    = "garden-open-webui-state"
  pool    = data.incus_storage_pool.root.name
  project = "ai"
  remote  = var.incus_remote
  config  = { "initial.mode" = "0700" }

  lifecycle {
    prevent_destroy = true
  }
}

resource "incus_storage_volume" "webui_secrets" {
  name    = "garden-open-webui-secrets"
  pool    = data.incus_storage_pool.root.name
  project = "ai"
  remote  = var.incus_remote
  config  = { "initial.mode" = "0700" }

  lifecycle {
    prevent_destroy = true
  }
}
