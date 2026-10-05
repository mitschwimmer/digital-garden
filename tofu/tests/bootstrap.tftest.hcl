# No real Incus calls: exercise the missing-key regression before creation.
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

run "assigned_address_after_creation" {
  command = apply

  assert {
    condition     = output.private_bridge_ipv4 == "10.240.0.1/24"
    error_message = "The bridge output must read the server-assigned address."
  }
}
