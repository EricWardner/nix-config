{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (lib) mkIf mkEnableOption getExe';
  cfg = config.modules.tether;
in
{
  options.modules.tether.enable = mkEnableOption ''
    Tether, an iPhone's messages (SMS and iMessage) and notifications over
    Bluetooth. Pair with `tether-gtk` or `tether --bt-pair`, then turn on
    "Show Message Notifications" and "Sync Contacts" for this computer in
    the iPhone's Bluetooth settings
  '';

  config = mkIf cfg.enable {
    # tetherd, the tether CLI and tether-gtk
    environment.systemPackages = [ pkgs.tether ];

    # Notifications need BlueZ's experimental bearer API, and it has to be
    # on before the phone is paired: a bond made without it has no LE half.
    hardware.bluetooth.settings.General.Experimental = true;

    # iOS offers messages and contacts only to a device whose class is A/V
    # hands-free (major 4, minor 8), and bluetoothd puts its own class back
    # every time it starts.
    systemd.services.tether-btclass = {
      description = "Bluetooth class of device: hands-free, for Tether";
      after = [ "bluetooth.service" ];
      partOf = [ "bluetooth.service" ];
      wantedBy = [ "bluetooth.service" ];
      path = [
        pkgs.bluez
        pkgs.coreutils
        pkgs.gnugrep
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = 60;
      };
      # The controller can take a while to come up, and isn't always hci0:
      # one that fails its firmware handshake comes back under the next
      # index. btmgmt polls its stdin before it runs anything and can't
      # poll /dev/null, hence the pipe. A try that fails (the controller
      # still coming up, bluetoothd setting its own class) is tried again:
      # the script runs under `set -e`, which would end it there.
      script = ''
        for _ in $(seq 30); do
          hci=$(ls /sys/class/bluetooth 2>/dev/null | head -n1)
          if [ -n "$hci" ]; then
            echo | btmgmt --index "$hci" class 4 8 >/dev/null 2>&1 || true
            if echo | btmgmt --index "$hci" info 2>/dev/null | grep -q 'class 0x..0408'; then
              exit 0
            fi
          fi
          sleep 1
        done
        exit 1
      '';
    };

    # WirePlumber's stock roles make this machine a Bluetooth speaker and
    # hands-free unit, so a linked iPhone plays its music, sounds and calls
    # here. These are the roles headphones use, without the ones a phone
    # connects to. Leaving hfp_hf to BlueZ is also what Tether's call
    # control needs.
    services.pipewire.wireplumber.extraConfig."51-tether-phone-audio" = {
      "monitor.bluez.properties"."bluez5.roles" = [
        "a2dp_source"
        "bap_source"
        "hfp_ag"
      ];
    };

    systemd.user.services.tetherd = {
      description = "Tether, an iPhone's messages and notifications";
      after = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      # tetherd runs btmgmt and bluetoothctl, and its own tether-gtk and
      # tether-dialog by name: a notification's Reply opens the app
      path = [
        pkgs.bluez
        pkgs.tether
      ];
      # One that keeps failing stops, and says so, as the package's own unit
      # does: the default limit is never reached at a restart every 3 s
      startLimitIntervalSec = 60;
      startLimitBurst = 3;
      serviceConfig = {
        # `tether` and tether-gtk start a tetherd of their own when none is
        # running. It holds the runtime lock, and this one would exit on it.
        ExecStartPre = "-${getExe' pkgs.procps "pkill"} -f ^tetherd";
        ExecStart = getExe' pkgs.tether "tetherd";
        Restart = "on-failure";
        RestartSec = 3;
        # It keeps its own log in $XDG_STATE_HOME/tether; why it would not
        # start goes to the journal
        StandardOutput = "null";
        StandardError = "journal";
      };
    };
  };
}
