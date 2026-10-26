{ lib, pkgs, ... }:
let
  encrypted = ./secrets.yaml;
  ready = builtins.pathExists encrypted;
  cert = "identity.archaic.work";
in {
  imports = [ ./directory.nix ./immich.nix ./walter.nix ];
  assertions = [ {
    assertion = ready;
    message = "Prepare systems/identity/secrets.yaml before building identity.";
  } ];
  sops = lib.mkIf ready {
    defaultSopsFile = encrypted;
    age.keyFile = "/var/lib/garden-secrets/age.key";
    age.sshKeyPaths = [ ];
    gnupg.sshKeyPaths = [ ];
    secrets = lib.genAttrs [ "admin" "idm-admin" ] (_: {
      owner = "kanidm";
      group = "kanidm";
      mode = "0400";
      restartUnits = [ "kanidm.service" ];
    });
  };

  security.acme = {
    acceptTerms = true;
    certs.${cert} = {
      listenHTTP = ":8081";
      group = "kanidm";
      reloadServices = [ "kanidm.service" ];
    };
  };
  # Provision locally with verified TLS, independent of public DNS/hairpin NAT.
  networking.hosts."127.0.0.1" = [ cert ];
  networking.firewall.interfaces.eth0.allowedTCPPorts = [ 8443 8081 ];
  services.kanidm = {
    # Nixpkgs-maintained patches permit predetermined runtime-file secrets.
    package = pkgs.kanidm_1_11.withSecretProvisioning;
    server = {
      enable = true;
      settings = {
        domain = "auth.archaic.work";
        origin = "https://auth.archaic.work";
        bindaddress = "0.0.0.0:8443";
        tls_chain = "/var/lib/acme/${cert}/fullchain.pem";
        tls_key = "/var/lib/acme/${cert}/key.pem";
      };
    };
    provision = {
      enable = true;
      instanceUrl = "https://${cert}:8443";
      acceptInvalidCerts = false;
      adminPasswordFile = "/run/secrets/admin";
      idmAdminPasswordFile = "/run/secrets/idm-admin";
      # Deletion must be explicit (present = false), not an accidental omission.
      autoRemove = false;
      # Retain the tombstone: autoRemove = false does not delete omitted clients.
      systems.oauth2.open-webui = {
        present = false;
        displayName = "Open WebUI";
        originUrl = "https://ai.archaic.work/oauth/oidc/callback";
        originLanding = "https://ai.archaic.work";
      };
    };
  };
  systemd.services.kanidm = {
    # Wait for a real certificate, not the ACME module's bootstrap self-signed one.
    requires = [ "acme-order-renew-${cert}.service" ];
    after = [ "acme-order-renew-${cert}.service" "sops-nix.service" ];
    unitConfig = {
      RequiresMountsFor = [ "/var/lib/kanidm" "/var/lib/garden-secrets" "/var/lib/acme" ];
      ConditionPathIsMountPoint = [ "/var/lib/kanidm" "/var/lib/garden-secrets" "/var/lib/acme" ];
    };
  };
  systemd.services."acme-setup".unitConfig = {
    RequiresMountsFor = [ "/var/lib/acme" ];
    ConditionPathIsMountPoint = "/var/lib/acme";
  };
  systemd.services."acme-order-renew-${cert}".unitConfig = {
    RequiresMountsFor = [ "/var/lib/acme" ];
    ConditionPathIsMountPoint = "/var/lib/acme";
  };
  systemd.services."acme-${cert}".unitConfig = {
    RequiresMountsFor = [ "/var/lib/acme" ];
    ConditionPathIsMountPoint = "/var/lib/acme";
  };
}
