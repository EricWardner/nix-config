{
  pkgs,
  config,
  lib,
  user,
  ...
}:
let
  inherit (lib)
    mkIf
    mkOption
    mkEnableOption
    types
    ;
  cfg = config.modules.powerProfiles;

  batteryCheckScript = pkgs.writeShellApplication {
    name = "power-profile-battery-check";
    runtimeInputs = [
      pkgs.power-profiles-daemon
      pkgs.libnotify
      pkgs.util-linux
    ];
    text = ''
      # Use battery status as source of truth instead of AC online,
      # since some USB-C sources (e.g. monitor KVM) report AC online
      # but don't provide enough power to actually charge.
      BAT_STATUS="Discharging"
      CAPACITY=100

      if [ -f /sys/class/power_supply/BAT1/status ]; then
        BAT_STATUS=$(cat /sys/class/power_supply/BAT1/status)
        CAPACITY=$(cat /sys/class/power_supply/BAT1/capacity)
      elif [ -f /sys/class/power_supply/BAT0/status ]; then
        BAT_STATUS=$(cat /sys/class/power_supply/BAT0/status)
        CAPACITY=$(cat /sys/class/power_supply/BAT0/capacity)
      fi

      AC_ONLINE=0
      for supply in /sys/class/power_supply/*; do
        if [ "$(cat "$supply/type")" = Mains ] && [ "$(cat "$supply/online")" = 1 ]; then
          AC_ONLINE=1
        fi
      done

      case "$BAT_STATUS" in
        Charging|Full|"Not charging") WANT=performance WHY="Plugged in" ;;
        *)
          # A full battery on a charger reports Discharging (the EC lets it
          # drift), so a source that can't keep up only counts once it's
          # pulled the battery below 95%
          if [ "$AC_ONLINE" = 1 ] && [ "$CAPACITY" -ge 95 ]; then
            WANT=performance WHY="Plugged in"
          elif [ "$CAPACITY" -le ${toString cfg.powerSaverThreshold} ]; then
            WANT=power-saver WHY="Battery at $CAPACITY%"
          elif [ "$AC_ONLINE" = 1 ]; then
            WANT=balanced WHY="The charger isn't keeping up"
          else
            WANT=balanced WHY="On battery"
          fi
          ;;
      esac

      # Only when that changes (plugged in, unplugged, the battery running
      # low): a profile picked by hand stays until then
      LAST=$(cat /run/power-profile-auto 2>/dev/null || true)
      [ "$WANT" = "$LAST" ] && exit 0
      echo "$WANT" >/run/power-profile-auto
      if [ "$(powerprofilesctl get)" != "$WANT" ] && powerprofilesctl set "$WANT"; then
        case "$WANT" in
          performance) TITLE=Performance ;;
          balanced) TITLE=Balanced ;;
          *) TITLE="Power saver" ;;
        esac
        # This runs as root; the notification belongs on the user's session bus
        uid=$(id -u ${user.username})
        setpriv --reuid="$uid" --regid="$(id -g ${user.username})" --init-groups \
          env DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
          notify-send --transient --app-name=Power "$TITLE" "$WHY" || true
      fi
    '';
  };
in
{
  options.modules.powerProfiles = {
    autoSwitch = mkEnableOption "Automatic power profile switching based on AC/battery state";
    powerSaverThreshold = mkOption {
      type = types.int;
      default = 30;
      description = "Battery percentage at which to switch to power-saver mode.";
    };
  };

  config = mkIf cfg.autoSwitch {
    # Trigger a profile check as soon as a charger comes or goes. The
    # battery itself reports a change about every second, so it's left to
    # the minutely timer. SYSTEMD_WANTS only acts when a device unit first
    # becomes active (systemd.device(5)), so it never fires on change events
    # for already-active power supplies — start the service directly instead.
    services.udev.extraRules = ''
      SUBSYSTEM=="power_supply", ATTR{type}=="Mains|USB", ACTION=="change", RUN+="${pkgs.systemd}/bin/systemctl start --no-block power-profile-battery-check.service"
    '';

    # Poll battery percentage every minute for power-saver threshold, and
    # check once at boot. power-profiles-daemon (0.30+) starts after
    # multi-user.target, for graphical.target, so this hangs off the same
    # target: from multi-user.target it was an ordering cycle.
    systemd.services."power-profile-battery-check" = {
      description = "Check battery level and adjust power profile";
      after = [ "power-profiles-daemon.service" ];
      requires = [ "power-profiles-daemon.service" ];
      wantedBy = [ "graphical.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${batteryCheckScript}/bin/power-profile-battery-check";
      };
    };

    systemd.timers."power-profile-battery-check" = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "minutely";
        Unit = "power-profile-battery-check.service";
      };
    };
  };
}
