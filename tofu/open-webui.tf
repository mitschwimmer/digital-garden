# Reuse the immutable minimal seed; the deploy script sets the guest hostname.
resource "incus_storage_volume" "webui" {
  name    = "garden-open-webui-state"
  pool    = data.incus_storage_pool.root.name
  project = "default"
  remote  = var.incus_remote
  config  = { "initial.mode" = "0700" }

  lifecycle {
    prevent_destroy = true
  }
}

resource "incus_storage_volume" "webui_secrets" {
  name    = "garden-open-webui-secrets"
  pool    = data.incus_storage_pool.root.name
  project = "default"
  remote  = var.incus_remote
  config  = { "initial.mode" = "0700" }

  lifecycle {
    prevent_destroy = true
  }
}

resource "incus_instance" "webui" {
  name        = "open-webui"
  description = "Digital Garden private Open WebUI"
  type        = "container"
  image       = incus_image.edge.fingerprint
  project     = "default"
  remote      = var.incus_remote
  profiles    = []
  running     = true

  config = {
    "boot.autostart"        = "true"
    "limits.cpu"            = "2"
    "limits.memory"         = "4GiB"
    "security.privileged"   = "false"
    "security.nesting"      = "true"
    "user.access_interface" = "eth0"
  }

  device {
    name = "root"
    type = "disk"
    properties = {
      path = "/"
      pool = data.incus_storage_pool.root.name
      size = "24GiB"
    }
  }

  device {
    name = "eth0"
    type = "nic"
    properties = {
      network = incus_network.private.name
      name    = "eth0"
    }
  }

  device {
    name = "webui-state"
    type = "disk"
    properties = {
      path   = "/var/lib/open-webui"
      pool   = incus_storage_volume.webui.pool
      source = incus_storage_volume.webui.name
    }
  }

  device {
    name = "webui-secrets"
    type = "disk"
    properties = {
      path   = "/var/lib/garden-secrets"
      pool   = incus_storage_volume.webui_secrets.pool
      source = incus_storage_volume.webui_secrets.name
    }
  }

  wait_for {
    type = "ipv4"
    nic  = "eth0"
  }
}

output "open_webui_ipv4" {
  value = incus_instance.webui.ipv4_address
}
