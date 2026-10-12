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
      try(trimspace(file("${var.image_directory}/garden-system")) == "identity", false)
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
resource "incus_storage_volume" "identity" {
  name    = "garden-identity-state"
  pool    = data.incus_storage_pool.root.name
  project = local.target.project
  remote  = var.incus_remote
  config  = { "initial.mode" = "0700" }

  lifecycle {
    prevent_destroy = true
  }
}

resource "incus_storage_volume" "identity_secrets" {
  name    = "garden-identity-secrets"
  pool    = data.incus_storage_pool.root.name
  project = local.target.project
  remote  = var.incus_remote
  config  = { "initial.mode" = "0700" }

  lifecycle {
    prevent_destroy = true
  }
}

resource "incus_instance" "identity" {
  name        = local.target.instance
  description = "Digital Garden private Kanidm"
  type        = "container"
  image       = incus_image.seed.fingerprint
  project     = local.target.project
  remote      = var.incus_remote
  profiles    = []
  running     = true

  config = {
    "boot.autostart"        = "true"
    "limits.cpu"            = "2"
    "limits.memory"         = "2GiB"
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
    properties = {
      network = data.incus_network.private.name
      name    = "eth0"
    }
  }

  device {
    name = "identity-state"
    type = "disk"
    properties = {
      path   = "/var/lib/kanidm"
      pool   = incus_storage_volume.identity.pool
      source = incus_storage_volume.identity.name
    }
  }

  device {
    name = "identity-secrets"
    type = "disk"
    properties = {
      path   = "/var/lib/garden-secrets"
      pool   = incus_storage_volume.identity_secrets.pool
      source = incus_storage_volume.identity_secrets.name
    }
  }

  device {
    name = "acme"
    type = "disk"
    properties = {
      path   = "/var/lib/acme"
      pool   = incus_storage_volume.acme.pool
      source = incus_storage_volume.acme.name
    }
  }

  wait_for {
    type = "ipv4"
    nic  = "eth0"
  }
}

output "identity_ipv4" {
  value = incus_instance.identity.ipv4_address
}

resource "incus_storage_volume" "acme" {
  name    = "garden-identity-acme"
  pool    = data.incus_storage_pool.root.name
  project = local.target.project
  remote  = var.incus_remote
  config  = { "initial.mode" = "0700" }
  lifecycle { prevent_destroy = true }
}
