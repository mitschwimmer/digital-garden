# Plan-only tests with mocked Incus calls; supply a valid local seed directory.
mock_provider "incus" {
  mock_resource "incus_image" {
    defaults = { fingerprint = "test-seed-fingerprint" }
  }
  mock_data "incus_storage_pool" {
    defaults = { name = "test-pool" }
  }
  mock_data "incus_network" {
    defaults = { config = { "ipv4.address" = "10.10.10.1/24" } }
  }
}

variables {
  incus_remote    = "local"
  storage_pool    = "test-pool"
  edge_lan_parent = "test-lan"
  edge_lan_mac    = "02:00:00:00:00:01"
  llama_gpu_pci   = "0000:01:00.0"
}

run "lan_0_webui_0_inference_0" {
  command = plan
  variables {
    enable_edge_lan  = false
    enable_webui     = false
    enable_inference = false
  }
  assert {
    condition = (
      length(incus_instance.webui) == 0 &&
      length(incus_instance.llama) == 0 &&
      length([for device in incus_instance.edge.device : device if device.name == "eth1"]) == 0
    )
    error_message = "Service selection must not enable or disable another service or the edge LAN NIC."
  }
  assert {
    condition = (
      incus_storage_volume.webui.name == "garden-open-webui-state" &&
      incus_storage_volume.llama_cache.name == "garden-llama-cache" &&
      incus_storage_volume.llama_config.name == "garden-llama-config"
    )
    error_message = "Application state volumes must remain declared when a guest is disabled."
  }
}

run "lan_0_webui_0_inference_1" {
  command = plan
  variables {
    enable_edge_lan  = false
    enable_webui     = false
    enable_inference = true
  }
  assert {
    condition = (
      length(incus_instance.webui) == 0 &&
      length(incus_instance.llama) == 1 &&
      length([for device in incus_instance.edge.device : device if device.name == "eth1"]) == 0
    )
    error_message = "Service selection must not enable or disable another service or the edge LAN NIC."
  }
  assert {
    condition = (
      incus_storage_volume.webui.name == "garden-open-webui-state" &&
      incus_storage_volume.llama_cache.name == "garden-llama-cache" &&
      incus_storage_volume.llama_config.name == "garden-llama-config"
    )
    error_message = "Application state volumes must remain declared when a guest is disabled."
  }
}

run "lan_0_webui_1_inference_0" {
  command = plan
  variables {
    enable_edge_lan  = false
    enable_webui     = true
    enable_inference = false
  }
  assert {
    condition = (
      length(incus_instance.webui) == 1 &&
      length(incus_instance.llama) == 0 &&
      length([for device in incus_instance.edge.device : device if device.name == "eth1"]) == 0
    )
    error_message = "Service selection must not enable or disable another service or the edge LAN NIC."
  }
  assert {
    condition = (
      incus_storage_volume.webui.name == "garden-open-webui-state" &&
      incus_storage_volume.llama_cache.name == "garden-llama-cache" &&
      incus_storage_volume.llama_config.name == "garden-llama-config"
    )
    error_message = "Application state volumes must remain declared when a guest is disabled."
  }
}

run "lan_0_webui_1_inference_1" {
  command = plan
  variables {
    enable_edge_lan  = false
    enable_webui     = true
    enable_inference = true
  }
  assert {
    condition = (
      length(incus_instance.webui) == 1 &&
      length(incus_instance.llama) == 1 &&
      length([for device in incus_instance.edge.device : device if device.name == "eth1"]) == 0
    )
    error_message = "Service selection must not enable or disable another service or the edge LAN NIC."
  }
  assert {
    condition = (
      incus_storage_volume.webui.name == "garden-open-webui-state" &&
      incus_storage_volume.llama_cache.name == "garden-llama-cache" &&
      incus_storage_volume.llama_config.name == "garden-llama-config"
    )
    error_message = "Application state volumes must remain declared when a guest is disabled."
  }
}

run "lan_1_webui_0_inference_0" {
  command = plan
  variables {
    enable_edge_lan  = true
    enable_webui     = false
    enable_inference = false
  }
  assert {
    condition = (
      length(incus_instance.webui) == 0 &&
      length(incus_instance.llama) == 0 &&
      length([for device in incus_instance.edge.device : device if device.name == "eth1"]) == 1
    )
    error_message = "Service selection must not enable or disable another service or the edge LAN NIC."
  }
  assert {
    condition = (
      incus_storage_volume.webui.name == "garden-open-webui-state" &&
      incus_storage_volume.llama_cache.name == "garden-llama-cache" &&
      incus_storage_volume.llama_config.name == "garden-llama-config"
    )
    error_message = "Application state volumes must remain declared when a guest is disabled."
  }
}

run "lan_1_webui_0_inference_1" {
  command = plan
  variables {
    enable_edge_lan  = true
    enable_webui     = false
    enable_inference = true
  }
  assert {
    condition = (
      length(incus_instance.webui) == 0 &&
      length(incus_instance.llama) == 1 &&
      length([for device in incus_instance.edge.device : device if device.name == "eth1"]) == 1
    )
    error_message = "Service selection must not enable or disable another service or the edge LAN NIC."
  }
  assert {
    condition = (
      incus_storage_volume.webui.name == "garden-open-webui-state" &&
      incus_storage_volume.llama_cache.name == "garden-llama-cache" &&
      incus_storage_volume.llama_config.name == "garden-llama-config"
    )
    error_message = "Application state volumes must remain declared when a guest is disabled."
  }
}

run "lan_1_webui_1_inference_0" {
  command = plan
  variables {
    enable_edge_lan  = true
    enable_webui     = true
    enable_inference = false
  }
  assert {
    condition = (
      length(incus_instance.webui) == 1 &&
      length(incus_instance.llama) == 0 &&
      length([for device in incus_instance.edge.device : device if device.name == "eth1"]) == 1
    )
    error_message = "Service selection must not enable or disable another service or the edge LAN NIC."
  }
  assert {
    condition = (
      incus_storage_volume.webui.name == "garden-open-webui-state" &&
      incus_storage_volume.llama_cache.name == "garden-llama-cache" &&
      incus_storage_volume.llama_config.name == "garden-llama-config"
    )
    error_message = "Application state volumes must remain declared when a guest is disabled."
  }
}

run "lan_1_webui_1_inference_1" {
  command = plan
  variables {
    enable_edge_lan  = true
    enable_webui     = true
    enable_inference = true
  }
  assert {
    condition = (
      length(incus_instance.webui) == 1 &&
      length(incus_instance.llama) == 1 &&
      length([for device in incus_instance.edge.device : device if device.name == "eth1"]) == 1
    )
    error_message = "Service selection must not enable or disable another service or the edge LAN NIC."
  }
  assert {
    condition = (
      incus_storage_volume.webui.name == "garden-open-webui-state" &&
      incus_storage_volume.llama_cache.name == "garden-llama-cache" &&
      incus_storage_volume.llama_config.name == "garden-llama-config"
    )
    error_message = "Application state volumes must remain declared when a guest is disabled."
  }
}

run "reject_legacy_stage_1" {
  command = plan
  variables { stage = 1 }
  expect_failures = [var.stage]
}

run "reject_legacy_stage_2" {
  command = plan
  variables { stage = 2 }
  expect_failures = [var.stage]
}

run "reject_legacy_stage_3" {
  command = plan
  variables { stage = 3 }
  expect_failures = [var.stage]
}

run "reject_legacy_stage_4" {
  command = plan
  variables { stage = 4 }
  expect_failures = [var.stage]
}

run "reject_legacy_stage_5" {
  command = plan
  variables { stage = 5 }
  expect_failures = [var.stage]
}

run "reject_lan_without_parent" {
  command = plan
  variables {
    enable_edge_lan = true
    edge_lan_parent = null
  }
  expect_failures = [incus_instance.edge]
}

run "reject_inference_without_gpu" {
  command = plan
  variables {
    enable_inference = true
    llama_gpu_pci    = null
  }
  expect_failures = [incus_instance.llama]
}
