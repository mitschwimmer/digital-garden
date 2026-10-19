locals {
  agent_network = jsondecode(file("${path.module}/../../agent-network.json"))
}

data "incus_network" "agent" {
  name    = local.agent_network.bridge
  project = "default"
  remote  = var.incus_remote
}
resource "incus_network_acl" "sandbox" {
  name        = "garden-pi-egress"
  description = "Pi can initiate TCP connections only to the credential proxy"
  project     = "default"
  remote      = var.incus_remote
  egress = [
    {
      action           = "allow"
      state            = "enabled"
      protocol         = "tcp"
      destination      = "${local.agent_network.vaultIPv4}/32"
      destination_port = tostring(local.agent_network.proxyPort)
    }
  ]
}

variable "image_directory" {
  description = "Absolute immutable Nix store directory produced by this system's seed-image build."
  type        = string

  validation {
    condition = (
      startswith(var.image_directory, "/nix/store/") &&
      fileexists("${var.image_directory}/metadata.tar.xz") &&
      fileexists("${var.image_directory}/rootfs.tar.xz") &&
      try(trimspace(file("${var.image_directory}/garden-system")) == "pi", false)
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
resource "incus_storage_volume" "pi" {
  name    = "garden-pi-home"
  pool    = data.incus_storage_pool.workspace.name
  project = local.target.project
  remote  = var.incus_remote
  config  = { "initial.mode" = "0700", "size" = "20GiB" }

  lifecycle {
    prevent_destroy = true
  }
}

resource "incus_instance" "pi" {
  name        = local.target.instance
  description = "Digital Garden Pi coding sandbox"
  type        = "container"
  image       = incus_image.seed.fingerprint
  project     = local.target.project
  remote      = var.incus_remote
  profiles    = []
  running     = true

  config = {
    "boot.autostart"        = "true"
    "limits.cpu"            = "4"
    "limits.memory"         = "4GiB"
    "security.privileged"   = "false"
    # Nix creates nested namespaces for sandboxed development builds.
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
      network                                = data.incus_network.agent.name
      name                                   = "eth0"
      "security.mac_filtering"               = "true"
      "security.acls"                        = incus_network_acl.sandbox.name
      "security.acls.default.ingress.action" = "reject"
      "security.acls.default.egress.action"  = "reject"
    }
  }

  device {
    name = "pi-state"
    type = "disk"
    properties = {
      path   = "/home/pi"
      pool   = incus_storage_volume.pi.pool
      source = incus_storage_volume.pi.name
    }
  }

  wait_for {
    type = "ipv4"
    nic  = "eth0"
  }
}

output "pi_ipv4" {
  value = incus_instance.pi.ipv4_address
}
