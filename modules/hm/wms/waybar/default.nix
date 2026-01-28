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
            "temperature"
            "bluetooth"
            "network"
            "pulseaudio"
            "backlight"
            "cpu"
            "memory"
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
              "title<(.*) - (.*) - Visual Studio Code>" = "󰨞 $2";
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
            tooltip = false;
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
            format-alt = "  {usage}%";
            on-click = "${pkgs.kitty}/bin/kitty -e ${pkgs.btop}/bin/btop";
          };

          memory = {
            format = "";
            format-alt = "  {}%";
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
            format = "{:%a %d %b  %I:%M %p}";
            format-alt = "{:L%d %B W%V %Y}";
            tooltip-format = "<tt>{calendar}</tt>";
            calendar = {
              mode = "month";
              on-scroll = 1;
              format = {
                today = "<span color='#${colors.base0B}'><b><u>{}</u></b></span>";
              };
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
            on-click = "${pkgs.kitty}/bin/kitty -e ${pkgs.networkmanager}/bin/nmtui";
          };

          battery = {
            format = "{icon} {capacity}%";
            format-discharging = "{icon}";
            format-charging = "󰂄 {capacity}%";
            format-plugged = " {capacity}%";
            format-alt = "{icon} {time}";
            format-icons = [
              "󰢜"
              "󰂆"
              "󰂇"
              "󰂈"
              "󰢝"
              "󰂉"
              "󰢞"
              "󰂊"
              "󰂋"
              "󰂅"
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
            on-click = "${pkgs.pavucontrol}/bin/pavucontrol";
            on-click-right = "${pkgs.pamixer}/bin/pamixer -t";
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
