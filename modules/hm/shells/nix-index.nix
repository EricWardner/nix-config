{
  config,
  inputs,
  lib,
  ...
}:
let
  nix-locate = "${config.programs.nix-index.package}/bin/nix-locate";
in
{
  # A prebuilt nix-index database (nix-index-database, refreshed weekly and
  # updated with the flake): typing a missing command names the package
  # that has it, `nix-locate bin/foo` finds packages by file, and comma runs
  # one without installing it, e.g. `, cowsay hi`.
  imports = [ inputs.nix-index-database.homeModules.nix-index ];

  programs.nix-index.enable = true;
  programs.nix-index-database.comma.enable = true;

  # nix-index's own hook suggests `nix-env -iA` and `nix-shell -p`; this one
  # points at comma, and at home.packages to keep a program for good.
  # Outside a terminal (pipes, scripts) it is the plain error, as before.
  programs.nix-index.enableZshIntegration = false;
  programs.zsh.initContent = lib.mkAfter ''
    command_not_found_handler() {
      if [[ ! -t 1 ]]; then
        print -u2 "zsh: command not found: $1"
        return 127
      fi
      local -a pkgs
      pkgs=(''${(f)"$(${nix-locate} --minimal --no-group --type x --type s \
        --whole-name --at-root "/bin/$1" 2>/dev/null)"})
      # attr.output -> attr, drop nixpkgs' test derivations, and list the
      # package named after the command first
      pkgs=(''${(u)''${pkgs%.*}})
      pkgs=(''${pkgs:#tests.*})
      pkgs=(''${(M)pkgs:#$1} ''${pkgs:#$1})
      if (( ! $#pkgs )); then
        print -u2 "zsh: command not found: $1"
        return 127
      fi
      print -u2 "$1 isn't installed. Run it once with: , $*"
      print -u2 "  provided by: ''${(j:, :)pkgs[1,5]}"
      print -u2 "  to keep it: add ''${pkgs[1]} to home.packages in home/home.nix, then nh home switch"
      return 127
    }
  '';
}
