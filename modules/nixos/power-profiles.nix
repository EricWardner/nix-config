{
  pkgs,
  config,
  lib,
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
    runtimeInputs = [ pkgs.power-profiles-daemon ];
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

      CURRENT=$(powerprofilesctl get)

      case "$BAT_STATUS" in
        Charging|Full|"Not charging")
          [ "$CURRENT" != "performance" ] && powerprofilesctl set performance || true
          ;;
        *)
          if [ "$CAPACITY" -le ${toString cfg.powerSaverThreshold} ]; then
            [ "$CURRENT" != "power-saver" ] && powerprofilesctl set power-saver || true
          else
            [ "$CURRENT" != "balanced" ] && powerprofilesctl set balanced || true
          fi
          ;;
      esac
    '';
  };
in
{
  options.modules.powerProfiles = {
    autoSwitch = mkEnableOption "Automatic power profile switching based on AC/battery state";
    powerSaverThreshold = mkOption {
      type = types.int;
      default = 20;
      description = "Battery percentage at which to switch to power-saver mode.";
    };
  };

  config = mkIf cfg.autoSwitch {
    # Trigger a profile check immediately on any power supply change
    services.udev.extraRules = ''
      SUBSYSTEM=="power_supply", ACTION=="change", TAG+="systemd", ENV{SYSTEMD_WANTS}="power-profile-battery-check.service"
    '';

    # Poll battery percentage every minute for power-saver threshold
    systemd.services."power-profile-battery-check" = {
      description = "Check battery level and adjust power profile";
      after = [ "power-profiles-daemon.service" ];
      requires = [ "power-profiles-daemon.service" ];
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

    # Set correct profile on boot
    systemd.services."power-profile-boot" = {
      description = "Set power profile based on AC state at boot";
      after = [ "power-profiles-daemon.service" ];
      requires = [ "power-profiles-daemon.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${batteryCheckScript}/bin/power-profile-battery-check";
      };
    };
  };
}
