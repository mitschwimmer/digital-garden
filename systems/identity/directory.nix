{ ... }:
{
  services.kanidm.provision = {
    groups = {
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
