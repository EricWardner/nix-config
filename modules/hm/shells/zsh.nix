{
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.modules.shells;
  inherit (lib) mkIf mkEnableOption;
in
{
  options = {
    modules.shells.zsh.enable = mkEnableOption "Enable zsh" // {
      default = true;
    };
  };
  config = mkIf cfg.zsh.enable {
    programs.zsh = {
      dotDir = "${config.xdg.configHome}/zsh";
      plugins = [
        {
          file = "p10k.zsh";
          src = ./.;
          name = "powerlevel10k-config";
        }
        {
          name = "zsh-powerlevel10k";
          src = "${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/";
          file = "powerlevel10k.zsh-theme";
        }
      ];
      enable = true;
      enableCompletion = true;
      autosuggestion.enable = true;
      autocd = true;
      syntaxHighlighting.enable = true;
      history = {
        append = true;
      };
      shellAliases =
        let
          flakeDir = "$HOME/nix-config";
        in
        {
          rb = "nh os switch ${flakeDir}";
          rbh = "nh home switch ${flakeDir}";
          upd = "nh home switch ${flakeDir} --update";
          gct = "git commit";
          open = "xdg-open";
          nosleep = ''systemd-inhibit --what=sleep:idle:handle-lid-switch:handle-power-key --who="$USER" --why="no sleep" --mode=block sleep infinity'';
        };
      historySubstringSearch.enable = true;
      oh-my-zsh = {
        enable = true;
        plugins = [
          "git"
          "helm"
          "kubectl"
          "docker"
          "docker-compose"
          "alias-finder"
          "z"
        ];
      };
    };

    # thefuck's successor (thefuck is gone from nixpkgs: unmaintained, and
    # broken on current Python). After a command fails, `fuck` runs it again
    # to read the error, suggests a fix and runs that on Enter; Ctrl+X
    # Ctrl+X fixes the line being typed instead. --nocnf: mistyped commands
    # stay with the nix-index handler (nix-index.nix).
    programs.pay-respects = {
      enable = true;
      options = [
        "--alias"
        "fuck"
        "--nocnf"
      ];
    };
    # When no rule matches it would offer to send the command and its error
    # to a hosted AI service. Off: commands here can hold work details.
    xdg.configFile."pay-respects/config.toml".text = ''
      [module.request-ai]
      enabled = false
    '';
  };
}
