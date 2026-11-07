terraform {
  required_version = ">= 1.9.0, < 2.0.0"

  required_providers {
    incus = {
      source  = "lxc/incus"
      version = "= 1.2.1"
    }
  }
}

variable "incus_remote" {
  description = "Existing authenticated Incus remote pointing at measerve."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_.-]*$", var.incus_remote))
    error_message = "Enter an Incus client remote alias without a colon."
  }
}

variable "lan_parent" {
  description = "Inspected IncusOS instances-role LAN bridge (not the physical NIC's device path)."
  type        = string

  validation {
    condition     = length(trimspace(var.lan_parent)) > 0
    error_message = "Inspect incus network list and supply the LAN bridge."
  }
}

variable "lan_mac" {
  description = "Persistent, locally administered MAC with a DHCP reservation; keep in ignored local inputs."
  type        = string

  validation {
    condition     = can(regex("^02(:[0-9a-f]{2}){5}$", var.lan_mac))
    error_message = "Use a reserved lowercase MAC starting with 02."
  }
}

variable "installer_iso" {
  description = "Existing ISO volume imported into Incus local pool for Talos installation. Empty after installation."
  type        = string
  default     = ""
}

variable "installation_complete" {
  description = "Set true only after Talos has been installed to the system disk and reboot-tested."
  type        = bool
  default     = false
}

variable "start_vm" {
  description = "Deliberate VM power-on. Defaults to stopped until inspected."
  type        = bool
  default     = false
}

variable "enable_gpu_passthrough" {
  description = "Cold-attach AMD RX 9060 XT PCI function after confirming host availability."
  type        = bool
  default     = false
}

variable "cpu_count" {
  description = "VM vCPU count on the 14-CPU measerve host."
  type        = number
  default     = 8

  validation {
    condition     = var.cpu_count >= 2 && var.cpu_count <= 12 && floor(var.cpu_count) == var.cpu_count
    error_message = "Reserve some logical CPUs for IncusOS; choose between 2 and 12."
  }
}

variable "vm_memory" {
  description = "Talos VM memory; 24GiB leaves roughly 8GiB for IncusOS on measerve."
  type        = string
  default     = "24GiB"
}

variable "system_disk_size" {
  type    = string
  default = "64GiB"
}

variable "nvme_disk_size" {
  type    = string
  default = "128GiB"
}

variable "data_disk_size" {
  type    = string
  default = "1TiB"
}

provider "incus" {
  default_remote = var.incus_remote

  remote {
    name = var.incus_remote
  }
}

# These are pre-existing IncusOS-managed ZFS pools; never create or destroy them here.
data "incus_storage_pool" "nvme" {
  name   = "local"
  remote = var.incus_remote
}

data "incus_storage_pool" "data" {
  name   = "data"
  remote = var.incus_remote
}

resource "incus_storage_volume" "nvme" {
  name         = "garden-k8s-nvme"
  description  = "Talos Kubernetes fast-tier block disk (local ZFS / NVMe)"
  project      = "default"
  pool         = data.incus_storage_pool.nvme.name
  remote       = var.incus_remote
  content_type = "block"

  config = {
    "size" = var.nvme_disk_size
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "incus_storage_volume" "data" {
  name         = "garden-k8s-data"
  description  = "Talos Kubernetes bulk-tier block disk (mirrored ZFS data pool)"
  project      = "default"
  pool         = data.incus_storage_pool.data.name
  remote       = var.incus_remote
  content_type = "block"

  config = {
    "size" = var.data_disk_size
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "incus_instance" "talos" {
  name        = "garden-k8s"
  description = "Digital Garden one-node Talos Kubernetes"
  type        = "virtual-machine"
  project     = "default"
  remote      = var.incus_remote
  profiles    = []
  running     = var.start_vm

  # No image: empty UEFI VM, booted initially from an externally imported Talos ISO.
  config = {
    "boot.autostart"      = tostring(var.start_vm)
    "limits.cpu"          = tostring(var.cpu_count)
    "limits.memory"       = var.vm_memory
    "security.secureboot" = "false"
    "user.garden.system"  = "kubernetes"
  }

  device {
    name = "root"
    type = "disk"
    properties = {
      path = "/"
      pool = data.incus_storage_pool.nvme.name
      size = var.system_disk_size
    }
  }

  device {
    name = "eth0"
    type = "nic"
    properties = {
      name    = "eth0"
      nictype = "bridged"
      parent  = var.lan_parent
      hwaddr  = var.lan_mac
    }
  }

  # Distinct, stable device names become SCSI serials; verify in Talos before formatting.
  device {
    name = "k8s-nvme"
    type = "disk"
    properties = {
      pool   = incus_storage_volume.nvme.pool
      source = incus_storage_volume.nvme.name
      "io.bus" = "virtio-scsi"
    }
  }

  device {
    name = "k8s-data"
    type = "disk"
    properties = {
      pool   = incus_storage_volume.data.pool
      source = incus_storage_volume.data.name
      "io.bus" = "virtio-scsi"
    }
  }

  # Import the pinned Talos ISO as an Incus ISO volume before enabling boot.
  dynamic "device" {
    for_each = var.installer_iso == "" ? [] : [var.installer_iso]
    content {
      name = "installer"
      type = "disk"
      properties = {
        pool            = data.incus_storage_pool.nvme.name
        source          = device.value
        "boot.priority" = "10"
      }
    }
  }

  # AMD Radeon RX 9060 XT, dedicated IOMMU group 13 on inspected measerve host.
  # Separate HDMI audio function 0000:04:00.1 (group 14) stays on the host.
  dynamic "device" {
    for_each = var.enable_gpu_passthrough ? [true] : []
    content {
      name = "amdgpu"
      type = "gpu"
      properties = {
        gputype   = "physical"
        pci       = "0000:04:00.0"
        vendorid  = "1002"
        productid = "7590"
      }
    }
  }

  lifecycle {
    prevent_destroy = true

    precondition {
      condition     = !var.start_vm || var.installation_complete || var.installer_iso != ""
      error_message = "Cannot boot an uninstalled empty VM without an attached Talos ISO."
    }
  }
}

output "instance_name" {
  value = incus_instance.talos.name
}

output "nvme_volume" {
  value = incus_storage_volume.nvme.name
}

output "data_volume" {
  value = incus_storage_volume.data.name
}

output "talos_lan_mac" {
  value = var.lan_mac
}
