variable "llama_gpu_pci" {
  description = "AMD GPU PCI address from ignored local host inputs; null leaves inference disabled."
  type        = string
  default     = null

  validation {
    condition     = var.llama_gpu_pci == null || can(regex("^[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\\.[0-7]$", var.llama_gpu_pci))
    error_message = "Use configure-llama.py to select an existing AMD GPU."
  }
}

locals {
  llama_enabled = var.llama_gpu_pci != null
  llama_image   = jsondecode(file("${path.module}/../llama/image.lock.json"))
  llama_presets = file("${path.module}/../llama/models.ini.tftpl")
}

resource "incus_storage_volume" "llama_cache" {
  count   = local.llama_enabled ? 1 : 0
  name    = "garden-llama-cache"
  pool    = data.incus_storage_pool.root.name
  project = "default"
  remote  = var.incus_remote

  config = {
    "initial.uid"  = "1000"
    "initial.gid"  = "1000"
    "initial.mode" = "0750"
    "size"         = "64GiB"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "incus_storage_volume" "llama_config" {
  count   = local.llama_enabled ? 1 : 0
  name    = "garden-llama-config"
  pool    = data.incus_storage_pool.root.name
  project = "default"
  remote  = var.incus_remote
  file {
    target_path = "/models.ini"
    content     = local.llama_presets
    mode        = "0644"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "incus_instance" "llama" {
  count       = local.llama_enabled ? 1 : 0
  name        = "garden-llama"
  description = "Digital Garden private ROCm inference router"
  image       = "garden-ghcr:${local.llama_image.repository}@${local.llama_image.digest}"
  type        = "container"
  project     = "default"
  remote      = var.incus_remote
  profiles    = []
  running     = true

  config = {
    "boot.autostart"                        = "true"
    "boot.autorestart"                      = "true"
    "limits.cpu"                            = "4"
    "limits.memory"                         = "20GiB"
    "security.privileged"                   = "false"
    "oci.uid"                               = "1000"
    "oci.gid"                               = "1000"
    "environment.LLAMA_CACHE"               = "/var/cache/llama"
    "environment.LLAMA_ARG_MODELS_PRESET"   = "/etc/llama/models.ini"
    "environment.LLAMA_ARG_MODELS_MAX"      = "1"
    "environment.LLAMA_ARG_MODELS_AUTOLOAD" = "true"
    "environment.LLAMA_ARG_HOST"            = "0.0.0.0"
    "environment.LLAMA_ARG_PORT"            = "8080"
    "environment.LLAMA_ARG_UI"              = "false"
  }

  device {
    name       = "root"
    type       = "disk"
    properties = { path = "/", pool = data.incus_storage_pool.root.name, size = "32GiB" }
  }

  device {
    name       = "eth0"
    type       = "nic"
    properties = { name = "eth0", network = incus_network.private.name }
  }

  device {
    name = "cache"
    type = "disk"
    properties = {
      path   = "/var/cache/llama"
      pool   = incus_storage_volume.llama_cache[0].pool
      source = incus_storage_volume.llama_cache[0].name
    }
  }

  device {
    name = "config"
    type = "disk"
    properties = {
      path     = "/etc/llama"
      pool     = incus_storage_volume.llama_config[0].pool
      source   = incus_storage_volume.llama_config[0].name
      readonly = "true"
    }
  }

  device {
    name = "gpu"
    type = "gpu"
    properties = {
      gputype = "physical"
      pci     = var.llama_gpu_pci
      uid     = "1000"
      gid     = "1000"
      mode    = "0660"
    }
  }

  device {
    name = "kfd"
    type = "unix-char"
    properties = {
      source = "/dev/kfd"
      path   = "/dev/kfd"
      uid    = "1000"
      gid    = "1000"
      mode   = "0660"
    }
  }

  wait_for {
    type = "ipv4"
    nic  = "eth0"
  }
}

output "llama_ipv4" {
  value = local.llama_enabled ? incus_instance.llama[0].ipv4_address : null
}
