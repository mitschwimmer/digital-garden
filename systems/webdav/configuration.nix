{ lib, ... }:
let
  policy = builtins.fromJSON (builtins.readFile ../../network-policy.json);
in
{
  assertions = [
    {
      assertion = builtins.pathExists ./secrets.yaml;
      message = "Prepare encrypted WebDAV inputs before building this consumer.";
    }
    {
      assertion = policy.edgeBackendIPv4 != null;
      message = "Reserve edge's backend IPv4 in network-policy.json before deploying WebDAV.";
    }
  ];
  sops = lib.mkIf (builtins.pathExists ./secrets.yaml) {
    defaultSopsFile = ./secrets.yaml;
    age.keyFile = "/var/lib/garden-secrets/age.key";
    age.sshKeyPaths = [ ];
    gnupg.sshKeyPaths = [ ];
    secrets.environment = {
      owner = "webdav";
      group = "webdav";
      mode = "0400";
      restartUnits = [ "webdav.service" ];
    };
  };

  services.webdav = {
    enable = true;
    environmentFile = "/run/secrets/environment";
    settings = {
      address = "0.0.0.0";
      port = 6065;
      directory = "/var/lib/webdav/enpass";
      permissions = "none";
      users = [
        {
          username = "enpass";
          password = "{env}ENPASS_WEBDAV_PASSWORD";
          permissions = "CRUD";
        }
      ];
    };
  };

  # No general port opening: only edge may reach the backend listener.
  # The common container module disables IPv6 on the backend bridge.
  networking.firewall.extraInputRules = lib.optionalString (policy.edgeBackendIPv4 != null) ''
    iifname "eth0" ip saddr ${policy.edgeBackendIPv4} tcp dport 6065 accept
  '';
  systemd.tmpfiles.rules = [ "d /var/lib/webdav/enpass 0700 webdav webdav -" ];
  systemd.services.webdav = {
    unitConfig = {
      RequiresMountsFor = [
        "/var/lib/webdav"
        "/var/lib/garden-secrets"
      ];
      ConditionPathIsMountPoint = [
        "/var/lib/webdav"
        "/var/lib/garden-secrets"
      ];
    };
    serviceConfig = {
      StateDirectory = "webdav";
      StateDirectoryMode = "0700";
      UMask = "0077";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      RestartSec = "5s";
    };
  };
}
