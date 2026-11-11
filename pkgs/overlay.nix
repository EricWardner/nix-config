# This repository's own packages, as members of pkgs: the flake applies it
# with its other overlays, so modules use pkgs.bar-tools and the rest
# without knowing where their sources live.
final: _prev: {
  # Push-to-talk (pttd) and the status watchers the islands bar reads
  bar-tools = final.callPackage ./bar-tools { };
  # A finished recording's or screenshot's preview window
  capture-preview = final.callPackage ./capture-preview { };
  # The Gather logo, a one-glyph font at U+FFF00
  gather-symbol = final.callPackage ./gather-symbol { };
  # NetworkManager's secret agent, BlueZ's pairing agent and gnome-keyring's
  # prompter, for the islands shell
  islands-agent = final.callPackage ./islands-agent { };
}
