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
  # All sessions registered via services.displayManager.sessionPackages
  # (hyprland + niri) merged into one dir, so tuigreet can offer a picker
  # (F3). --remember-user-session keeps the last choice per user.
  sessionDirs = "${config.services.displayManager.sessionData.desktops}/share/wayland-sessions";
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
            command = "${tuigreet} --greeting 'Welcome to NixOS!' --asterisks --time --remember --remember-user-session --sessions ${sessionDirs} --cmd ${session}";
            user = "greeter";
          };
        };
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
      extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
      config.common = {
        default = [
          "hyprland"
          "gtk"
        ];
        # gtk is only here for the file chooser; hyprland handles ScreenCast et al.
        "org.freedesktop.impl.portal.FileChooser" = [ "gtk" ];
      };
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
