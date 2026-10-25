{ config, lib, ... }:
let
  colors = config.lib.stylix.colors;
in
{
  # A dark-glass panel to match the bar's glass island: a translucent base,
  # blurred by Hyprland (the "launcher" layer rule in hypr/lua/rules.lua),
  # with a faint white rim and a soft rounded highlight on the selection.
  programs.fuzzel = {
    enable = true;
    settings = {
      main = {
        # U+1002AB magnifyingglass (SF Symbols), quoted to keep the spaces
        prompt = "\"􀊫  \"";
        placeholder = "Search";
        width = 36; # characters
        lines = 8;
        # Values divisible by 4 for clean 1.25x scaling
        horizontal-pad = 16; # 16 * 1.25 = 20
        vertical-pad = 16; # 16 * 1.25 = 20
        inner-pad = 12; # 12 * 1.25 = 15
        line-height = 32; # 32 * 1.25 = 40
        # no oversized icon when only a few apps match
        image-size-ratio = 0;
        icon-theme = "Papirus-Dark";
        font = lib.mkForce "SF Pro Text:size=13";
      };
      # Replaces stylix's opaque palette; still drawn from the theme.
      colors = lib.mkForce {
        background = "${colors.base00}b3";
        text = "${colors.base05}dd";
        prompt = "${colors.base05}99";
        placeholder = "${colors.base05}66";
        input = "${colors.base05}ff";
        match = "${colors.base0D}ff";
        selection = "${colors.base05}1f";
        selection-text = "${colors.base05}ff";
        selection-match = "${colors.base0D}ff";
        counter = "${colors.base05}66";
        border = "${colors.base05}2e";
      };
      border = {
        width = 1; # a hairline rim; 1.25px at 1.25x
        radius = 16; # 16 * 1.25 = 20
        selection-radius = 10;
      };
    };
  };
}
