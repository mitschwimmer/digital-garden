{ ... }:
let
  network = builtins.fromJSON (builtins.readFile ../../agent-network.json);
in
{
  networking.interfaces.eth1 = {
    useDHCP = false;
    ipv4.addresses = [
      {
        address = network.vaultIPv4;
        prefixLength = network.prefixLength;
      }
    ];
  };
  # This dual-homed guest is an application proxy, never an IP router.
  networking.nftables.tables.agent-boundary = {
    family = "inet";
    content = ''
      chain forward {
        type filter hook forward priority -10; policy drop;
      }
    '';
  };
}
