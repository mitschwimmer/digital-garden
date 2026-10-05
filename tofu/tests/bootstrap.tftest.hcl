# All provider calls are mocked; plan-only checks preserve protected storage.
mock_provider "incus" {
  mock_data "incus_network" {
    defaults = {
      config = {
        "ipv4.address" = "10.240.0.1/24"
      }
    }
  }
}

variables {
  incus_remote = "test"
  storage_pool = "test"
}

run "first_plan_before_bridge_exists" {
  command = plan
}

run "new_lan_identity_is_explicit" {
  command = plan

  variables {
    edge_lan_parent = "test0"
    edge_lan_mac    = "02:00:00:00:00:01"
  }

  assert {
    condition = (
      [for nic in incus_instance.edge.device : nic if nic.name == "eth1"][0].properties["parent"] == "test0" &&
      [for nic in incus_instance.edge.device : nic if nic.name == "eth1"][0].properties["hwaddr"] == "02:00:00:00:00:01"
    )
    error_message = "The edge LAN NIC must use the configured parent and new persistent MAC."
  }
}
