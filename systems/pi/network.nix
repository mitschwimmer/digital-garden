{ lib, ... }:
let
  network = builtins.fromJSON (builtins.readFile ../../agent-network.json);
in
{
  networking.useDHCP = lib.mkForce false;
  networking.interfaces.eth0 = {
    useDHCP = false;
    ipv4.addresses = [
      {
        address = network.sandboxIPv4;
        prefixLength = network.prefixLength;
      }
    ];
  };
  networking.hosts.${network.vaultIPv4} = [ "agent-vault.internal" ];
  networking.nameservers = lib.mkForce [ ];
  services.resolved.enable = lib.mkForce false;
  services.timesyncd.enable = lib.mkForce false;
  # No gateway, resolver or second NIC. Upstream names resolve at the proxy.
}
