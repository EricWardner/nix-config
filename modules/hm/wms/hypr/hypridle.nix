{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.modules.hypridle;
  # hypridle itself is compositor-agnostic (ext-idle-notify), but display
  # power is compositor-specific: hyprctl under Hyprland, niri msg under
  # niri (parallel session experiment). NIRI_SOCKET only exists (as a live
  # socket) inside a niri session.
  dpmsAction = pkgs.writeShellApplication {
    name = "dpms-action";
    text = ''
      if [ -S "''${NIRI_SOCKET:-}" ]; then
        case "$1" in
          on) ${pkgs.niri}/bin/niri msg action power-on-monitors ;;
          off) ${pkgs.niri}/bin/niri msg action power-off-monitors ;;
        esac
      else
        hyprctl dispatch dpms "$1"
      fi
    '';
  };
  dpms = "${dpmsAction}/bin/dpms-action";
in
{
  options.modules.hypridle = {
    enable = mkEnableOption "Enable hypridle" // {
      default = true;
    };
    dimTimeout = mkOption {
      type = types.int;
      default = 150;
      description = "Seconds before dimming screen";
    };
    lockTimeout = mkOption {
      type = types.int;
      default = 300;
      description = "Seconds before locking screen";
    };
    screenOffTimeout = mkOption {
      type = types.int;
      default = 600;
      description = "Seconds before turning off screen";
    };
    suspendTimeout = mkOption {
      type = types.int;
      default = 1200;
      description = "Seconds before suspending system";
    };
  };

  config = mkIf cfg.enable {
    services.hypridle = {
      enable = true;
      settings = {
        general = {
          lock_cmd = "pidof hyprlock || hyprlock";
          before_sleep_cmd = "loginctl lock-session";
          after_sleep_cmd = "${dpms} on";
        };

        listener = [
          # Dim screen
          {
            timeout = cfg.dimTimeout;
            on-timeout = "${pkgs.brightnessctl}/bin/brightnessctl -s set 10%";
            on-resume = "${pkgs.brightnessctl}/bin/brightnessctl -r";
          }
          # Lock screen
          {
            timeout = cfg.lockTimeout;
            on-timeout = "loginctl lock-session";
          }
          # Screen off
          {
            timeout = cfg.screenOffTimeout;
            on-timeout = "${dpms} off";
            on-resume = "${dpms} on && ${pkgs.brightnessctl}/bin/brightnessctl -r";
          }
          # Suspend
          {
            timeout = cfg.suspendTimeout;
            on-timeout = "systemctl suspend-then-hibernate";
          }
        ];
      };
    };
  };
}
