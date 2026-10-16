{ lib, ... }:
let
  ready = builtins.pathExists ./walter-secrets.yaml;
in
{
  sops.secrets.walter-client = lib.mkIf ready {
    sopsFile = ./walter-secrets.yaml;
    owner = "kanidm";
    group = "kanidm";
    mode = "0400";
    restartUnits = [ "kanidm.service" ];
  };
  services.kanidm.provision.systems.oauth2.walter = lib.mkIf ready {
    displayName = "Walter";
    originUrl = "https://walter.archaic.work/auth/callback";
    originLanding = "https://walter.archaic.work";
    basicSecretFile = "/run/secrets/walter-client";
    preferShortUsername = true;
    allowInsecureClientDisablePkce = false;
    enableLegacyCrypto = false;
    scopeMaps.ai-users = [ "openid" "profile" "groups" ];
    claimMaps.groups = {
      joinType = "array";
      valuesByGroup.ai-users = [ "ai-users" ];
    };
  };
}
