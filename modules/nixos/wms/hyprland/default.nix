{
  pkgs,
  config,
  lib,
  user,
  ...
}:
let
  inherit (lib) mkIf mkEnableOption;
  cfg = config.modules.hyprland;
  tuigreet = "${pkgs.tuigreet}/bin/tuigreet";
  session = "start-hyprland";
in
{
  options = {
    modules.hyprland.enable = mkEnableOption "Enable hyprland module" // {
      default = true;
    };
  };
  config = mkIf cfg.enable {
    services = {
      greetd = {
        enable = true;
        settings = {
          initial_session = {
            command = "${session}";
            user = "${user.username}";
          };
          default_session = {
            command = "${tuigreet} --greeting 'Welcome to NixOS!' --asterisks --time --remember --remember-user-session -cmd ${session}";
            user = "greeter";
          };
        };
      };
      xserver = {
        enable = true;
        xkb.layout = "us";
      };
    };
    systemd.services.greetd.serviceConfig = {
      Type = "idle";
      StandardInput = "tty";
      StandardOutput = "tty";
      StandardError = "journal"; # Without this errors will spam on screen
      # Without these bootlogs will spam on screen
      TTYReset = true;
      TTYVHangup = true;
      TTYVTDisallocate = true;
    };
    programs.hyprland = {
      enable = true;
      xwayland.enable = true;
    };
    xdg.portal = {
      enable = true;
      config.common.default = [ "hyprland" ];
    };
    hardware.graphics = {
      enable = true;
      enable32Bit = true;
    };
    environment.sessionVariables = {
      NIXOS_OZONE_WL = "1";
    };
  };
}
