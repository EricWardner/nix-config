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
    targets.kitty.enable = false;

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
    # k9s.settings.ui.skin = "skin";
    vscode = {
      enable = true;
      package = pkgs.vscode.fhsWithPackages (
        ps: with ps; [
          nodejs
          rustup
          zlib
          openssl.dev
          pkg-config
        ]
      );
    };

    kitty.extraConfig = ''
      background_blur 1

      shell_integration no-rc
      font_family Cascadia Code NF
      font_size 12

      # Override the entire base16 theme to remove macos_titlebar_color
      # Keep the colors but remove the problematic settings

      # The basic colors
      background #060f11
      foreground #e7e7e8
      selection_background #687275
      selection_foreground #e7e7e8

      # Cursor colors
      cursor #e7e7e8
      cursor_text_color #060f11

      # URL underline color when hovering with mouse
      url_color #6c7174

      # Kitty window border colors
      active_border_color #687275
      inactive_border_color #0e1618

      # OS Window titlebar colors (only set wayland, skip macos)
      wayland_titlebar_color #060f11
      # macos_titlebar_color REMOVED - this was causing the conflict

      # Tab bar colors
      active_tab_background #060f11
      active_tab_foreground #e7e7e8
      inactive_tab_background #0e1618
      inactive_tab_foreground #6c7174
      tab_bar_background #0e1618

      # The 16 terminal colors
      # normal
      color0 #060f11
      color1 #ff6286
      color2 #00d992
      color3 #ffb615
      color4 #738be3
      color5 #6377c0
      color6 #94e2d5
      color7 #e7e7e8

      # bright
      color8 #9ca3af
      color9 #ff6286
      color10 #00d992
      color11 #ffb615
      color12 #738be3
      color13 #6377c0
      color14 #94e2d5
      color15 #aa7ed0

      # extended base16 colors
      color16 #301b1d
      color17 #f2cdcd
      color18 #0e1618
      color19 #9ca3af
      color20 #6c7174
      color21 #301b1d

      # Your custom settings
      background_opacity 0.95
    '';
  };

  services.hyprpaper = {
    settings.preload = [
      "~/Wallpapers/2f-ai-mountains.png"
    ];
    settings.wallpaper = [
      ",~/Wallpapers/2f-ai-mountains.png"
    ];
  };

  gtk = {
    enable = true;
    iconTheme = {
      package = pkgs.papirus-icon-theme;
      name = "Papirus";
    };
  };

  wayland.windowManager.hyprland = {
    settings = {
      layerrule = [
        "blur,waybar"
        "blur,group"
        "blur,launcher"
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
          font_weight_inactive = "Bold"; 
          font_weight_active = "Heavy"; 
          height = 14;
          render_titles = true;
          scrolling = true;
          text_color = "rgba(000000ff)"; # Dark text

          "col.active" = "rgba(ffffffcc)"; # Same as workspace active (0.2 opacity)
          "col.inactive" = "rgba(ffffff66)"; # Transparent like inactive workspaces
          "col.locked_active" = "rgba(f53c3ccc)"; # Red version of active state
          "col.locked_inactive" = "rgba(ffffff40)";
          gradients = true;
        };
      };

      exec-once = [
        "systemctl --user import-environment PATH && systemctl --user restart xdg-desktop-portal.service"
      ];

      bind = [
        "$mainMod, V, exec, ${pkgs.cliphist}/bin/cliphist list | ${pkgs.fuzzel}/bin/fuzzel --dmenu | ${pkgs.cliphist}/bin/cliphist decode | ${pkgs.wl-clipboard}/bin/wl-copy"
        "$mainMod, G, togglegroup"
        "$mainMod, Return, exec, ${pkgs.kitty}/bin/kitty"
        "$mainMod, Y, exec, ykmanoath"
        "$mainMod, Q, killactive,"
        "$mainMod, E, exec, ${pkgs.nautilus}/bin/nautilus"
        "$mainMod, F, togglefloating,"
        "$mainMod, SPACE, exec, ${pkgs.fuzzel}/bin/fuzzel --icon-theme=Papirus"
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
      ];

      bindm = [
        "$mainMod, mouse:272, movewindow"
        "$mainMod, mouse:273, resizewindow"
      ];
    };
  };
}
