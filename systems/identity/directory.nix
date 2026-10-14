{ ... }:
{
  services.kanidm.provision = {
    groups = {
      photos-users = { members = [ "henner" "claudi" ]; };
      ai-users = { members = [ "henner" "claudi" ]; };
      admins = { members = [ "henner" ]; };
    };
    persons.henner = {
      displayName = "Henner";
      mailAddresses = [ "henner@archaic.work" ];
    };
    persons.claudi = {
      displayName = "Claudi";
      mailAddresses = [ "mail@claudiapatzak.de" ];
    };
  };
}
