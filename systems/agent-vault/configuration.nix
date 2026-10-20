{ lib, pkgs, ... }:
let
  network = builtins.fromJSON (builtins.readFile ../../agent-network.json);
  agentVault = pkgs.callPackage ../../nix/packages/agent-vault.nix { };
in
{
  # Ciphertext is staged during bootstrap; no placeholder keys or secrets.
  # Without it the unit cannot start because its stdin file is unavailable.
  sops = lib.mkIf (builtins.pathExists ./secrets.yaml) {
    defaultSopsFile = ./secrets.yaml;
    age.keyFile = "/var/lib/garden-secrets/age.key";
    age.sshKeyPaths = [ ];
    gnupg.sshKeyPaths = [ ];
    secrets.master-password = {
      owner = "agent-vault";
      group = "agent-vault";
      mode = "0400";
      restartUnits = [ "agent-vault.service" ];
    };
  };

  users.groups.agent-vault = { };
  users.users.agent-vault = {
    isSystemUser = true;
    group = "agent-vault";
    home = "/var/lib/agent-vault";
  };
  environment.systemPackages = [ agentVault ];
  environment.variables.AGENT_VAULT_TELEMETRY = "false";

  # Pi may use its scoped token on the API over the isolated link.
  # Operator sessions remain local; neither port is open on the backend NIC.
  networking.firewall.extraInputRules = ''
    iifname "eth1" ip saddr ${network.sandboxIPv4} tcp dport ${toString network.proxyPort} accept
    iifname "eth1" ip saddr ${network.sandboxIPv4} tcp dport ${toString network.apiPort} accept
  '';
  systemd.services.agent-vault = {
    description = "Standalone Agent Vault credential proxy";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    environment = {
      HOME = "/var/lib/agent-vault";
      AGENT_VAULT_TELEMETRY = "false";
      AGENT_VAULT_ALLOW_PRIVATE_RANGES = "false";
      # Intentionally empty until individual internal endpoints are approved.
      AGENT_VAULT_NETWORK_ALLOWLIST = "";
    };
    unitConfig = {
      RequiresMountsFor = [
        "/var/lib/agent-vault"
        "/var/lib/garden-secrets"
      ];
      ConditionPathIsMountPoint = [
        "/var/lib/agent-vault"
        "/var/lib/garden-secrets"
      ];
    };
    serviceConfig = {
      User = "agent-vault";
      Group = "agent-vault";
      StateDirectory = "agent-vault";
      StateDirectoryMode = "0700";
      WorkingDirectory = "/var/lib/agent-vault";
      # StandardInput cannot open a per-unit credential path (%d). Use the
      # service-owned sops-nix file, which exists before the unit starts.
      StandardInput = "file:/run/secrets/master-password";
      ExecStartPre = "${pkgs.coreutils}/bin/test -s /run/secrets/master-password";
      ExecStart = "${agentVault}/bin/agent-vault server --host 0.0.0.0 --port ${toString network.apiPort} --mitm-port ${toString network.proxyPort} --password-stdin";
      Restart = "on-failure";
      RestartSec = "5s";
      UMask = "0077";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      RestrictAddressFamilies = [
        "AF_UNIX"
        "AF_INET"
        "AF_INET6"
      ];
      CapabilityBoundingSet = "";
    };
  };
}
