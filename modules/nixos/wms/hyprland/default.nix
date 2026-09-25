{
  pkgs,
  config,
  lib,
  ...
}:
let
  inherit (lib) mkIf mkEnableOption;
  cfg = config.modules.hyprland;
in
{
  options = {
    modules.hyprland.enable = mkEnableOption "Enable hyprland module" // {
      default = true;
    };
  };
  config = mkIf cfg.enable {
    # The login greeter lives in ../greeter; Hyprland's
    # session file is picked up there via displayManager.sessionPackages.
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
