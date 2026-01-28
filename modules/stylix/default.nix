{
  pkgs,
  config,
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
      type = types.str or types.path;
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
      targets.gnome.enable = false;
      enable = true;
      fonts =
        let
          sfPro = {
            package = inputs.apple-fonts.packages.${pkgs.stdenv.hostPlatform.system}.sf-pro-nerd;
            name = "SFProText Nerd Font";
          };
          mono = {
            package = pkgs.nerd-fonts.caskaydia-cove;
            name = "CaskaydiaCove Nerd Font";
          };
        in
        {
          serif = sfPro;
          sansSerif = sfPro;
          monospace = mono;
          emoji = {
            package = pkgs.nerd-fonts.symbols-only;
            name = "Symbols Nerd Font Mono";
          };

          sizes = {
            desktop = 13;
            applications = 13;
            popups = 11;
          };
        };
      image = cfg.wallpaper;
      base16Scheme = cfg.theme;
      opacity = {
        terminal = 0.65;
      };
    };
  };
}
