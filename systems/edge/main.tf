locals {
  network_policy = jsondecode(file("${path.module}/../../network-policy.json"))
}

data "incus_network" "private" {
  name    = "gardenbr0"
  project = "default"
  remote  = var.incus_remote
}
variable "image_directory" {
  description = "Absolute immutable Nix store directory produced by this system's seed-image build."
  type        = string

  validation {
    condition = (
      startswith(var.image_directory, "/nix/store/") &&
      fileexists("${var.image_directory}/metadata.tar.xz") &&
      fileexists("${var.image_directory}/rootfs.tar.xz") &&
      try(trimspace(file("${var.image_directory}/garden-system")) == "edge", false)
    )
    error_message = "Build this system's seed-image and provide its immutable /nix/store directory."
  }
}

resource "incus_image" "seed" {
  project = local.target.project
  remote  = var.incus_remote
  source_file = {
    metadata_path = "${var.image_directory}/metadata.tar.xz"
    data_path     = "${var.image_directory}/rootfs.tar.xz"
  }
}
variable "edge_lan_parent" {
  description = "Existing IncusOS LAN bridge; configured in local inputs."
  type        = string
  default     = null
}

variable "edge_lan_mac" {
  description = "Persistent locally administered MAC for the new LAN DHCP reservation."
  type        = string
  default     = null

  validation {
    condition = (
      var.edge_lan_parent == null ||
      can(regex("^02(:[0-9a-f]{2}){5}$", var.edge_lan_mac))
    )
    error_message = "Supply a locally administered MAC starting with 02."
  }
}

resource "incus_storage_volume" "caddy" {
  name    = "garden-caddy-state"
  pool    = data.incus_storage_pool.root.name
  project = "default"
  remote  = var.incus_remote

  config = {
    "initial.mode" = "0700"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "incus_instance" "edge" {
  lifecycle {
    precondition {
      condition     = var.edge_lan_parent != null && var.edge_lan_mac != null
      error_message = "Ingress requires an inspected IncusOS instances bridge and persistent LAN MAC."
    }
  }

  name        = local.target.instance
  description = "Digital Garden NixOS edge; private bootstrap"
  type        = "container"
  image       = incus_image.seed.fingerprint
  project     = "default"
  remote      = var.incus_remote
  profiles    = []
  running     = true

  config = {
    "boot.autostart"        = "true"
    "limits.cpu"            = "2"
    "limits.memory"         = "1GiB"
    "security.privileged"   = "false"
    "security.nesting"      = "true"
    "user.access_interface" = "eth0"
    "user.garden.system"    = local.target.system
  }

  device {
    name = "root"
    type = "disk"
    properties = {
      path = "/"
      pool = data.incus_storage_pool.root.name
      size = "8GiB"
    }
  }

  device {
    name = "eth0"
    type = "nic"
    properties = merge({
      network = data.incus_network.private.name
      name    = "eth0"
      }, local.network_policy.edgeBackendIPv4 == null ? {} : {
      "ipv4.address" = local.network_policy.edgeBackendIPv4
    })
  }

  device {
    name = "caddy-state"
    type = "disk"
    properties = {
      path   = "/var/lib/caddy"
      pool   = incus_storage_volume.caddy.pool
      source = incus_storage_volume.caddy.name
    }
  }

  dynamic "device" {
    for_each = [var.edge_lan_parent]
    content {
      name = "eth1"
      type = "nic"
      properties = {
        name    = "eth1"
        nictype = "bridged"
        parent  = device.value
        hwaddr  = var.edge_lan_mac
      }
    }
  }

  wait_for {
    type = "ipv4"
    nic  = "eth0"
  }
}

output "edge_ipv4" {
  value = incus_instance.edge.ipv4_address
}
