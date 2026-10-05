{ lib, ... }:
{
  networking.enableIPv6 = lib.mkForce true;
  networking.useDHCP = lib.mkForce false;
  systemd.network.networks = {
    "10-backend" = {
      matchConfig.Name = "eth0";
      networkConfig = {
        DHCP = "ipv4";
        IPv6AcceptRA = false;
      };
      dhcpV4Config = {
        RouteMetric = 1024;
        ClientIdentifier = "mac";
      };
    };
    "10-lan" = {
      matchConfig.Name = "eth1";
      networkConfig = {
        DHCP = "yes";
        IPv6AcceptRA = true;
      };
      dhcpV4Config = {
        RouteMetric = 100;
        ClientIdentifier = "mac";
      };
      ipv6AcceptRAConfig.RouteMetric = 100;
    };
  };

  networking.firewall.interfaces.eth1.allowedTCPPorts = [ 80 443 ];
  services.caddy = {
    enable = true;
    openFirewall = false;
    globalConfig = ''
      servers {
        protocols h1 h2
      }
    '';
    virtualHosts = {
      "test.archaic.work".extraConfig = ''
        respond "Digital Garden edge is ready.\n" 200
      '';
      "http://127.0.0.1:8080".extraConfig = ''
        respond /healthz "ok\n" 200
      '';
    };
  };

  # Refuse to put certificate state on the disposable container root disk.
  systemd.services.caddy.unitConfig.ConditionPathIsMountPoint = "/var/lib/caddy";
  systemd.services.caddy.serviceConfig.StateDirectoryMode = "0700";
}
