{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (lib)
    mkIf
    mkMerge
    mkForce
    mkOption
    mkEnableOption
    types
    getExe'
    escapeShellArg
    ;
  cfg = config.modules.tether;
  # tetherd's port for the phone's app (TETHER_PORT would move it)
  port = "5134";
  # Says the network side is open, and on which devices: the script
  # below writes it, and Avahi only starts while it is there
  open = "/run/tether-wifi";
  systemctl = getExe' config.systemd.package "systemctl";
in
{
  options.modules.tether = {
    enable = mkEnableOption ''
      Tether, an iPhone's messages (SMS and iMessage) and notifications over
      Bluetooth. Pair with `tether-gtk` or `tether --bt-pair`, then turn on
      "Show Message Notifications" and "Sync Contacts" for this computer in
      the iPhone's Bluetooth settings
    '';

    wifi.enable = mkEnableOption ''
      Tether's network side (the clipboard, files and links shared with the
      iPhone's Tether app), on the networks marked for it and no others.
      Mark one by giving its NetworkManager connection the zone below:
      `nmcli connection modify NAME connection.zone home`, then reconnect
      or `systemctl restart tether-wifi`
    '';

    wifi.zone = mkOption {
      type = types.str;
      default = "home";
      description = ''
        The NetworkManager zone (`connection.zone`) of a network Tether may
        be reached on. NetworkManager only keeps it, for firewalld, which
        isn't used here: it is a label, set on the machine, so no network
        is named in this configuration.
      '';
    };
  };

  config = mkMerge [
    (mkIf cfg.enable {
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
    })

    (mkIf (cfg.enable && cfg.wifi.enable) {
      assertions = [
        {
          assertion =
            config.networking.networkmanager.enable
            && config.networking.firewall.enable
            && !config.networking.nftables.enable;
          message = "modules.tether.wifi marks its networks in NetworkManager and opens tetherd's port in the iptables firewall: it needs both, and has no nftables rules";
        }
      ];

      # tetherd listens on every network; the firewall is what keeps the
      # others out. A chain of its own, checked before the firewall refuses
      # a packet, is empty (so closed) each time the firewall is set up, and
      # tether-wifi fills it for the marked networks' devices.
      networking.firewall.extraCommands = ''
        ip46tables -N tether-wifi 2>/dev/null || true
        ip46tables -F tether-wifi
        ip46tables -A nixos-fw -j tether-wifi
        ${systemctl} --no-block try-restart tether-wifi.service || true
      '';
      networking.firewall.extraStopCommands = ''
        ip46tables -F tether-wifi 2>/dev/null || true
      '';

      # The phone's app finds tetherd by mDNS, so Avahi answers for it, and
      # for nothing else about the machine. It runs only on a marked network:
      # started by tether-wifi and by nothing else (not at boot, and a
      # program asking for it over D-Bus or its socket is refused while the
      # network side is closed).
      services.avahi = {
        enable = true;
        openFirewall = false;
        settings.publish = {
          disable-publishing = false;
          disable-user-service-publishing = false;
          publish-addresses = true;
          publish-hinfo = false;
          publish-workstation = false;
        };
      };
      systemd.services.avahi-daemon = {
        wantedBy = mkForce [ ];
        unitConfig.ConditionPathExists = open;
      };
      systemd.sockets.avahi-daemon.wantedBy = mkForce [ ];

      # Opens the network side on the devices of the active connections
      # whose zone is the one marked, and closes it when there are none. It
      # is run again whenever that may have changed: by the firewall above,
      # and by NetworkManager below as a connection comes or goes.
      systemd.services.tether-wifi = {
        description = "Tether's network side, on the networks marked for it";
        after = [
          "firewall.service"
          "NetworkManager.service"
        ];
        wantedBy = [ "multi-user.target" ];
        path = [
          config.networking.firewall.package
          pkgs.networkmanager
          pkgs.coreutils
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          devices=$(nmcli -t -f UUID,DEVICE connection show --active 2>/dev/null |
            while IFS=: read -r uuid device; do
              zone=$(nmcli -g connection.zone connection show "$uuid" 2>/dev/null || true)
              if [ -n "$device" ] && [ "$zone" = ${escapeShellArg cfg.wifi.zone} ]; then
                echo "$device"
              fi
            done)
          for table in iptables ip6tables; do
            "$table" -w -F tether-wifi
            for device in $devices; do
              "$table" -w -A tether-wifi -i "$device" -p tcp --dport ${port} -j nixos-fw-accept
              "$table" -w -A tether-wifi -i "$device" -p udp --dport 5353 -j nixos-fw-accept
            done
          done
          if [ -n "$devices" ]; then
            echo "$devices" >${open}
            ${systemctl} start avahi-daemon.service
          else
            rm -f ${open}
            ${systemctl} stop avahi-daemon.socket avahi-daemon.service
          fi
        '';
      };
      networking.networkmanager.dispatcherScripts = [
        {
          type = "basic";
          source = pkgs.writeShellScript "tether-wifi" ''
            case "$2" in
              up | down)
                ${systemctl} --no-block restart tether-wifi.service
                ;;
            esac
          '';
        }
      ];
    })
  ];
}
