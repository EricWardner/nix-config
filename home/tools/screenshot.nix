{ config, pkgs, ... }:
let
  # The shot's preview and actions, shared with screen-record
  capture-preview = import ./capture-preview.nix { inherit config pkgs; };

  screenshot = pkgs.writeShellApplication {
    name = "screenshot";

    runtimeInputs = with pkgs; [
      grimblast
      hyprpicker
      wl-clipboard-rs
      libnotify
      findutils
      qrtool
      # English is all it reads; every language would be ~650 MB
      (tesseract.override { enableLanguages = [ "eng" ]; })
      capture-preview
    ];

    text = builtins.readFile ./screenshot;
  };
in
{
  home.packages = [ screenshot ];

  # Annotating, from the preview's Annotate or run by hand. Enter copies the
  # result and closes; Ctrl+S saves it (over a saved screenshot, or a new
  # file in ~/Pictures/Screenshots for one not saved yet).
  programs.satty = {
    enable = true;
    settings = {
      general = {
        copy-command = "${pkgs.wl-clipboard-rs}/bin/wl-copy";
        actions-on-enter = [
          "save-to-clipboard"
          "exit"
        ];
        output-filename = "~/Pictures/Screenshots/%m-%d-%Y-%H-%M-%S.png";
        initial-tool = "arrow";
        no-window-decoration = true;
        # Named for Hyprland's float rule (rules.lua)
        app-id = "com.gabm.satty";
      };
      font = {
        family = config.stylix.fonts.sansSerif.name;
        style = "Regular";
      };
    };
  };
}
