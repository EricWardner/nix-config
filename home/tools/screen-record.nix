{ config, pkgs, ... }:
let
  inherit (config.lib.stylix) colors;

  # The finished recording's preview and actions (pkgs/capture-preview),
  # themed like net-panel: the palette and the desktop font over its
  # built-in stylesheet.
  capturePreview = pkgs.callPackage ../../pkgs/capture-preview { };
  previewTheme = pkgs.writeText "capture-preview-theme.css" ''
    @define-color cp_fg #${colors.base05};
    @define-color cp_bg alpha(#${colors.base00}, 0.78);
    @define-color cp_accent #${colors.base0D};
    @define-color cp_on_accent #${colors.base00};
    @define-color cp_danger #${colors.base08};

    .panel {
      font-family: "${config.stylix.fonts.sansSerif.name}";
    }
  '';
  capture-preview = pkgs.writeShellScriptBin "capture-preview" ''
    exec ${capturePreview}/bin/capture-preview --css ${previewTheme} "$@"
  '';

  screen-record = pkgs.writeShellApplication {
    name = "screen-record";

    runtimeInputs = with pkgs; [
      wl-screenrec
      ffmpeg
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
