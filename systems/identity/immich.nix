{ lib, ... }:
let
  ready = builtins.pathExists ./immich-secrets.yaml;
in {
  # Stage the new ciphertext before provisioning this client. Existing identity
  # and WebUI remain buildable during preparation; autoRemove remains false.
  sops.secrets.immich-client = lib.mkIf ready {
    sopsFile = ./immich-secrets.yaml;
    owner = "kanidm";
    group = "kanidm";
    mode = "0400";
    restartUnits = [ "kanidm.service" ];
  };
  services.kanidm.provision.systems.oauth2.immich = lib.mkIf ready {
    displayName = "Immich";
    originUrl = [
      "https://photos.archaic.work/auth/login"
      "https://photos.archaic.work/user-settings"
      "https://photos.archaic.work/api/oauth/mobile-redirect"
    ];
    originLanding = "https://photos.archaic.work";
    basicSecretFile = "/run/secrets/immich-client";
    preferShortUsername = true;
    # Immich 3 supports S256 PKCE and Kanidm's default ES256 signing.
    allowInsecureClientDisablePkce = false;
    enableLegacyCrypto = false;
    scopeMaps = {
      photos-users = [ "openid" "profile" "email" ];
      admins = [ "openid" "profile" "email" ];
    };
    claimMaps.immich_role = {
      joinType = "array";
      valuesByGroup = {
        photos-users = [ "user" ];
        admins = [ "admin" ];
      };
    };
  };
}
