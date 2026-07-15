{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkIf;
in
{
  config = mkIf config.modules.hyprland.enable {
    services.mako.enable = true;
    services.mako.settings = {
      "default-timeout" = 5000;
      border-radius = 12;
      padding = "12";
      margin = "12";
      anchor = "top-right";
      border-size = 2;

      "app-name=yubikey-touch-detector" = {
        "icon-path" = "${config.home.homeDirectory}/.nix-profile/share/icons/hicolor";
        "max-icon-size" = 128;
        "default-timeout" = 0;
        anchor = "center";
        layer = "overlay";
        on-notify = "exec pw-play ${pkgs.sound-theme-freedesktop}/share/sounds/freedesktop/stereo/dialog-warning.oga";
      };
    };
  };
}
