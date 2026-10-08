variable "llama_gpu_pci" {
  description = "AMD GPU PCI address from inspected local host inputs; required at stage 5."
  type        = string
  default     = null

  validation {
    condition     = var.llama_gpu_pci == null || can(regex("^[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\\.[0-7]$", var.llama_gpu_pci))
    error_message = "Supply the PCI address of an existing AMD GPU."
  }
}

locals {
  llama_image = jsondecode(file("${path.module}/../llama/image.lock.json"))
}

resource "incus_storage_volume" "llama_cache" {
  name    = "garden-llama-cache"
  pool    = data.incus_storage_pool.root.name
  project = incus_project.inference.name
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
  name    = "garden-llama-config"
  pool    = data.incus_storage_pool.root.name
  project = incus_project.inference.name
  remote  = var.incus_remote

  config = {
    "initial.uid"  = "0"
    "initial.gid"  = "0"
    "initial.mode" = "0755"
  }

  file {
    content            = file("${path.module}/../llama/models.ini")
    target_path        = "/models.ini"
    uid                = 0
    gid                = 0
    mode               = "0444"
    create_directories = false
  }

  lifecycle {
    prevent_destroy = true
  }
}

# OpenTofu delivers public presets before creating/starting the OCI instance.
resource "incus_instance" "llama" {
  count       = local.llama_enabled ? 1 : 0
  name        = "garden-llama"
  description = "Digital Garden private ROCm inference router"
  image       = "garden-ghcr:${local.llama_image.repository}@${local.llama_image.digest}"
  type        = "container"
  project     = incus_project.inference.name
  remote      = var.incus_remote
  profiles    = []
  running     = true

  lifecycle {
    precondition {
      condition     = var.llama_gpu_pci != null
      error_message = "Stage 5 requires an inspected AMD GPU PCI address and host /dev/kfd."
    }
  }

  config = {
    "boot.autostart"          = "true"
    "boot.autorestart"        = "true"
    "limits.cpu"              = "4"
    "limits.memory"           = "20GiB"
    "security.privileged"     = "false"
    "oci.uid"                 = "1000"
    "oci.gid"                 = "1000"
    "environment.LLAMA_CACHE" = "/var/cache/llama"
    "oci.entrypoint"          = "/app/llama-server --models-preset /etc/llama/models.ini --models-max 1 --models-autoload --host 0.0.0.0 --port 8080 --no-webui"
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
      pool   = incus_storage_volume.llama_cache.pool
      source = incus_storage_volume.llama_cache.name
    }
  }

  device {
    name = "config"
    type = "disk"
    properties = {
      path     = "/etc/llama"
      pool     = incus_storage_volume.llama_config.pool
      source   = incus_storage_volume.llama_config.name
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
}

output "llama_ipv4" {
  value = local.llama_enabled ? incus_instance.llama[0].ipv4_address : null
}
