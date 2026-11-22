# This repository's own packages, as members of pkgs: the flake applies it
# with its other overlays, so modules use pkgs.bar-tools and the rest
# without knowing where their sources live.
final: prev: {
  # Push-to-talk (pttd) and the status watchers the islands bar reads
  bar-tools = final.callPackage ./bar-tools { };
  # A finished recording's or screenshot's preview window
  capture-preview = final.callPackage ./capture-preview { };
  # The Gather logo, a one-glyph font at U+FFF00
  gather-symbol = final.callPackage ./gather-symbol { };
  # NetworkManager's secret agent, BlueZ's pairing agent and gnome-keyring's
  # prompter, for the islands shell
  islands-agent = final.callPackage ./islands-agent { };
  # Tether (modules/nixos/tether.nix), ahead of nixpkgs, whose automatic
  # updates stopped at 0.2.37: later versions need the three libraries added
  # here (a terminal front end, and the iPhone's camera as a PipeWire
  # source) and name the JSON library's source differently. It steps aside
  # once nixpkgs has this version or a later one, and says so at every
  # rebuild from then on, until it is taken out.
  tether =
    if final.lib.versionOlder prev.tether.version "0.3.6" then
      prev.tether.overrideAttrs (
        finalAttrs: old: {
          version = "0.3.6";
          src = final.fetchFromGitHub {
            owner = "zackb";
            repo = "tether";
            tag = "v${finalAttrs.version}";
            hash = "sha256-vdAjOi9e4L7M5RfYDuyl5ipbiEK+NU0MR30khCOucLo=";
          };
          buildInputs = old.buildInputs ++ [
            final.ffmpeg
            final.ncurses
            final.pipewire
          ];
          cmakeFlags = old.cmakeFlags ++ [
            (final.lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_NLOHMANN_JSON" "${final.nlohmann_json.src}")
          ];
        }
      )
    else
      final.lib.warn "nixpkgs now has Tether ${prev.tether.version}: the 0.3.6 override in pkgs/overlay.nix is no longer used and can be removed" prev.tether;
}
