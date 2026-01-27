{
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.modules.editors;
  inherit (lib) mkIf mkEnableOption;
in
{
  options.modules.editors.vscode.enable = mkEnableOption "Enable VSCode" // {
    default = false;
  };

  config = mkIf cfg.vscode.enable {
    stylix.targets.vscode.enable = false;

    programs.vscode = {
      enable = true;
      package = pkgs.vscode.fhsWithPackages (
        ps: with ps; [
          nodejs_22
          rustup
          zlib
          openssl.dev
          pkg-config
        ]
      );
      profiles.default = {
        enableUpdateCheck = false;
        enableExtensionUpdateCheck = false;
      };
    };
  };
}
