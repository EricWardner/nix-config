{ lib, ... }:
{
  programs.waybar = lib.mkForce {
    enable = true;
    settings = {
      # Top bar configuration
      mainBar = {
        layer = "top";
        position = "top";
        height = 16;
        spacing = 5;
        margin-left = 2;
        margin-right = 2;
        margin-top = 2;
        modules-left = [
          "custom/launcher"
          "hyprland/workspaces"
        ];
        modules-center = [
          "hyprland/window"
        ];
        modules-right = [
          "mpd"
          # "idle_inhibitor"
          "temperature"
          "cpu"
          "memory"
          "network"
          "pulseaudio"
          "backlight"
          "battery"
          "tray"
          "clock"
        ];

        # Module configurations
        "hyprland/window" = {
          format = "{class}";
          max-length = 20;
          rewrite = {
            "^(?!.*\\S).*" = "Finder";
          };
        };

        "hyprland/workspaces" = {
          show-special = true;
          format = "{name} {windows}";
          format-alt = "poopt";
          icon-size = 24;
          format-window-separator = " ";
          window-rewrite-default = "";
          window-rewrite = {
            "class<google-chrome>" = "";
            "class<kitty>" = "";
            "class<code>" = "󰨞";
            "class<slack>" = "";
            "title<(.*) - (.*) - Visual Studio Code>" = "󰨞 $2";
          };
        };

        "custom/launcher" = {
          format = "";
          on-click = "fuzzel";
          tooltip = false;
        };

        mpd = {
          format = "  {title} - {artist} {stateIcon} [{elapsedTime:%M:%S}/{totalTime:%M:%S}] {consumeIcon}{randomIcon}{repeatIcon}{singleIcon}[{songPosition}/{queueLength}] [{volume}%]";
          format-disconnected = " Disconnected";
          format-stopped = " {consumeIcon}{randomIcon}{repeatIcon}{singleIcon}Stopped";
          unknown-tag = "N/A";
          interval = 2;
          consume-icons = {
            "on" = " ";
          };
          random-icons = {
            "on" = " ";
          };
          repeat-icons = {
            "on" = " ";
          };
          single-icons = {
            "on" = "1 ";
          };
          state-icons = {
            paused = "";
            playing = "";
          };
          tooltip-format = "MPD (connected)";
          tooltip-format-disconnected = "MPD (disconnected)";
          on-click = "mpc toggle";
          on-click-right = "foot -a ncmpcpp ncmpcpp";
          on-scroll-up = "mpc volume +2";
          on-scroll-down = "mpc volume -2";
        };

        idle_inhibitor = {
          format = "{icon}";
          format-icons = {
            activated = "";
            deactivated = "";
          };
        };

        tray = {
          spacing = 10;
        };

        clock = {
          format = "{:%a %d %b  %H:%M %p %Z}";
          timezones = [
            "America/New_York"
            "Etc/UTC"
          ];
          tooltip-format = "<tt>{calendar}</tt>";
          calendar = {
            mode = "month";
            on-scroll = 1;
            format = {
              today = "<span color='#47FF51'><b><u>{}</u></b></span>"; # This highlights today
            };
          };
          actions = {
            on-click-right = "tz_up";
          };
        };

        cpu = {
          format = "";
          format-alt = "  {usage}%";
        };

        memory = {
          format = "";
          format-alt = "  {}%";
        };

        temperature = {
          thermal-zone = 2;
          hwmon-path = "/sys/class/hwmon/hwmon2/temp1_input";
          critical-threshold = 80;
          format-critical = "{icon} {temperatureC}°C";
          format = "{icon}";
          format-alt = "{icon} {temperatureC}°C";
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
          # format-icons = [ "" "" "" "" "" "" "" "" "" ];
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

        battery = {
          states = {
            warning = 30;
            critical = 15;
          };
          format = "{icon} {capacity}%";
          format-charging = "󰂄 {capacity}%";
          format-plugged = "  {capacity}%";
          format-alt = "{icon} {time}";
          tooltip-format = "{power}W {timeTo}";
          format-icons = [
            ""
            ""
            ""
            ""
            ""
          ];
        };

        network = {
          format-wifi = "";
          tooltip-format-wifi = "{essid} ({signalStrength}%)";
          format-ethernet = "󰈁";
          tooltip-format-ethernet = "󰈁 {ifname}";
          format-linked = "󱚵";
          tooltip-format-linked = "{ifname} (No IP)";
          format-disconnected = "󰤫";
          tooltip-format-disconnected = "Disconnected ⚠ {ifname}";
          format-alt = "{ifname}: {ipaddr}/{cidr}";
        };

        pulseaudio = {
          scroll-step = 5;
          format = "{icon}";
          format-alt = "{icon}  {volume}% {format_source}";
          format-bluetooth = " {icon} {volume}% {format_source}";
          format-bluetooth-muted = "󰝟   {icon} {format_source}";
          format-muted = "󰝟  {format_source}";
          format-source = " {volume}%";
          format-source-muted = "";
          format-icons = {
            default = [
              ""
              ""
              ""
            ];
          };
          on-click-right = "pavucontrol";
        };
      };
    };
    style = lib.mkAfter (builtins.readFile ./waybar.css);
  };
}
