#!/usr/bin/env bash
# Render and verify both hosts without activating Home Manager or a compositor.
set -euo pipefail

repo_root=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
check_root=$(mktemp -d)
trap 'rm -rf "$check_root"' EXIT
hyprland_bin=${HYPRLAND_BIN:-Hyprland}

profiles=("$@")
if ((${#profiles[@]} == 0)); then
  profiles=(ewardner@framework ewardner@tiberius)
fi

for profile in "${profiles[@]}"; do
  config_home="$check_root/$profile"
  mkdir -p "$config_home/hypr"
  # A path flake also includes newly created Lua files before they are staged.
  # shellcheck disable=SC2016 # The interpolation in --apply belongs to Nix.
  nix eval --no-write-lock-file --json \
    "path:$repo_root#homeConfigurations.\"$profile\".config.xdg.configFile" \
    --apply 'files: builtins.mapAttrs (_: f: { inherit (f) text source; })
      (builtins.listToAttrs (map (name: { inherit name; value = files.${name}; })
        (builtins.filter (n: builtins.match "hypr/.*[.]lua" n != null)
          (builtins.attrNames files))))' >"$config_home/files.json"

  while IFS= read -r name; do
    mkdir -p "$(dirname "$config_home/$name")"
    if jq -e --arg name "$name" '(.[$name].text // "") != ""' "$config_home/files.json" >/dev/null; then
      jq -rj --arg name "$name" '.[$name].text' "$config_home/files.json" >"$config_home/$name"
    else
      source_file=$(jq -r --arg name "$name" '.[$name].source' "$config_home/files.json")
      cp "$source_file" "$config_home/$name"
    fi
  done < <(jq -r 'keys[]' "$config_home/files.json")

  printf 'Verifying %s\n' "$profile"
  XDG_CONFIG_HOME="$config_home" "$hyprland_bin" --verify-config \
    -c "$config_home/hypr/hyprland.lua" | tee "$config_home/verification.log"
  rg -q '^config ok$' "$config_home/verification.log"
done
