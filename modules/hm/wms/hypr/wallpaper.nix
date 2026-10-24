{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    ;
  cfg = config.modules.wallpaper;
in
{
  options.modules.wallpaper = {
    enable = mkEnableOption "the desktop wallpaper" // {
      default = true;
    };
    path = mkOption {
      type = types.path;
      # One picture for the desktop, the lock screen and stylix; hosts set
      # it with modules.themes.wallpaper.
      default = config.stylix.image;
      defaultText = lib.literalExpression "config.stylix.image";
      description = "The wallpaper image, also used by hyprlock.";
    };
  };

  config = mkIf cfg.enable {
    # swaybg hands Hyprland one static image per output through shared
    # memory and then frees its own copy: about 1 MiB once drawn, against
    # hyprpaper 0.8's ~26 MiB plus a GL context (it was rebuilt on
    # hyprtoolkit). Decoding briefly peaks higher, on start and hotplug.
    systemd.user.services.swaybg = {
      Unit = {
        Description = "Desktop wallpaper";
        After = [ "hyprland-session.target" ];
        PartOf = [ "hyprland-session.target" ];
      };
      Service = {
        ExecStart = "${lib.getExe pkgs.swaybg} --mode fill --image ${cfg.path}";
        Restart = "on-failure";
      };
      Install.WantedBy = [ "hyprland-session.target" ];
    };
  };
}
