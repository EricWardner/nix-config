{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (lib) mkIf mkEnableOption;
  cfg = config.modules.hyprland.waybar;
  inherit (config.lib.stylix) colors;

  # Waybar 0.15's workspace buttons still send legacy Hyprland dispatchers.
  # Backport upstream's Lua IPC support, including config-provider detection.
  # Keep the package installed by HM and the service executable in sync.
  waybarPackage = pkgs.waybar.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./hyprland-lua-ipc.patch ];
  });

  # The push-to-talk daemon and the bar's event-driven status watchers
  # (pkgs/bar-tools). Each custom module below runs a watcher as a
  # long-running exec that prints a line only when its state changes and
  # otherwise sleeps, so the bar polls nothing.
  barTools = pkgs.callPackage ../../../../pkgs/bar-tools { };
  wpctl = "${pkgs.wireplumber}/bin/wpctl";
  pavucontrol = "${pkgs.pavucontrol}/bin/pavucontrol";
  # webcam-watch sees the cameras come and go through inotify, so the
  # toggle needs no refresh signal.
  webcamToggle = "sudo /run/current-system/sw/bin/webcam-toggle toggle";

  # waybar doesn't rebuild its bars when the set of outputs changes, so on a
  # monitor hotplug we restart the waybar user service. Listens to Hyprland's
  # event socket; systemd keeps this watcher alive (Restart=always).
  waybarMonitorWatch = pkgs.writeShellApplication {
    name = "waybar-monitor-watch";
    runtimeInputs = with pkgs; [
      socat
      systemd
      coreutils
    ];
    text = ''
      # HYPRLAND_INSTANCE_SIGNATURE isn't always imported into the systemd
      # user environment (and set -u would kill us); fall back to discovering
      # the instance dir under $XDG_RUNTIME_DIR/hypr.
      SOCK=""
      for _ in $(seq 1 100); do
        if [ -n "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
          SOCK="''${XDG_RUNTIME_DIR}/hypr/''${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"
        else
          SOCK=$(find "''${XDG_RUNTIME_DIR}/hypr" -maxdepth 2 -name .socket2.sock 2>/dev/null | head -n1) || true
        fi
        [ -S "$SOCK" ] && break
        sleep 0.1
      done
      [ -S "$SOCK" ] || { echo "waybar-monitor-watch: no hyprland event socket found" >&2; exit 1; }
      socat -U - "UNIX-CONNECT:$SOCK" | while read -r line; do
        case "$line" in
          monitoradded*|monitorremoved*)
            systemctl --user restart waybar.service || true
            ;;
        esac
      done
    '';
  };
in
{
  options = {
    modules.hyprland.waybar.enable = mkEnableOption "Enable waybar" // {
      default = true;
    };
  };
  config = mkIf cfg.enable {
    # micctl for keybinds; the rest are handy to run by hand when debugging
    home.packages = [ barTools ];

    # waybar runs as a systemd --user service so the session manager keeps it
    # alive no matter how it dies (Restart=always recovers from crashes and the
    # silent disappearances that defeated the old exec-once supervisor). The
    # start-rate limit is disabled so a burst of monitor hotplugs (each triggers
    # a restart below) can never push the unit into a failed state where it
    # stays gone.
    #
    # Bound to hyprland-session.target (created by the HM hyprland module's
    # systemd integration) so it only runs under a Hyprland session.
    systemd.user.services.waybar = {
      Unit = {
        Description = "waybar";
        After = [ "hyprland-session.target" ];
        PartOf = [ "hyprland-session.target" ];
        StartLimitIntervalSec = 0;
      };
      Service = {
        ExecStart = "${config.programs.waybar.package}/bin/waybar";
        ExecReload = "${pkgs.coreutils}/bin/kill -SIGUSR2 $MAINPID";
        Restart = "always";
        RestartSec = 1;
      };
      Install.WantedBy = [ "hyprland-session.target" ];
    };

    # Restart waybar on monitor add/remove so its bars rebuild on the current
    # outputs. systemd keeps this watcher alive too (Restart=always), so unlike
    # the old supervisor there is no single launched-once process that, once
    # dead, stays dead.
    systemd.user.services.waybar-monitor-watch = {
      Unit = {
        Description = "Restart waybar on Hyprland monitor hotplug";
        After = [
          "hyprland-session.target"
          "waybar.service"
        ];
        PartOf = [ "hyprland-session.target" ];
        StartLimitIntervalSec = 0;
      };
      Service = {
        ExecStart = "${waybarMonitorWatch}/bin/waybar-monitor-watch";
        Restart = "always";
        RestartSec = 1;
      };
      Install.WantedBy = [ "hyprland-session.target" ];
    };

    # Push-to-talk (pkgs/bar-tools/src/bin/pttd.rs): while armed from the mic
    # module, every mic stays muted except while Right Alt is held. It reads
    # keyd's virtual keyboard (stable by-id symlink, see
    # modules/nixos/peripherals), so real keyboards coming and going never
    # matter, and reopens it if keyd itself restarts. User service (you're in
    # the `input` group) on graphical-session.target, unlike waybar: it's
    # evdev + audio with no compositor dependency.
    systemd.user.services.pttd = {
      Unit = {
        Description = "Push-to-talk (hold Right Alt while armed)";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
        StartLimitIntervalSec = 0;
      };
      Service = {
        ExecStart = "${barTools}/bin/pttd /dev/input/by-id/keyd-virtual-keyboard-event-kbd";
        Restart = "always";
        RestartSec = 1;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    programs.waybar = {
      enable = true;
      package = waybarPackage;
      # We define the waybar systemd user service ourselves below (Restart=always
      # + a monitor-hotplug watcher) instead of using the module's unit, so this
      # only writes the config/style. Running under systemd is what makes the bar
      # reliably recover from crashes and monitor hotplug.
      systemd.enable = false;
      settings = {
        mainBar = {
          reload_style_on_change = true;
          layer = "top";
          position = "top";
          spacing = 4;
          height = 32;
          margin-left = 8;
          margin-right = 8;
          margin-top = 4;

          modules-left = [
            "custom/nix"
            "hyprland/workspaces"
          ];
          modules-center = [
            "hyprland/window"
            "clock"
          ];
          modules-right = [
            "group/tray-expander"
            "network"
            "bluetooth"
            "custom/webcam"
            "custom/mic"
            "custom/volume"
            "cpu"
            "memory"
            "temperature"
            "backlight"
            "battery"
          ];

          "hyprland/workspaces" = {
            on-click = "activate";
            show-special = true;
            all-outputs = false;
            format = "{name} {windows}";
            format-window-separator = " ";
            window-rewrite-default = "";
            window-rewrite = {
              "class<google-chrome>" = "";
              "class<firefox>" = "";
              "class<kitty>" = "󰆍";
              "class<com.mitchellh.ghostty>" = "󰆍";
              "class<code>" = "󰨞";
              "class<slack>" = "󰒱";
              "class<spotify>" = "󰓇";
              "title<.* Gather .*>" = "󱁅";
              "class<.*gather.*>" = "󱁅";
              "title<(.*) - (.*) - Visual Studio Code>" = "[󰨞 $2]";
            };
          };

          "hyprland/window" = {
            format = "{class}";
            max-length = 20;
            rewrite = {
              "^(?!.*\\S).*" = "Desktop";
              "com\\.mitchellh\\.ghostty" = "Ghostty";
            };
          };

          "custom/nix" = {
            format = "󱄅";
            on-click = "fuzzel";
            on-click-right = "system-menu";
            tooltip-format = "Left: App Launcher\nRight: System Menu";
          };

          "custom/lock" = {
            format = "";
            on-click = "loginctl lock-session && ${pkgs.hyprlock}/bin/hyprlock";
            tooltip-format = "Lock Screen";
          };

          # restart-interval only matters if a watcher ever exits
          "custom/webcam" = {
            exec = "${barTools}/bin/webcam-watch";
            return-type = "json";
            restart-interval = 5;
            # like mic/volume: middle mutes, right opens the settings app
            on-click = webcamToggle;
            on-click-middle = webcamToggle;
            on-click-right = "${pkgs.cameractrls-gtk4}/bin/cameractrlsgtk4 &";
          };

          "group/tray-expander" = {
            orientation = "inherit";
            drawer = {
              transition-duration = 600;
              children-class = "tray-group-item";
            };
            modules = [
              "custom/expand-icon"
              "tray"
            ];
          };

          "custom/expand-icon" = {
            format = "󰅂";
            tooltip = false;
          };

          tray = {
            icon-size = 12;
            spacing = 16;
          };

          cpu = {
            interval = 5;
            format = "";
            format-alt = " {usage}%";
            on-click-right = "${pkgs.ghostty}/bin/ghostty --class=btop -e ${pkgs.btop}/bin/btop";
          };

          memory = {
            format = "";
            format-alt = " {}%";
          };

          temperature = {
            critical-threshold = 80;
            format-critical = "{icon} {temperatureC}°C";
            format = "{icon}";
            format-alt = "{icon} {temperatureC}°C";
            format-icons = [
              ""
              ""
              ""
              ""
              ""
            ];
          };

          backlight = {
            format = "{icon}";
            format-alt = "{icon} {percent}%";
            format-icons = [
              "󰃚"
              "󰃛"
              "󰃜"
              "󰃝"
              "󰃞"
              "󰃟"
              "󰃠"
            ];
            tooltip-format = "Backlight: {percent}%";
          };

          clock = {
            format = "{:%a %d %b  %I:%M %p %Z}";
            timezones = [
              "America/New_York"
              "Etc/UTC"
            ];
            tooltip-format = "<tt>{calendar}</tt>";
            calendar = {
              mode = "month";
              on-scroll = 1;
              format = {
                today = "<span color='#${colors.base0B}'><b><u>{}</u></b></span>";
              };
            };
            actions = {
              on-click-right = "tz_up";
            };
          };

          network = {
            format-icons = [
              "󰤟"
              "󰤢"
              "󰤥"
              "󰤨"
            ];
            format = "{icon}";
            format-wifi = "{icon}";
            format-ethernet = "󰌘";
            format-disconnected = "󰌙";
            tooltip-format-wifi = "{essid} ({frequency} GHz)\n↓{bandwidthDownBytes}  ↑{bandwidthUpBytes}";
            tooltip-format-ethernet = "↓{bandwidthDownBytes}  ↑{bandwidthUpBytes}";
            tooltip-format-disconnected = "Disconnected";
            interval = 3;
            spacing = 1;
            on-click = "${pkgs.networkmanagerapplet}/bin/nm-connection-editor";
          };

          battery = {
            format = "{icon}";
            format-charging = "󰂄 {capacity}%";
            format-plugged = "󰚥 {capacity}%";
            format-alt = "{icon} {capacity}%";
            format-icons = [
              "󰁺"
              "󰁻"
              "󰁼"
              "󰁽"
              "󰁾"
              "󰁿"
              "󰂀"
              "󰂁"
              "󰂂"
              "󰁹"
            ];
            format-full = "󱟢";
            tooltip-format = "{power}W {timeTo}";
            interval = 5;
            states = {
              warning = 30;
              critical = 15;
            };
          };

          bluetooth = {
            format = "󰂯";
            format-disabled = "󰂲";
            format-connected = "󰂱";
            format-no-controller = "󰂲";
            tooltip-format = "Devices connected: {num_connections}";
            on-click = "${pkgs.blueman}/bin/blueman-manager";
          };

          # Left-click arms/disarms push-to-talk (pttd does the muting).
          "custom/mic" = {
            exec = "${barTools}/bin/mic-watch";
            return-type = "json";
            restart-interval = 5;
            on-click = "${barTools}/bin/micctl ptt";
            on-click-middle = "${barTools}/bin/micctl mute";
            on-click-right = pavucontrol;
            on-scroll-up = "${barTools}/bin/micctl mute";
            on-scroll-down = "${barTools}/bin/micctl mute";
          };

          # Any volume change flashes the percentage; hover shows it too.
          "custom/volume" = {
            exec = "${barTools}/bin/volume-watch";
            return-type = "json";
            restart-interval = 5;
            on-click-middle = "${wpctl} set-mute @DEFAULT_AUDIO_SINK@ toggle";
            on-click-right = pavucontrol;
            on-scroll-up = "${wpctl} set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+";
            on-scroll-down = "${wpctl} set-volume @DEFAULT_AUDIO_SINK@ 5%-";
          };
        };
      };
      style = builtins.readFile ./waybar.css;
    };
  };
}
