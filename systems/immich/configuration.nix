{ lib, pkgs, ... }:
let
  ready = builtins.pathExists ./secrets.yaml;
in {
  assertions = [ {
    assertion = ready && builtins.pathExists ../identity/immich-secrets.yaml;
    message = "Prepare encrypted Immich client inputs for both consumers before building Immich.";
  } ];
  sops = lib.mkIf ready {
    defaultSopsFile = ./secrets.yaml;
    age.keyFile = "/var/lib/garden-secrets/age.key";
    age.sshKeyPaths = [ ];
    gnupg.sshKeyPaths = [ ];
    secrets.immich-client = {
      mode = "0400";
      restartUnits = [ "immich-server.service" ];
    };
  };

  services.immich = {
    enable = true;
    host = "0.0.0.0";
    port = 2283;
    openFirewall = false;
    mediaLocation = "/var/lib/immich";
    accelerationDevices = [ ];
    settings = {
      server.externalDomain = "https://photos.archaic.work";
      passwordLogin.enabled = false;
      oauth = {
        enabled = true;
        autoRegister = true;
        autoLaunch = true;
        buttonText = "Sign in with Kanidm";
        clientId = "immich";
        clientSecret._secret = "/run/secrets/immich-client";
        issuerUrl = "https://auth.archaic.work/oauth2/openid/immich/.well-known/openid-configuration";
        scope = "openid profile email";
        tokenEndpointAuthMethod = "client_secret_basic";
        signingAlgorithm = "ES256";
        profileSigningAlgorithm = "none";
        roleClaim = "immich_role";
        mobileOverrideEnabled = true;
        mobileRedirectUri = "https://photos.archaic.work/api/oauth/mobile-redirect";
      };
    };
  };
  # Keep the database major version explicit; upgrades require a migration.
  services.postgresql.package = pkgs.postgresql_16;
  services.postgresql.dataDir = "/var/lib/postgresql/16";
  networking.firewall.interfaces.eth0.allowedTCPPorts = [ 2283 ];

  # Stable guest-local ownership for retained media and database volumes.
  users.groups.immich.gid = 990;
  users.users.immich.uid = 990;

  systemd.services.immich-server = {
    after = [ "sops-nix.service" ];
    unitConfig = {
      RequiresMountsFor = [ "/var/lib/immich" "/var/lib/postgresql" "/var/lib/garden-secrets" ];
      ConditionPathIsMountPoint = [ "/var/lib/immich" "/var/lib/postgresql" "/var/lib/garden-secrets" ];
    };
    serviceConfig = {
      PrivateUsers = lib.mkForce false;
      StateDirectoryMode = "0700";
    };
  };
  systemd.services.immich-machine-learning.serviceConfig.PrivateUsers = lib.mkForce false;
  systemd.services.postgresql.unitConfig = {
    RequiresMountsFor = [ "/var/lib/postgresql" ];
    ConditionPathIsMountPoint = "/var/lib/postgresql";
  };
  systemd.services.postgresql-setup.unitConfig = {
    RequiresMountsFor = [ "/var/lib/postgresql" ];
    ConditionPathIsMountPoint = "/var/lib/postgresql";
  };
}
