{ config, lib, ... }:
{
  # Blueman's tray icon, next to net-panel on the bar's tray island: pairing
  # prompts, quick reconnect, audio profile switching and connect/disconnect
  # notifications. Bluetooth has no waybar module of its own because of it.
  # Its menu is drawn by waybar (GTK3), so the submenus ("Reconnect to…",
  # "Audio Profiles") have GTK3's diagonal-hover quirk. The system side
  # (blueman-mechanism) is services.blueman in modules/nixos.
  config = lib.mkIf config.modules.hyprland.enable {
    services.blueman-applet = {
      enable = true;
      # Like waybar and net-panel, only under a Hyprland session.
      systemdTargets = [ "hyprland-session.target" ];
    };
  };
}
