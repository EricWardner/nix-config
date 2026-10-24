{ pkgs, ... }:
let
  screen-record = pkgs.writeShellApplication {
    name = "screen-record";

    runtimeInputs = with pkgs; [
      wl-screenrec
      ffmpeg
      procps
      libnotify
      slurp
      mpv
    ];

    text = builtins.readFile ./screen-record;
  };
in
{
  home.packages = [ screen-record ];
}
