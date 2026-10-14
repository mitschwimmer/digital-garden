{ lib, pkgs, ... }:
let
  policy = builtins.fromJSON (builtins.readFile ../../network-policy.json);
  accounts = [
    "henner"
    "claudi"
    "elmo"
  ];
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
      directory = "/var/lib/webdav";
      permissions = "none";
      users = map (name: {
        username = name;
        password = "{env}WEBDAV_${lib.toUpper name}_PASSWORD";
        directory = "/var/lib/webdav/${name}";
        permissions = "CRUD";
      }) accounts;
    };
  };

  # No general port opening: only edge may reach the backend listener.
  # The common container module disables IPv6 on the backend bridge.
  networking.firewall.extraInputRules = lib.optionalString (policy.edgeBackendIPv4 != null) ''
    iifname "eth0" ip saddr ${policy.edgeBackendIPv4} tcp dport 6065 accept
  '';
  systemd.tmpfiles.rules = map (name: "d /var/lib/webdav/${name} 0700 webdav webdav -") accounts;
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
      # The native module has no distinct/nonempty credential validation.
      ExecStartPre = "${pkgs.python3}/bin/python ${../../operations/check_webdav_credentials.py}";
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
