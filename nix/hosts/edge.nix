{ lib, pkgs, ... }:
{
  networking.hostName = "edge";
  networking.useNetworkd = true;
  networking.useDHCP = true;
  networking.enableIPv6 = false;

  networking.nftables.enable = true;
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ ];
    allowedUDPPorts = [ ];
  };

  # Management uses authenticated Incus exec, with no guest SSH listener.
  services.openssh.enable = lib.mkForce false;
  services.getty.helpLine = lib.mkForce "";
  users.mutableUsers = false;
  users.users.root.initialHashedPassword = lib.mkForce "!";

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  environment.systemPackages = [ pkgs.curl ];
  system.stateVersion = "26.05";
}
