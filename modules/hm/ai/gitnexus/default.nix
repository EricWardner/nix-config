{
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.modules.ai.gitnexus;
  hookEnv.GITNEXUS_HOOK_CLI_PATH = "${config.home.profileDirectory}/lib/node_modules/gitnexus/dist/cli/index.js";
  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    ;
in
{
  options.modules.ai.gitnexus = {
    enable = mkEnableOption "Enable GitNexus - code knowledge graph creator with MCP integration";

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ./package.nix { };
      description = "The gitnexus package to install";
    };

    analyzeExtraFlags = mkOption {
      type = types.listOf types.str;
      default = [ "--skip-agents-md" ];
      description = ''
        Flags appended to every `gitnexus analyze` invocation. The default
        keeps analyze from regenerating the gitnexus section in CLAUDE.md /
        AGENTS.md, which would clobber local customizations of that block
        (and churn the volatile symbol counts).
      '';
    };
  };

  config = mkIf cfg.enable {
    home.packages = [
      # Wrapper first so it wins the bin/gitnexus conflict in symlinkJoin;
      # non-analyze subcommands (mcp, query, ...) pass through untouched
      (pkgs.symlinkJoin {
        name = "gitnexus";
        paths = [
          (pkgs.writeShellScriptBin "gitnexus" ''
            if [ "''${1:-}" = "analyze" ]; then
              exec ${cfg.package}/bin/gitnexus "$@" ${lib.escapeShellArgs cfg.analyzeExtraFlags}
            fi
            exec ${cfg.package}/bin/gitnexus "$@"
          '')
          cfg.package
        ];
      })
      # The Claude Code hooks installed by `gitnexus setup` run `node` by name,
      # so a node must be on PATH; the package above only bundles one internally.
      pkgs.nodejs
    ];

    # `gitnexus setup` bakes the CLI's /nix/store path into the hook. Once that
    # path is garbage-collected the hook silently falls back to `npx -y
    # gitnexus`, a second, unmanaged copy. The hook checks this variable first,
    # and the profile path always points at the current package. Set for
    # shells and for the systemd user manager, so Claude Code started from a
    # launcher or a terminal it spawned has it too.
    home.sessionVariables = { inherit (hookEnv) GITNEXUS_HOOK_CLI_PATH; };
    systemd.user.sessionVariables = { inherit (hookEnv) GITNEXUS_HOOK_CLI_PATH; };
  };
}
