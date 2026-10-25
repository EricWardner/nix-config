# The preview a finished recording or screenshot opens in (pkgs/capture-preview),
# themed like net-panel: the palette and the desktop font over its built-in
# stylesheet. A function rather than a module, so screen-record and screenshot
# share the one wrapper.
{ config, pkgs }:
let
  inherit (config.lib.stylix) colors;

  capturePreview = pkgs.callPackage ../../pkgs/capture-preview { };
  theme = pkgs.writeText "capture-preview-theme.css" ''
    @define-color cp_fg #${colors.base05};
    @define-color cp_bg alpha(#${colors.base00}, 0.78);
    @define-color cp_accent #${colors.base0D};
    @define-color cp_on_accent #${colors.base00};
    @define-color cp_danger #${colors.base08};

    .panel {
      font-family: "${config.stylix.fonts.sansSerif.name}";
    }
  '';
in
pkgs.writeShellScriptBin "capture-preview" ''
  exec ${capturePreview}/bin/capture-preview --css ${theme} "$@"
''
