{ config, pkgs, ... }:
let
  oath = pkgs.writeShellApplication {
    name = "oath";

    runtimeInputs = with pkgs; [
      config.programs.vicinae.package
      wl-clipboard-rs
      libnotify
      yubikey-manager
    ];

    text = builtins.readFile ./oath;
  };
in
{
  home.packages = [ oath ];
}
