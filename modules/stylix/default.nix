{
  pkgs,
  config,
  options,
  lib,
  inputs,
  ...
}:
let
  cfg = config.modules.themes;
  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    ;
in
{
  options = {
    modules.themes.enable = mkEnableOption "Enable Stylix theme" // {
      default = true;
    };
    modules.themes.theme = mkOption {
      type = types.either types.str types.path;
      default = "${pkgs.base16-schemes}/share/themes/material-darker.yaml";
      example = ''
        ./assets/themes/grail.yaml
        $${pkgs.base16-schemes}/share/themes/material-darker.yaml
      '';
    };
    modules.themes.wallpaper = mkOption {
      type = types.path;
      default = ./assets/walls/Tiberius.png;
      example = ''
        ./path/to/wallpaper.png
        ~/Wallpapers/Eric.png
      '';
    };
  };
  config = mkIf cfg.enable {
    stylix = {
      enable = true;

      # Stylix's chromium target writes a machine-wide managed policy
      # (BrowserThemeColor -> /etc/opt/chrome/policies/managed/extra.json).
      # That makes Chrome report "managed by your administrator" and locks the
      # theme color across all profiles, so profiles cannot be themed apart.
      # This module is shared by the NixOS and home-manager module sets, and
      # stylix only defines a chromium target for NixOS, so guard on it.
      targets = lib.optionalAttrs (options.stylix.targets ? chromium) {
        chromium.enable = false;
      };

      fonts =
        let
          sfPro = {
            # Plain SF Pro, unpacked from Apple's image in seconds. Nerd Font
            # icons come from Symbols Nerd Font by fontconfig fallback (the
            # HM fontconfig rules in modules/hm), and the Gather logo from
            # pkgs/gather-symbol (waybar), where a Nerd-patched build with the
            # logo patched in took ~13 minutes on every nixpkgs update.
            package = inputs.apple-fonts.packages.${pkgs.stdenv.hostPlatform.system}.sf-pro;
            # SF Pro Text is Apple's optical variant hinted for small UI sizes
            # (vs the variable "SF Pro"/Display family, tuned for large headings).
            name = "SF Pro Text";
          };
          mono = {
            package = pkgs.cascadia-code;
            name = "Cascadia Code NF";
          };
        in
        {
          serif = sfPro;
          sansSerif = sfPro;
          monospace = mono;
          # emoji: stylix's default, Noto Color Emoji

          sizes = {
            desktop = 9;
            applications = 9;
            popups = 9;
            terminal = 12;
          };
        };
      image = cfg.wallpaper;
      base16Scheme = cfg.theme;
      opacity = {
        terminal = 0.90;
      };
    };
  };
}
