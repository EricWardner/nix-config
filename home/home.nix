{
  pkgs,
  lib,
  inputs,
  ...
}:
{
  secondfront.hyprland.monitors = [
    {
      name = "eDP-1";
      resolution = "highres@highrr";
      position = "auto";
      scale = "1";
    }
    {
      name = "desc:GIGA-BYTE TECHNOLOGY CO. LTD. Gigabyte M32U 22181B002365";
      resolution = "highres@highrr";
      position = "-3072x-1000";
      scale = "1.25";
    }
    {
      name = "desc:ESP eD13(2022) 0x00023552";
      resolution = "highres@highrr";
      position = "auto-left";
      scale = "1";
    }
  ];

  stylix = {
    targets.vscode.enable = false;
    targets.waybar.enable = false;

    fonts = {
      monospace = lib.mkForce {
        package = pkgs.cascadia-code;
        name = "Cascadia Code NF";
      };

      serif = lib.mkForce {
        package = inputs.apple-fonts.packages.${pkgs.system}.sf-pro-nerd;
        name = "SFProDisplay Nerd Font";
      };

      sansSerif = lib.mkForce {
        package = inputs.apple-fonts.packages.${pkgs.system}.sf-pro-nerd;
        name = "SFProDisplay Nerd Font";
      };

      sizes = lib.mkForce {
        desktop = 13;
        popups = 11;
      };
    };


  };

  home.packages = with pkgs; [
    inputs.apple-fonts.packages.${pkgs.system}.sf-pro-nerd
    inputs.apple-fonts.packages.${pkgs.system}.sf-mono-nerd

    # twofctl
    go
    gopls
    sqlc
    gotools
    delve
    rustup
    python3
    poetry
    nodejs_22
    typescript
    pre-commit
    go-mockery
    golangci-lint
    cypress
    bun
    air
    jdk
    postgresql
    protobuf
    apko
    
    # Additional DevOps tools
    pulumi-bin
    sops
    age
    nss
    cosign
    curl
    dive
    trivy
    yq  # jq is provided, but not yq
    ssm-session-manager-plugin
    grype
    syft
    mysql80
    openssl
    
    # System utilities
    brightnessctl
    imv
    lshw
    unzip
    tiled
    atuin
    nautilus
    coreutils
    file
    pgloader
    hubble
    
    # Smart card tools
    pcsc-tools
    
    # Bluetooth
    bluez
    bluez-tools
    
    # Additional chat/communication
    signal-desktop
    
    # Additional screenshot tools
    grimblast  # grim/slurp/swappy already provided
    flameshot
    
    # Image editing
    gimp
    inkscape
    
    # Additional clipboard (wl-clipboard-rs provided, but you had wl-clipboard)
    cliphist  # Actually already provided as a service!
    
    # YubiKey (yubikey-manager provided)
    yubioath-flutter
    
    # Browsers
    google-chrome
    
    # Other tools
    spotify
    crane
    wireguard-tools
    ngrok
    claude-code
  ];

  programs = {
    # k9s.settings.ui.skin = "skin";
    vscode = {
      enable = true;
      package = pkgs.vscode.fhsWithPackages (ps: with ps; [ 
        nodejs 
        rustup 
        zlib 
        openssl.dev 
        pkg-config 
      ]);
    };

    waybar = lib.mkForce {
      enable = true;
      settings = {
        # Top bar configuration
        mainBar = {
          layer = "top";
          position = "top";
          height = 24;
          spacing = 5;
          modules-left = [
            "custom/launcher"
            "hyprland/window"
          ];
          modules-center = [
            "sway/window"
          ];
          modules-right = [
            "mpd"
            "idle_inhibitor"
            "temperature"
            "cpu"
            "memory"
            "network"
            "pulseaudio"
            "backlight"
            "keyboard-state"
            "battery"
            "battery#bat2"
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

          "custom/launcher" = {
            format = "🔍";
            on-click = "wofi --show drun";
            tooltip = false;
          };

          "sway/mode" = {
            format = "<span style=\"italic\">{}</span>";
          };

          "sway/scratchpad" = {
            format = "{icon} {count}";
            show-empty = false;
            format-icons = [ "" "" ];
            tooltip = true;
            tooltip-format = "{app}: {title}";
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
            format = "{:%A %B %d %H:%M %p}";
            tooltip-format = "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>";
          };

          cpu = {
            format = "  {usage}%";
          };

          memory = {
            format = " {}%";
          };

          temperature = {
            thermal-zone = 2;
            hwmon-path = "/sys/class/hwmon/hwmon2/temp1_input";
            critical-threshold = 80;
            format-critical = "{icon} {temperatureC}°C";
            format = "{icon} {temperatureC}°C";
            format-icons = [ "" "" "" ];
          };

          backlight = {
            format = "{icon} {percent}%";
            format-icons = [ "" "" "" "" "" "" "" "" "" ];
          };

          battery = {
            states = {
              warning = 30;
              critical = 15;
            };
            format = "{icon} {capacity}%";
            format-charging = " {capacity}%";
            format-plugged = "  {capacity}%";
            format-alt = "{icon} {time}";
            format-icons = [ "" "" "" "" "" ];
          };

          "battery#bat2" = {
            bat = "BAT2";
          };

          network = {
            format-wifi = "{essid} ({signalStrength}%) ";
            format-ethernet = " {ifname}";
            tooltip-format = " {ifname} via {gwaddr}";
            format-linked = " {ifname} (No IP)";
            format-disconnected = "Disconnected ⚠ {ifname}";
            format-alt = " {ifname}: {ipaddr}/{cidr}";
          };

          pulseaudio = {
            scroll-step = 5;
            format = "{icon}  {volume}% {format_source}";
            format-bluetooth = " {icon} {volume}% {format_source}";
            format-bluetooth-muted = "   {icon} {format_source}";
            format-muted = "  {format_source}";
            format-source = " {volume}%";
            format-source-muted = "";
            format-icons = {
              default = [ "" "" "" ];
            };
            on-click = "pavucontrol";
            on-click-right = "foot -a pw-top pw-top";
          };
        };
      };
      style = lib.mkAfter (builtins.readFile ./waybar.css);
    };
  };

  gtk = {
    iconTheme = {
      package = pkgs.colloid-icon-theme;
      name = "Colloid";
    };
  };

  wayland.windowManager.hyprland = {
    settings = {
      exec-once = [
        "systemctl --user import-environment PATH && systemctl --user restart xdg-desktop-portal.service"
      ];
      bind = [
        "$mainMod, V, exec, cliphist list | fuzzel --dmenu | cliphist decode | wl-copy"
        "$mainMod, G, togglegroup"
        "$mainMod, Return, exec, kitty"
        "$mainMod, Y, exec, ykmanoath"
        "$mainMod, Q, killactive,"
        "$mainMod, E, exec, thunar"
        "$mainMod, F, togglefloating,"
        "$mainMod, SPACE, exec, fuzzel"
        "$mainMod, P, pseudo, # dwindle"
        "$mainMod, S, togglesplit, # dwindle"
        "$mainMod, TAB, workspace, previous"
        ",F11,fullscreen"
        "$mainMod, h, movefocus, l"
        "$mainMod, l, movefocus, r"
        "$mainMod, k, movefocus, u"
        "$mainMod, j, movefocus, d"
        "$mainMod ALT, J, changegroupactive, f"
        "$mainMod ALT, K, changegroupactive, b"
        "$mainMod SHIFT, h, movewindoworgroup, l"
        "$mainMod SHIFT, l, movewindoworgroup, r"
        "$mainMod SHIFT, k, movewindoworgroup, u"
        "$mainMod SHIFT, j, movewindoworgroup, d"
        "$mainMod CTRL, h, resizeactive, -60 0"
        "$mainMod CTRL, l, resizeactive,  60 0"
        "$mainMod CTRL, k, resizeactive,  0 -60"
        "$mainMod CTRL, j, resizeactive,  0  60"
        "$mainMod, 1, workspace, 1"
        "$mainMod, 2, workspace, 2"
        "$mainMod, 3, workspace, 3"
        "$mainMod, 4, workspace, 4"
        "$mainMod, 5, workspace, 5"
        "$mainMod, 6, workspace, 6"
        "$mainMod, 7, workspace, 7"
        "$mainMod, 8, workspace, 8"
        "$mainMod, 9, workspace, 9"
        "$mainMod, 0, workspace, 10"
        "$mainMod SHIFT, 1, movetoworkspacesilent, 1"
        "$mainMod SHIFT, 2, movetoworkspacesilent, 2"
        "$mainMod SHIFT, 3, movetoworkspacesilent, 3"
        "$mainMod SHIFT, 4, movetoworkspacesilent, 4"
        "$mainMod SHIFT, 5, movetoworkspacesilent, 5"
        "$mainMod SHIFT, 6, movetoworkspacesilent, 6"
        "$mainMod SHIFT, 7, movetoworkspacesilent, 7"
        "$mainMod SHIFT, 8, movetoworkspacesilent, 8"
        "$mainMod SHIFT, 9, movetoworkspacesilent, 9"
        "$mainMod SHIFT, 0, movetoworkspacesilent, 10"
        "$mainMod, mouse_down, workspace, e+1"
        "$mainMod, mouse_up, workspace, e-1"
        "$mainMod, F3, exec, brightnessctl -d *::kbd_backlight set +33%"
        "$mainMod, F2, exec, brightnessctl -d *::kbd_backlight set 33%-"
        ", XF86AudioRaiseVolume, exec, pamixer -i 5 "
        ", XF86AudioLowerVolume, exec, pamixer -d 5 "
        ", XF86AudioMute, exec, pamixer -t"
        ", XF86AudioMicMute, exec, pamixer --default-source -m"
        ", XF86MonBrightnessDown, exec, brightnessctl set 5%- "
        ", XF86MonBrightnessUp, exec, brightnessctl set +5% "
        '', Print, exec, grim -g "$(slurp)" - | swappy -f -''
        "$mainMod, B, exec, pkill -SIGUSR1 waybar"
        "$mainMod, W, exec, pkill -SIGUSR2 waybar"
      ];
      bindm = [
        "$mainMod, mouse:272, movewindow"
        "$mainMod, mouse:273, resizewindow"
      ];
    };
  };
}
