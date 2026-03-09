{ config, lib, ... }:
let
  cfg = config.secondfront.terminals;
  inherit (lib) mkIf mkEnableOption;
in
{
  options = {
    secondfront.terminals.ghostty.enable = mkEnableOption "Enable Ghostty terminal" // {
      default = true;
    };
  };
  config = mkIf cfg.ghostty.enable {
    programs.ghostty = {
      enable = true;
      enableZshIntegration = true;
      settings = {
        font-codepoint-map = [
          # ── Nerd Font PUA gaps (only ranges NOT in Cascadia Code NF) ──
          "U+E7C6-U+E8EF=Symbols Nerd Font Mono"
          "U+EBEC-U+EC1E=Symbols Nerd Font Mono"
          "U+ED00-U+EFFF=Symbols Nerd Font Mono"

          # ── Unicode Symbol Blocks (NOT in Cascadia Code NF) ──
          # Cascadia has U+2190-U+2195; fallback the rest of Arrows
          "U+2196-U+21FF=DejaVu Sans Mono"
          "U+2200-U+22FF=DejaVu Sans Mono"
          "U+2300-U+23E8=DejaVu Sans Mono"
          "U+23FB-U+23FF=DejaVu Sans Mono"
          # Cascadia has U+2400-U+2429; fallback the rest of Control Pictures
          "U+242A-U+244A=DejaVu Sans Mono"
          # U+25A0-U+25FF Geometric Shapes: fully covered by Cascadia — no mapping needed
          "U+2600-U+26FF=DejaVu Sans Mono"
          "U+2900-U+297F=DejaVu Sans Mono"
          "U+2B00-U+2BFF=DejaVu Sans Mono"

          # ── Media Controls (U+23E9-U+23FA) → Unifont ──
          # Not in DejaVu Sans Mono or Cascadia; Unifont is the only mono option
          "U+23E9-U+23FA=Unifont"

          # ── Dingbats (U+2700-U+27BF) — matching Kitty's fallback chain ──
          "U+2700=Unifont"
          "U+2701-U+2704,U+2706-U+2709,U+270E-U+2727,U+2729-U+274B,U+274D,U+274F-U+2752,U+2756,U+2758-U+275E,U+2761-U+2775,U+2794,U+2798-U+27AF,U+27B1-U+27BE=DejaVu Sans Mono"
          "U+2705,U+270A-U+270D,U+2728,U+274C,U+274E,U+2753-U+2755,U+2757,U+2795-U+2797,U+27B0,U+27BF=Noto Color Emoji"
          "U+275F-U+2760,U+2776-U+2793=FreeSerif"
        ];
      };
    };
  };
}
