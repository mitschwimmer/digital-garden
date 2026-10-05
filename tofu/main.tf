terraform {
  required_version = ">= 1.9.0, < 2.0.0"

  required_providers {
    incus = {
      source  = "lxc/incus"
      version = "= 1.2.0"
    }
  }
}

variable "incus_remote" {
  description = "Authenticated Incus client remote alias."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_.-]*$", var.incus_remote))
    error_message = "Supply an Incus client remote alias without a colon."
  }
}

variable "storage_pool" {
  description = "Existing storage pool for the disposable edge root volume."
  type        = string
}

variable "image_directory" {
  description = "Absolute immutable Nix store directory produced by the edge-image build."
  type        = string

  validation {
    condition = (
      startswith(var.image_directory, "/nix/store/") &&
      fileexists("${var.image_directory}/metadata.tar.xz") &&
      fileexists("${var.image_directory}/rootfs.tar.xz")
    )
    error_message = "Build edge-image and provide its immutable /nix/store directory."
  }
}

provider "incus" {
  default_remote = var.incus_remote

  remote {
    name = var.incus_remote
  }
}

# Existing IncusOS pools are host prerequisites, not managed lifecycle here.
data "incus_storage_pool" "root" {
  name   = var.storage_pool
  remote = var.incus_remote
}

resource "incus_network" "private" {
  name        = "gardenbr0"
  description = "Digital Garden backend bridge"
  type        = "bridge"
  project     = "default"
  remote      = var.incus_remote

  config = {
    "ipv4.dhcp"     = "true"
    "ipv4.nat"      = "true"
    "ipv4.firewall" = "true"
    "ipv6.address"  = "none"
    "dns.domain"    = "garden.internal"
    "dns.mode"      = "managed"
  }

  # Omit the address so Incus allocates a subnet. The provider tracks it as computed.
}

resource "incus_image" "edge" {
  project = "default"
  remote  = var.incus_remote

  source_file = {
    metadata_path = "${var.image_directory}/metadata.tar.xz"
    data_path     = "${var.image_directory}/rootfs.tar.xz"
  }
}

variable "edge_lan_parent" {
  description = "Optional existing IncusOS LAN bridge; configured in local inputs."
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
    error_message = "When enabling LAN, supply a locally administered MAC starting with 02."
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
  name        = "edge"
  description = "Digital Garden NixOS edge; private bootstrap"
  type        = "container"
  image       = incus_image.edge.fingerprint
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
    properties = {
      network = incus_network.private.name
      name    = "eth0"
    }
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
    for_each = var.edge_lan_parent == null ? [] : [var.edge_lan_parent]
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

# Read server-generated values only after the managed bridge exists.
data "incus_network" "private" {
  name       = incus_network.private.name
  project    = "default"
  remote     = var.incus_remote
  depends_on = [incus_network.private]
}

output "private_bridge_ipv4" {
  value = data.incus_network.private.config["ipv4.address"]
}
