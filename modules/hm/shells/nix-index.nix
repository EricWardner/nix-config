{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  nix-locate = "${config.programs.nix-index.package}/bin/nix-locate";
  repo = "${config.home.homeDirectory}/nix-config";

  # Given a config's `options`, the module namespaces that have a module
  # named $NIX_KEEP_NAME (programs.steam, services.syncthing, ...).
  moduleCheck = pkgs.writeText "nix-keep-modules.nix" ''
    options:
    let
      name = builtins.getEnv "NIX_KEEP_NAME";
    in
    builtins.filter (ns: builtins.hasAttr ns options && builtins.hasAttr name options.''${ns}) [
      "programs"
      "services"
      "virtualisation"
    ]
  '';

  # `nix-keep PKG...`: add nixpkgs packages to home.packages in home.nix and
  # switch, the copy-paste line the missing-command hint offers. If NixOS or
  # Home Manager has a module of that name (which can set up groups, udev
  # rules, services or config the bare package lacks), it asks first. Leaves
  # the change for you to review and commit; undoes it if the switch fails.
  nix-keep = pkgs.writeShellApplication {
    name = "nix-keep";
    runtimeInputs = with pkgs; [
      config.programs.git.package
      gnugrep
      gnused
      jq
    ];
    text = ''
      file=${repo}/home/home.nix
      anchor='home.packages = with pkgs; \['
      host=$(</proc/sys/kernel/hostname)
      if [ $# -eq 0 ]; then
        echo "usage: nix-keep PACKAGE..." >&2
        exit 2
      fi

      # "NixOS programs.steam" etc. for each module named after $1. A config
      # that doesn't evaluate is skipped with a warning (errexit would
      # otherwise end nix-keep silently, stderr being hidden).
      modules() {
        local kind attr out
        for kind in NixOS "Home Manager"; do
          if [ "$kind" = NixOS ]; then
            attr="nixosConfigurations.$host.options"
          else
            attr="homeConfigurations.\"$USER@$host\".options"
          fi
          if ! out=$(NIX_KEEP_NAME=$1 nix eval --impure --json "${repo}#$attr" \
            --apply "import ${moduleCheck}" 2>/dev/null); then
            echo "nix-keep: couldn't evaluate the $kind config to look for a $1 module" >&2
            continue
          fi
          jq -r --arg kind "$kind" --arg name "$1" '.[] | "\($kind) \(.).\($name)"' <<<"$out"
        done
      }

      backup=$(mktemp)
      trap 'rm -f "$backup"' EXIT
      cp "$file" "$backup"
      added=0
      for p in "$@"; do
        if ! [[ $p =~ ^[A-Za-z0-9_.+-]+$ ]] || ! nix eval --raw "nixpkgs#$p.name" >/dev/null 2>&1; then
          echo "nix-keep: $p isn't a nixpkgs package" >&2
          exit 1
        fi
        if grep -qxF "    $p" "$file"; then
          echo "nix-keep: $p is already in home.packages"
          continue
        fi
        found=$(modules "''${p##*.}")
        if [ -n "$found" ]; then
          echo "nix-keep: $p has a module, which may set up more than the package:"
          while read -r line; do echo "  $line (enable = true)"; done <<<"$found"
          read -r -p "Add the package anyway? [y/N] " answer || answer=
          if ! [[ $answer =~ ^[Yy] ]]; then
            echo "nix-keep: skipped $p"
            continue
          fi
        fi
        sed -i "0,/$anchor/s//&\n    $p/" "$file"
        added=1
      done
      [ "$added" -eq 1 ] || exit 0
      git -C ${repo} --no-pager diff -- home/home.nix
      if ! nh home switch ${repo} -c "$USER@$host"; then
        cp "$backup" "$file"
        echo "nix-keep: switch failed, home.nix restored" >&2
        exit 1
      fi
    '';
  };
in
{
  # A prebuilt nix-index database (nix-index-database, refreshed weekly and
  # updated with the flake): typing a missing command names the package
  # that has it, `nix-locate bin/foo` finds packages by file, and comma runs
  # one without installing it, e.g. `, cowsay hi`.
  imports = [ inputs.nix-index-database.homeModules.nix-index ];

  programs.nix-index.enable = true;
  programs.nix-index-database.comma.enable = true;
  home.packages = [ nix-keep ];

  # nix-index's own hook suggests `nix-env -iA` and `nix-shell -p`; this one
  # points at comma, and at nix-keep (or home.nix) to keep a program for
  # good. Outside a terminal (pipes, scripts) it is the plain error.
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
      print -u2 "  to keep it: nix-keep ''${pkgs[1]}   (adds it to ${repo}/home/home.nix)"
      return 127
    }
  '';
}
