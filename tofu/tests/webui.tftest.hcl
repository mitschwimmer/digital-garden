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

run "webui_is_private_and_persistent" {
  command = plan

  assert {
    condition = (
      length(incus_instance.webui.device) == 4 &&
      [for device in incus_instance.webui.device : device if device.type == "nic"][0].properties["network"] == incus_network.private.name &&
      [for device in incus_instance.webui.device : device if device.name == "webui-state"][0].properties["source"] == incus_storage_volume.webui.name &&
      [for device in incus_instance.webui.device : device if device.name == "webui-secrets"][0].properties["source"] == incus_storage_volume.webui_secrets.name &&
      incus_instance.webui.config["security.privileged"] == "false"
    )
    error_message = "WebUI must have one private NIC and separate persistent state and identity volumes."
  }
}
