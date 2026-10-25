{ config, pkgs, ... }:
let
  # The finished recording's preview and actions
  capture-preview = import ./capture-preview.nix { inherit config pkgs; };

  screen-record = pkgs.writeShellApplication {
    name = "screen-record";

    runtimeInputs = with pkgs; [
      wl-screenrec
      procps
      libnotify
      slurp
      findutils
      capture-preview
    ];

    text = builtins.readFile ./screen-record;
  };
in
{
  home.packages = [ screen-record ];
}
