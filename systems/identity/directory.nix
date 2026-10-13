{ ... }:
{
  services.kanidm.provision = {
    groups = {
      ai-users = { members = [ "henner" ]; };
      admins = { members = [ "henner" ]; };
    };
    persons.henner = {
      displayName = "Henner";
      mailAddresses = [ "henner@archaic.work" ];
    };
  };
}
