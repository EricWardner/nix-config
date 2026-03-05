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
        gtk-single-instance = true;
      };
    };
  };
}
