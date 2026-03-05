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
      containers.enable = true;
    };
  };
}
