{
  pkgs,
  config,
  lib,
  ...
}:
let
  inherit (lib) mkIf mkEnableOption;
  cfg = config.modules.niri;
in
{
  options = {
    modules.niri.enable = mkEnableOption "Enable niri compositor (parallel session experiment)" // {
      default = true;
    };
  };
  config = mkIf cfg.enable {
    # The nixpkgs module registers the wayland session, sets up niri-scoped
    # portals (xdg.portal.config.niri -> gnome/gtk), and ships the systemd
    # user units. Portal config is keyed by XDG_CURRENT_DESKTOP, so it
    # coexists with the hyprland portal setup.
    programs.niri.enable = true;

    # niri has no built-in XWayland; it spawns xwayland-satellite on demand.
    # The HM config also pins the path explicitly in config.kdl.
    environment.systemPackages = [ pkgs.xwayland-satellite ];
  };
}
