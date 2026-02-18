{ config, lib, ... }:
let
  inherit (lib) mkIf;
in
{
  config = mkIf config.modules.hyprland.enable {
    services.mako.enable = true;
    services.mako.settings = {
      "default-timeout" = 5000;

      "app-name=yubikey-touch-detector" = {
        "icon-path" = "${config.home.homeDirectory}/.nix-profile/share/icons/hicolor";
        "max-icon-size" = 128;
        "default-timeout" = 0;
        anchor = "center";
        layer = "overlay";
      };
    };
  };
}
