{ lib, ... }:
{
  networking.enableIPv6 = lib.mkForce true;
  networking.useDHCP = lib.mkForce false;
  systemd.network.networks = {
    "10-backend" = {
      matchConfig.Name = "eth0";
      networkConfig = {
        DHCP = "ipv4";
        Domains = [ "~garden.internal" ];
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
    resume = false;
    enableReload = false;
    globalConfig = ''
      admin off
      persist_config off
      servers {
        protocols h1 h2
      }
    '';
    virtualHosts = {
      # Native OIDC belongs to the application. Caddy never authenticates users.
      "ai.archaic.work" = {
        logFormat = null;
        extraConfig = "reverse_proxy open-webui.garden.internal:8080";
      };
      "auth.archaic.work" = {
        logFormat = null;
        extraConfig = ''
          reverse_proxy https://identity.garden.internal:8443 {
            transport http {
              tls_server_name identity.archaic.work
            }
          }
        '';
      };
      # The identity guest owns its backend certificate and ACME renewal.
      # This hostname has no public application or automatic HTTPS listener.
      "http://identity.archaic.work" = {
        logFormat = null;
        extraConfig = ''
          handle /.well-known/acme-challenge/* {
            reverse_proxy identity.garden.internal:8081
          }
          handle {
            respond 404
          }
        '';
      };
      "test.archaic.work" = {
        logFormat = "output stderr";
        extraConfig = ''
          respond "Digital Garden edge is ready.\n" 200
        '';
      };
      "http://127.0.0.1:8080" = {
        logFormat = null;
        extraConfig = ''
          respond /healthz "ok\n" 200
        '';
      };
    };
  };

  # Refuse to put certificate state on the disposable container root disk.
  systemd.services.caddy.unitConfig = {
    ConditionPathIsMountPoint = "/var/lib/caddy";
    RequiresMountsFor = [ "/var/lib/caddy" ];
  };
  systemd.services.caddy.serviceConfig.StateDirectoryMode = "0700";
}
