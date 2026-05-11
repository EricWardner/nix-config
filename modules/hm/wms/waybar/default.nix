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

  webcamToggle = pkgs.writeShellScript "webcam-toggle" ''
    sudo /run/current-system/sw/bin/webcam-toggle toggle
    ${pkgs.procps}/bin/pkill -RTMIN+10 waybar
  '';

  volumeAction = pkgs.writeShellApplication {
    name = "volume-action";
    runtimeInputs = with pkgs; [
      wireplumber
      procps
      coreutils
    ];
    text = ''
      case "''${1:-}" in
        up)    wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+ ;;
        down)  wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- ;;
        mute)  wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle ;;
        flash) ;;
        *)     echo "usage: volume-action {up|down|mute|flash}" >&2; exit 1 ;;
      esac
      touch /tmp/waybar-volume-flash
      pkill -RTMIN+11 waybar || true
    '';
  };

  volumeStatus = pkgs.writeShellScript "volume-status" ''
    FLAG_FILE="/tmp/waybar-volume-flash"
    RAW=$(${pkgs.wireplumber}/bin/wpctl get-volume @DEFAULT_AUDIO_SINK@)
    VOLUME=$(echo "$RAW" | ${pkgs.gawk}/bin/awk '{print int($2 * 100)}')

    if echo "$RAW" | ${pkgs.gnugrep}/bin/grep -q MUTED; then
      ICON="󰝟"
      CLASS="muted"
    elif [ "$VOLUME" -lt 33 ]; then
      ICON="󰕿"
      CLASS=""
    elif [ "$VOLUME" -lt 67 ]; then
      ICON="󰖀"
      CLASS=""
    else
      ICON="󰕾"
      CLASS=""
    fi

    SHOW_PCT=0
    if [ -f "$FLAG_FILE" ]; then
      NOW=$(${pkgs.coreutils}/bin/date +%s)
      MTIME=$(${pkgs.coreutils}/bin/stat -c %Y "$FLAG_FILE")
      AGE=$((NOW - MTIME))
      [ "$AGE" -lt 2 ] && SHOW_PCT=1
    fi

    if [ "$SHOW_PCT" = "1" ]; then
      TEXT="$ICON  $VOLUME%"
    else
      TEXT="$ICON"
    fi

    ${pkgs.coreutils}/bin/printf '{"text": "%s", "tooltip": "Volume: %d%%", "class": "%s"}\n' "$TEXT" "$VOLUME" "$CLASS"
  '';

  webcamStatus = pkgs.writeShellScript "webcam-status" ''
    STATE_FILE="/tmp/webcam-usb-paths"
    found=0
    any_on=0
    in_use=0
    for vdir in /sys/class/video4linux/video*; do
      [ -d "$vdir" ] || continue
      real="$(readlink -f "$vdir/device")"
      dir="$real"
      while [ "$dir" != "/" ]; do
        if [ -f "$dir/authorized" ] && [ -f "$dir/idVendor" ]; then
          break
        fi
        dir="$(dirname "$dir")"
      done
      [ "$dir" = "/" ] && continue
      found=1
      if [ "$(cat "$dir/authorized")" = "1" ]; then
        any_on=1
        vdev="/dev/$(basename "$vdir")"
        if [ -e "$vdev" ] && ${pkgs.psmisc}/bin/fuser "$vdev" >/dev/null 2>&1; then
          in_use=1
        fi
      fi
    done
    # Check state file for deauthorized cameras (video4linux entries disappear when deauthorized)
    if [ "$found" = "0" ] && [ -f "$STATE_FILE" ]; then
      while IFS= read -r p; do
        [ -f "$p/authorized" ] || continue
        found=1
        if [ "$(cat "$p/authorized")" = "1" ]; then
          any_on=1
        fi
      done < "$STATE_FILE"
    fi
    if [ "$found" = "0" ]; then
      echo '{"text": "󱜷", "tooltip": "No cameras found", "class": "disconnected"}'
    elif [ "$any_on" = "0" ]; then
      echo '{"text": "󱜷", "tooltip": "Webcam muted", "class": "muted"}'
    elif [ "$in_use" = "1" ]; then
      echo '{"text": "󰖠", "tooltip": "Webcam in use", "class": "in-use"}'
    else
      echo '{"text": "󰖠", "tooltip": "Webcam available", "class": "available"}'
    fi
  '';

  pcStatus = pkgs.writeShellScript "pc-status" ''
    LABEL="$1"
    PORT="$2"
    PROCS="$3"

    RAW=$(${pkgs.process-compose}/bin/process-compose process list -o json -p "''${PORT}" 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$RAW" ]; then
      echo "{\"text\": \"''${LABEL}: 󱎘\", \"tooltip\": \"''${LABEL}: not reachable\", \"class\": \"offline\"}"
      exit 0
    fi

    IFS=',' read -ra PROC_ARR <<< "''${PROCS}"
    TOTAL=0
    RUNNING=0
    TOOLTIP="''${LABEL}:"
    for proc in "''${PROC_ARR[@]}"; do
      STATUS=$(echo "$RAW" | ${pkgs.jq}/bin/jq -r --arg name "$proc" '.[] | select(.name == $name) | .status')
      TOTAL=$((TOTAL + 1))
      if [ "$STATUS" = "Running" ]; then
        RUNNING=$((RUNNING + 1))
        TOOLTIP="''${TOOLTIP}\n  ✓ ''${proc}"
      else
        TOOLTIP="''${TOOLTIP}\n  ✗ ''${proc} (''${STATUS:-unknown})"
      fi
    done

    if [ "$RUNNING" -eq "$TOTAL" ]; then
      ICON="󰐾"
      CLASS="online"
    elif [ "$RUNNING" -gt 0 ]; then
      ICON="󰍷"
      CLASS="degraded"
    else
      ICON="󱎘"
      CLASS="offline"
    fi

    TOOLTIP="''${TOOLTIP}\n  ''${RUNNING}/''${TOTAL} running"
    echo "{\"text\": \"''${LABEL}: ''${ICON}\", \"tooltip\": \"''${TOOLTIP}\", \"class\": \"''${CLASS}\"}"
  '';
in
{
  options = {
    modules.hyprland.waybar.enable = mkEnableOption "Enable waybar" // {
      default = true;
    };
  };
  config = mkIf cfg.enable {
    home.packages = [ volumeAction ];
    programs.waybar = {
      enable = true;
      systemd.enable = true;
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
            "custom/agility"
            "group/tray-expander"
            "network"
            "bluetooth"
            "custom/webcam"
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

          "custom/webcam" = {
            exec = "${webcamStatus}";
            return-type = "json";
            interval = 1;
            signal = 10;
            on-click = "${pkgs.cameractrls-gtk4}/bin/cameractrlsgtk4 &";
            on-click-middle = "${webcamToggle}";
            on-click-right = "${webcamToggle}";
          };

          "custom/agility" = {
            exec = "${pcStatus} AGI 8088 backend,backend-static,frontend,postgres,zitadel,openfga,rustfs,mailpit";
            return-type = "json";
            interval = 5;
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

          "custom/volume" = {
            exec = "${volumeStatus}";
            return-type = "json";
            interval = 1;
            signal = 11;
            on-click = "${volumeAction}/bin/volume-action flash";
            on-click-middle = "${volumeAction}/bin/volume-action mute";
            on-click-right = "${pkgs.pavucontrol}/bin/pavucontrol";
            on-scroll-up = "${volumeAction}/bin/volume-action up";
            on-scroll-down = "${volumeAction}/bin/volume-action down";
          };
        };
      };
      style = builtins.readFile ./waybar.css;
    };
  };
}
