mock_provider "incus" {
  mock_data "incus_network" {
    defaults = {
      config = { "ipv4.address" = "10.240.0.1/24" }
    }
  }
}

variables {
  incus_remote = "test"
  storage_pool = "test"
}

run "gpu_is_explicit_before_enabling_inference" {
  command = plan

  assert {
    condition     = length(incus_instance.llama) == 0 && length(incus_storage_volume.llama_cache) == 0
    error_message = "Inference must remain disabled until a host GPU is selected locally."
  }
}

run "private_pinned_gpu_router" {
  command = plan

  variables {
    llama_gpu_pci = "0000:01:00.0"
  }

  assert {
    condition = (
      endswith(incus_instance.llama[0].image, local.llama_image.digest) &&
      length([for device in incus_instance.llama[0].device : device if device.type == "nic"]) == 1 &&
      [for device in incus_instance.llama[0].device : device if device.type == "nic"][0].properties["network"] == incus_network.private.name &&
      [for device in incus_instance.llama[0].device : device if device.name == "gpu"][0].properties["pci"] == var.llama_gpu_pci &&
      [for device in incus_instance.llama[0].device : device if device.name == "kfd"][0].properties["source"] == "/dev/kfd" &&
      [for device in incus_instance.llama[0].device : device if device.name == "config"][0].properties["readonly"] == "true" &&
      incus_instance.llama[0].config["environment.LLAMA_ARG_MODELS_MAX"] == "1" &&
      incus_instance.llama[0].config["security.privileged"] == "false"
    )
    error_message = "Inference must use a pinned image, one private NIC, explicit GPU/KFD, read-only presets, and bounded model loading."
  }
}
