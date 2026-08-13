{
  config,
  lib,
  user,
  ...
}:
with lib;
let
  cfg = config.modules.virtualization;
in
{
  options = {
    modules.virtualization.enable = mkEnableOption "Enable virtualization" // {
      default = true;
    };
  };
  config = mkIf cfg.enable {
    users = {
      users.${user.username} = {
        extraGroups = mkAfter [
          "docker"
        ];
      };
    };

    virtualisation = {
      docker.enable = true;
      docker.daemon.settings = {
        bip = "10.200.0.1/24";
        default-address-pools = [
          {
            base = "10.201.0.0/16";
            size = 24;
          }
        ];
      };

      containers.enable = true;
    };
  };
}
