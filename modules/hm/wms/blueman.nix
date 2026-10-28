{ config, lib, ... }:
{
  # Blueman's tray icon, next to net-panel on the bar's tray island: pairing
  # prompts, quick reconnect, audio profile switching and connect/disconnect
  # notifications. Bluetooth has no bar icon of its own because of it. Its
  # menu is drawn by the islands bar, as a Qt menu. The system side
  # (blueman-mechanism) is services.blueman in modules/nixos.
  config = lib.mkIf config.modules.hyprland.enable {
    services.blueman-applet = {
      enable = true;
      # Like the bar and net-panel, only under a Hyprland session.
      systemdTargets = [ "hyprland-session.target" ];
    };
    # Clicking the tray icon again closes the device window instead of just
    # focusing it, like net-panel's.
    dconf.settings."org/blueman/plugins/standarditems".toggle-manager-onclick = true;
  };
}
