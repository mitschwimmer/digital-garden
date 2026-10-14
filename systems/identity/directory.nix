{ ... }:
{
  services.kanidm.provision = {
    groups = {
      photos-users = { members = [ "henner" "claudi" "elmo" ]; };
      ai-users = { members = [ "henner" "claudi" "elmo" ]; };
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
    persons.elmo = {
      displayName = "Elmo";
      mailAddresses = [ "elmo@mitschwimmer.de" ];
    };
  };
}
