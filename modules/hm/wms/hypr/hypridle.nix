{ config, lib, ... }:
with lib;
let
  cfg = config.modules.hypridle;
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
          after_sleep_cmd = "hyprctl dispatch dpms on";
        };

        listener = [
          # Dim screen
          {
            timeout = cfg.dimTimeout;
            on-timeout = "brightnessctl -s set 10";
            on-resume = "brightnessctl -r";
          }
          # Lock screen
          {
            timeout = cfg.lockTimeout;
            on-timeout = "loginctl lock-session";
          }
          # Screen off
          {
            timeout = cfg.screenOffTimeout;
            on-timeout = "hyprctl dispatch dpms off";
            on-resume = "hyprctl dispatch dpms on";
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
