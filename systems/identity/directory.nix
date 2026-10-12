{ ... }:
{
  # Add real persons (including mailAddresses) and group membership here before
  # first use. Credential/passkey enrollment is user-owned runtime state.
  # No implicit operator account or guessed email address is provisioned.
  services.kanidm.provision = {
    groups = {
      ai-users = { };
      admins = { };
    };
    persons = { };
  };
}
