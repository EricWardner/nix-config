{ lib, pkgs, ... }:
{
  # Raycast-style launcher: apps, clipboard history (in place of cliphist),
  # a calculator and file search. The server stays resident (~230 MiB);
  # Super+Space and Super+V (hypr/hyprland.nix) and the bar's nix icon talk
  # to it. Colours and font come from stylix's vicinae target.
  programs.vicinae = {
    enable = true;
    # Changes made in vicinae's settings window persist; the settings below
    # still win over them.
    mutableSettings = true;
    enableFirefoxIntegration = false; # Chrome, not Firefox
    systemd = {
      enable = true;
      # Like waybar, only under a Hyprland session.
      target = "hyprland-session.target";
    };
    settings = {
      # The bar's tray island holds nm-applet and blueman; no vicinae icon.
      tray.enabled = false;
      # Translucent so Hyprland's blur shows through (the "vicinae" layer
      # rule in hypr/lua/rules.lua), matching fuzzel's glass panel.
      launcher_window.opacity = lib.mkForce 0.85;
      # Start each app in its own transient scope. A plain child of the
      # server stays in vicinae.service's cgroup, along with every app
      # opened from it.
      providers.applications.preferences.launchPrefix = "${pkgs.systemd}/bin/systemd-run --user --scope --collect --quiet --";
    };
  };
}
