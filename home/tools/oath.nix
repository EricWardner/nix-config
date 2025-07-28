{ pkgs, ... }:
let
  oath = pkgs.writeShellApplication {
    name = "ykmanoath";

    runtimeInputs = with pkgs; [
      fuzzel
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
