{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
let
  cfg = config.secondfront.hyprland.waybar;
  inherit (config.lib.stylix) colors;

  webcamToggle = pkgs.writeShellScript "webcam-toggle" ''
    sudo /run/current-system/sw/bin/webcam-toggle toggle
    ${pkgs.procps}/bin/pkill -RTMIN+10 waybar
  '';

  webcamStatus = pkgs.writeShellScript "webcam-status" ''
    USB_IDS="0c45:6d50 046d:0946"
    found=0
    any_on=0
    in_use=0
    for id in $USB_IDS; do
      vid="''${id%%:*}"
      pid="''${id##*:}"
      for devpath in /sys/bus/usb/devices/*/idVendor; do
        dir="$(dirname "$devpath")"
        if [ -f "$dir/idVendor" ] && [ -f "$dir/idProduct" ] && [ -f "$dir/authorized" ] \
           && [ "$(cat "$dir/idVendor")" = "$vid" ] \
           && [ "$(cat "$dir/idProduct")" = "$pid" ]; then
          found=1
          if [ "$(cat "$dir/authorized")" = "1" ]; then
            any_on=1
            # Check if any video device under this USB device is open by a process
            for vdir in "$dir"/*/video4linux/video*; do
              if [ -d "$vdir" ]; then
                vdev="/dev/$(basename "$vdir")"
                if [ -e "$vdev" ] && ${pkgs.psmisc}/bin/fuser "$vdev" >/dev/null 2>&1; then
                  in_use=1
                fi
              fi
            done
          fi
        fi
      done
    done
    if [ "$found" = "0" ]; then
      echo '{"text": "󰖠", "tooltip": "No cameras found", "class": "disconnected"}'
    elif [ "$any_on" = "0" ]; then
      echo '{"text": "󱜷", "tooltip": "Webcam muted", "class": "muted"}'
    elif [ "$in_use" = "1" ]; then
      echo '{"text": "󰖠", "tooltip": "Webcam in use", "class": "in-use"}'
    else
      echo '{"text": "󰖠", "tooltip": "Webcam available", "class": "available"}'
    fi
  '';
in
{
  options = {
    secondfront.hyprland.waybar.enable = mkEnableOption "Enable waybar" // {
      default = true;
    };
  };
  config = mkIf cfg.enable {
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
            "group/tray-expander"
            "custom/lock"
            "network"
            "bluetooth"
            "custom/webcam"
            "pulseaudio"
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
              "class<code>" = "󰨞";
              "class<slack>" = "󰒱";
              "class<spotify>" = "󰓇";
              "title<.* Gather .*>" = "󱁅";
              "title<(.*) - (.*) - Visual Studio Code>" = "[󰨞 $2]";
            };
          };

          "hyprland/window" = {
            format = "{class}";
            max-length = 20;
            rewrite = {
              "^(?!.*\\S).*" = "Desktop";
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
            interval = 2;
            signal = 10;
            on-click = "${pkgs.cameractrls-gtk4}/bin/cameractrlsgtk4";
            on-click-middle = "${webcamToggle}";
            on-click-right = "${webcamToggle}";
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
            on-click-right = "${pkgs.kitty}/bin/kitty --class btop -e ${pkgs.btop}/bin/btop";
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

          pulseaudio = {
            format = "{icon}";
            format-alt = "{icon}  {volume}% {format_source}";
            on-click-middle = "${pkgs.pamixer}/bin/pamixer -t";
            on-click-right = "${pkgs.pavucontrol}/bin/pavucontrol";
            tooltip-format = "Playing at {volume}%";
            scroll-step = 5;
            format-muted = "󰝟";
            format-source = " {volume}%";
            format-source-muted = "󰝟";
            format-icons = {
              default = [
                "󰕿"
                "󰖀"
                "󰕾"
              ];
            };
          };
        };
      };
      style = builtins.readFile ./waybar.css;
    };
  };
}
