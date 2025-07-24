{
  pkgs,
  lib,
  inputs,
  ...
}:
{
  imports = [
    ./waybar
  ];

  xdg.mimeApps.defaultApplications = {
    "x-scheme-handler/https" = lib.mkForce [ "google-chrome.desktop" ]; # or whatever browser you prefer
    "x-scheme-handler/http" = lib.mkForce [ "google-chrome.desktop" ]; # or whatever browser you prefer

    "inode/directory" = [ "org.gnome.Nautilus.desktop" ];

    "application/zip" = [ "org.gnome.Nautilus.desktop" ];
    "application/x-tar" = [ "org.gnome.Nautilus.desktop" ];
    "application/gzip" = [ "org.gnome.Nautilus.desktop" ];
  };

  secondfront.hyprland.monitors = [
    {
      name = "eDP-1";
      resolution = "highres@highrr";
      position = "auto";
      scale = "1";
    }
    {
      name = "desc:GIGA-BYTE TECHNOLOGY CO. LTD. Gigabyte M32U 22181B002365";
      resolution = "3840x2160@144";
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
    targets.k9s.enable = true;

    opacity.desktop = lib.mkForce 0.92;
    opacity.terminal = lib.mkForce 0.92;
    opacity.popups = lib.mkForce 0.92;

    cursor.package = pkgs.adwaita-icon-theme;
    cursor.name = "Adwaita";
    cursor.size = 16;

    fonts = {
      monospace = lib.mkForce {
        package = pkgs.cascadia-code;
        name = "Cascadia Code NF";
      };

      serif = lib.mkForce {
        package = inputs.apple-fonts.packages.${pkgs.system}.sf-pro-nerd;
        name = "SFProText Nerd Font";
      };

      sansSerif = lib.mkForce {
        package = inputs.apple-fonts.packages.${pkgs.system}.sf-pro-nerd;
        name = "SFProText Nerd Font";
      };

      sizes = lib.mkForce {
        desktop = 13;
        applications = 13;
        popups = 11;
      };
    };
  };

  home.packages = with pkgs; [
    inputs.apple-fonts.packages.${pkgs.system}.sf-pro-nerd
    inputs.apple-fonts.packages.${pkgs.system}.sf-mono-nerd

    twofctl
    go
    gopls
    sqlc
    gotools
    delve
    rustup
    python3
    poetry
    nodejs_22
    deno
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
    git-filter-repo

    # Additional DevOps tools
    pulumi-bin
    sops
    age
    nss
    cosign
    curl
    dive
    trivy
    yq # jq is provided, but not yq
    ssm-session-manager-plugin
    grype
    syft
    mysql80
    openssl

    # System utilities
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

    networkmanagerapplet

    # Smart card tools
    pcsc-tools

    # Bluetooth
    bluez
    bluez-tools

    # Additional chat/communication
    signal-desktop

    # Image editing
    gimp
    inkscape

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
    nixfmt-rfc-style
  ];

  programs = {
    vscode = {
      enable = true;
      package = pkgs.vscode.fhsWithPackages (
        ps: with ps; [
          nodejs_22
          rustup
          zlib
          openssl.dev
          pkg-config
        ]
      );
    };

    fuzzel = {
      enable = true;
      settings = {
        main = {
          prompt = "\" \"";
          font = lib.mkForce "SFProText Nerd Font:size=13";
          icon-theme = "Colloid";
        };
        border = {
          radius = 10;
        };
      };
    };
  };

  services.hyprpaper = {
    settings.preload = [
      "~/Wallpapers/2f-ai-mountains.png"
    ];
    settings.wallpaper = [
      ",~/Wallpapers/2f-ai-mountains.png"
    ];
  };

  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "pidof hyprlock || hyprlock"; # avoid starting multiple hyprlock instances.
        after_sleep_cmd = "hyprctl dispatch dpms on"; # to avoid having to press a key twice to turn on the display.
        before_sleep_cmd = "loginctl lock-session"; # lock before suspend.
      };

      listener = [
        {
          timeout = 150; # 2.5min - dim the screen
          on-timeout = "brightnessctl -s set 10";
          on-resume = "brightnessctl -r";
        }
        {
          timeout = 300; # 5 minutes - lock the screen
          on-timeout = "loginctl lock-session";
        }
        {
          timeout = 600; # 10 minutes - turn off displays
          on-timeout = "hyprctl dispatch dpms off";
          on-resume = "hyprctl dispatch dpms on && brightnessctl -r";
        }
        {
          timeout = 1200; # 20 minutes - suspend system
          on-timeout = "systemctl suspend";
        }
      ];
    };
  };

  gtk = {
    enable = true;
    iconTheme = {
      package = pkgs.colloid-icon-theme;
      name = "Colloid";
    };
  };

  wayland.windowManager.hyprland = {
    settings = {
      general = {
        "col.active_border" = lib.mkForce "rgba(ffffffff)"; # White border like your groups
        "col.inactive_border" = lib.mkForce "rgba(3a3a3c80)"; # Match your group colors
      };

      input = {
        touchpad = {
          natural_scroll = lib.mkForce true; # You already have this
          tap-to-click = true; # Enable tap-to-click
          disable_while_typing = true; # Prevent accidental touches
          clickfinger_behavior = true; # 2-finger = right click, 3-finger = middle click
          scroll_factor = 0.5; # Adjust scroll sensitivity (1.0 = default, lower = less sensitive)
          drag_lock = false; # Disable tap-drag-lock
        };

        accel_profile = "adaptive"; # or "flat" for no acceleration
      };

      layerrule = [
        "blur,waybar"
        "blur,group"
        "blur,launcher"
        "ignorealpha 0.5, launcher"
      ];

      decoration = {
        blur = lib.mkForce {
          enabled = true;
          new_optimizations = true;
          xray = true;
          popups = true;
        };
      };

      group = lib.mkForce {
        # Group bar styling (higher opacity for bright wallpaper)
        "col.border_active" = "rgba(ffffffff)"; # White border for active
        "col.border_inactive" = "rgba(3a3a3c80)"; # Your waybar color at 50% opacity
        "col.border_locked_active" = "rgba(f53c3cff)"; # Red for locked (matches your battery critical)
        "col.border_locked_inactive" = "rgba(3a3a3c60)";

        groupbar = {
          enabled = true;
          font_size = 11;
          font_family = "SFProText Nerd Font";
          font_weight_inactive = "Normal"; # Lighter weight
          font_weight_active = "Bold"; # Heavy weight
          height = 14;
          render_titles = true;
          scrolling = true;
          text_color = "rgba(000000dd)"; # Slightly more opaque
          indicator_height = 0;

          "col.active" = "rgba(ffffffcc)"; # White, 80% opacity
          "col.inactive" = "rgba(ffffff33)"; # White, 20% opacity
          "col.locked_active" = "rgba(f53c3ccc)";
          "col.locked_inactive" = "rgba(ffffff40)";
          gradients = true;
        };
      };

      exec-once = [
        "systemctl --user import-environment PATH && systemctl --user restart xdg-desktop-portal.service"
        "hypridle"
      ];

      exec = [
        "nm-applet --indicator"
      ];

      bind = [
        "$mainMod, V, exec, ${pkgs.cliphist}/bin/cliphist list | ${pkgs.fuzzel}/bin/fuzzel --dmenu | ${pkgs.cliphist}/bin/cliphist decode | ${pkgs.wl-clipboard}/bin/wl-copy"
        "$mainMod, G, togglegroup"
        "$mainMod, U, moveoutofgroup"
        "$mainMod, Return, exec, ${pkgs.kitty}/bin/kitty"
        "$mainMod, Y, exec, ykmanoath"
        "$mainMod, Q, killactive,"
        "$mainMod, E, exec, ${pkgs.nautilus}/bin/nautilus"
        "$mainMod, F, togglefloating,"
        "$mainMod, SPACE, exec, ${pkgs.fuzzel}/bin/fuzzel"
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
        "$mainMod, F3, exec, ${pkgs.brightnessctl}/bin/brightnessctl -d *::kbd_backlight set +33%"
        "$mainMod, F2, exec, ${pkgs.brightnessctl}/bin/brightnessctl -d *::kbd_backlight set 33%-"
        ", XF86AudioRaiseVolume, exec, ${pkgs.pamixer}/bin/pamixer -i 5"
        ", XF86AudioLowerVolume, exec, ${pkgs.pamixer}/bin/pamixer -d 5"
        ", XF86AudioMute, exec, ${pkgs.pamixer}/bin/pamixer -t"
        ", XF86AudioMicMute, exec, ${pkgs.pamixer}/bin/pamixer --default-source -m"
        ", XF86MonBrightnessDown, exec, ${pkgs.brightnessctl}/bin/brightnessctl set 5%-"
        ", XF86MonBrightnessUp, exec, ${pkgs.brightnessctl}/bin/brightnessctl set +5%"
        '', Print, exec, ${pkgs.grim}/bin/grim -g "$(${pkgs.slurp}/bin/slurp)" - | ${pkgs.swappy}/bin/swappy -f -''
        "$mainMod, B, exec, pkill -SIGUSR1 waybar"
        "$mainMod, W, exec, pkill -SIGUSR2 waybar"

        "ALT, TAB, cyclenext"
        "ALT SHIFT, TAB, cyclenext, prev"
        "$mainMod, X, exec, loginctl lock-session"
      ];

      bindm = [
        "$mainMod, mouse:272, movewindow"
        "$mainMod, mouse:273, resizewindow"
      ];

      env = [
        "LIBVA_DRIVER_NAME,nvidia"
        "__GLX_VENDOR_LIBRARY_NAME,nvidia"
        "HYPRCURSOR_THEME,Adwaita"
      ];
    };
  };
}
