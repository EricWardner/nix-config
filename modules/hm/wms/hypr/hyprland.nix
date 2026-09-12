{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.modules.hyprland;
  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    ;
  inherit (builtins) map toString;

  # Binary paths
  ghostty = "${pkgs.ghostty}/bin/ghostty";
  thunar = "${pkgs.thunar}/bin/thunar";
  fuzzel = "${pkgs.fuzzel}/bin/fuzzel";
  cliphist = "${pkgs.cliphist}/bin/cliphist";
  wl-copy = "${pkgs.wl-clipboard}/bin/wl-copy";
  brightnessctl = "${pkgs.brightnessctl}/bin/brightnessctl";
  grim = "${pkgs.grim}/bin/grim";
  slurp = "${pkgs.slurp}/bin/slurp";
  swappy = "${pkgs.swappy}/bin/swappy";
  playerctl = "${pkgs.playerctl}/bin/playerctl";
  btop = "${pkgs.btop}/bin/btop";
  slack = "${pkgs.slack}/bin/slack";
  chrome = "${pkgs.google-chrome}/bin/google-chrome-stable";
  toLua = lib.generators.toLua { };
  commands = {
    terminal = ghostty;
    files = thunar;
    launcher = fuzzel;
    clipboard = "${cliphist} list | ${fuzzel} --dmenu | ${cliphist} decode | ${wl-copy}";
    oath = "oath 19125157";
    gather = "launch-webapp https://app.gather.town/app/V383EJ8uFnnNFtez/Grail";
    lock = "${pkgs.systemd}/bin/loginctl lock-session";
    keyboardBrighter = "${brightnessctl} -d '*::kbd_backlight' set +33%";
    keyboardDimmer = "${brightnessctl} -d '*::kbd_backlight' set 33%-";
    screenshot = ''${grim} -g "$(${slurp})" - | ${swappy} -f -'';
    record = "wf-recorder-toggle";
    volumeUp = "volume-action up";
    volumeDown = "volume-action down";
    volumeMute = "volume-action mute";
    micMute = "mic-action mute";
    brighter = "${brightnessctl} set 5%+";
    dimmer = "${brightnessctl} set 5%-";
    mediaNext = "${playerctl} next";
    mediaPlayPause = "${playerctl} play-pause";
    mediaPrevious = "${playerctl} previous";
  };
  launchOnWorkspace =
    command: workspace:
    "${pkgs.hyprland}/bin/hyprctl dispatch "
    + lib.escapeShellArg "hl.dsp.exec_cmd(${toLua command}, ${toLua { inherit workspace; }})";
in
{
  options = {
    modules.hyprland.enable = mkEnableOption "Enable hyprland window Manager" // {
      default = true;
    };
    modules.hyprland.monitors = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            transform = mkOption {
              type = types.ints.between 0 7;
              default = 0;
              description = "Monitor rotation/flip: 0 normal, 1–3 rotations, 4–7 flipped.";
            };
            name = mkOption {
              type = types.str;
              example = "DP-1";
            };

            resolution = mkOption {
              type = types.either types.str (
                types.submodule {
                  options = {
                    width = mkOption {
                      type = types.int;
                      example = 1920;
                    };
                    height = mkOption {
                      type = types.int;
                      example = 1080;
                    };
                    refreshRate = mkOption {
                      type = types.int;
                      default = 60;
                    };
                  };
                }
              );
              default = "preferred";
              example = "highres";
              description = ''
                Monitor resolution. Can be:
                - "highres" - Highest supported resolution
                - "preferred" - Use monitor's preferred mode
                - "highrr" - Highest supported refresh rate
                - { width = 1920; height = 1080; refreshRate = 60; } - Explicit resolution
              '';
            };

            # DEPRECATED: Keep for backwards compatibility
            width = mkOption {
              type = types.nullOr types.int;
              default = null;
            };
            height = mkOption {
              type = types.nullOr types.int;
              default = null;
            };
            refreshRate = mkOption {
              type = types.nullOr types.int;
              default = null;
            };

            scale = mkOption {
              type = types.oneOf [
                types.str
                types.ints.positive
                types.positiveFloat
              ];
              default = "1";
            };
            position = mkOption {
              type = types.str;
              default = "auto";
            };
            enabled = mkOption {
              type = types.bool;
              default = true;
            };
            workspace = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Default workspace to bind to this monitor.";
            };
          };
        }
      );
      default = [ ];
    };
    modules.hyprland.mainMod = mkOption {
      type = types.str;
      default = "SUPER";
      example = "CTRL";
      description = "The main modifier key for Hyprland bindings.";
    };
  };
  config = mkIf cfg.enable {
    wayland.windowManager.hyprland = {
      enable = true;
      # Explicit because home.stateVersion predates Home Manager's Lua default.
      configType = "lua";
      package = null;
      portalPackage = null;
      xwayland.enable = true;
      systemd = {
        enable = true;
        variables = [ "--all" ];
        # Run only after HM imports the complete environment and starts the
        # session target. Chromium caches portal availability on first launch.
        # Setting this option replaces HM's default list, so keep its target
        # stop/start commands before app startup.
        extraCommands = [
          "systemctl --user stop hyprland-session.target"
          "systemctl --user start hyprland-session.target"
          "systemctl --user restart xdg-desktop-portal.service"
          (launchOnWorkspace slack "special:chat silent")
          (launchOnWorkspace commands.gather "special:chat silent")
          (launchOnWorkspace chrome "1 silent")
        ];
      };
      extraLuaFiles = {
        bindings = ./lua/bindings.lua;
        animations = ./lua/animations.lua;
        rules = ./lua/rules.lua;
        nix = {
          autoLoad = false;
          content =
            "return "
            + toLua {
              mainMod = cfg.mainMod;
              inherit commands;
            };
        };
      };
      extraConfig = ''
        -- Waybar and hyprpaper are supervised by their systemd user services.
        hl.on("hyprland.start", function()
          hl.exec_cmd(${toLua "${pkgs.networkmanagerapplet}/bin/nm-applet --indicator"})
          hl.exec_cmd(${toLua ghostty}, { workspace = "1 silent" })
        end)
      '';
      settings =
        let
          inherit (config.lib.stylix) colors;
          rgb = color: "rgb(${color})";
          activeGradient = {
            colors = [
              (rgb colors.base0B)
              (rgb colors.base0A)
            ];
            angle = 45;
          };
          inactiveGradient = rgb colors.base00;

          # Helper function to build resolution string
          buildResolution =
            m:
            if builtins.isAttrs m.resolution then
              # Structured resolution
              "${toString m.resolution.width}x${toString m.resolution.height}@${toString m.resolution.refreshRate}"
            else if m.width != null && m.height != null then
              # Backwards compatibility
              "${toString m.width}x${toString m.height}@${
                toString (if m.refreshRate != null then m.refreshRate else 60)
              }"
            else
              # String resolution (preferred, highrr, highres, etc.)
              m.resolution;
        in
        {
          env =
            lib.mapAttrsToList
              (name: value: {
                _args = [
                  name
                  value
                ];
              })
              {
                XCURSOR_SIZE = "24";
                HYPRCURSOR_SIZE = "24";
                GDK_BACKEND = "wayland,x11,*";
                QT_QPA_PLATFORM = "wayland;xcb";
                QT_STYLE_OVERRIDE = "kvantum";
                SDL_VIDEODRIVER = "wayland";
                MOZ_ENABLE_WAYLAND = "1";
                ELECTRON_OZONE_PLATFORM_HINT = "wayland";
                OZONE_PLATFORM = "wayland";
                XDG_SESSION_TYPE = "wayland";
                XDG_CURRENT_DESKTOP = "Hyprland";
                XDG_SESSION_DESKTOP = "Hyprland";
                XCOMPOSEFILE = "${config.home.homeDirectory}/.XCompose";
              };

          monitor =
            map (m: {
              output = m.name;
              disabled = !m.enabled;
              mode = buildResolution m;
              inherit (m) position scale transform;
            }) cfg.monitors
            ++ [
              {
                output = "";
                mode = "preferred";
                position = "auto";
                scale = 1;
              }
            ];

          workspace_rule = [
            {
              workspace = "special:monitor";
              on_created_empty = "${ghostty} -e ${btop}";
            }
            {
              workspace = "special:chat";
              monitor = "eDP-1";
            }
          ]
          ++ map (m: {
            workspace = m.workspace;
            monitor = m.name;
            default = true;
          }) (lib.filter (m: m.enabled && m.workspace != null) cfg.monitors);

          # Home Manager renders this as hl.config(); Stylix merges colors here.
          config = {
            xwayland = {
              force_zero_scaling = false;
            };

            cursor = {
              no_hardware_cursors = 1;
              hide_on_key_press = true;
            };

            ecosystem = {
              no_update_news = true;
            };

            # Omarchy input config
            input = {
              kb_layout = "us";
              kb_options = "compose:caps";
              repeat_rate = 40;
              repeat_delay = 600;
              numlock_by_default = true;
              follow_mouse = 1;
              sensitivity = 0;

              touchpad = {
                natural_scroll = true;
                scroll_factor = 0.4;
              };
            };

            # Omarchy look and feel
            general = {
              "col.active_border" = lib.mkDefault activeGradient;
              "col.inactive_border" = lib.mkDefault inactiveGradient;
              gaps_in = 4;
              gaps_out = 8;
              border_size = 2;
              resize_on_border = false;
              allow_tearing = false;
              layout = "dwindle";
            };

            decoration = {
              rounding = 12;

              shadow = {
                enabled = true;
                range = 8;
                render_power = 2;
                color = lib.mkForce "rgba(00000040)";
              };

              blur = {
                enabled = true;
                size = 4;
                passes = 2;
                special = true;
                xray = true;
                popups = true;
              };
            };

            animations.enabled = true;

            dwindle = {
              preserve_split = true;
              force_split = 2; # Always split on the right
            };

            master = {
              new_status = "master";
            };

            group = {
              "col.border_active" = lib.mkDefault activeGradient;
              "col.border_inactive" = lib.mkDefault inactiveGradient;

              groupbar = {
                font_size = 12;
                font_family = "sans-serif";
                font_weight_active = "ultraheavy";
                font_weight_inactive = "normal";
                indicator_height = 0;
                indicator_gap = 5;
                height = 22;
                gaps_in = 5;
                gaps_out = 0;
                text_color = lib.mkDefault (rgb colors.base05);
                text_color_inactive = "rgba(${colors.base04}90)";
                "col.active" = lib.mkForce "rgba(${colors.base0D}bf)";
                "col.inactive" = lib.mkForce "rgba(${colors.base03}80)";
                gradients = true;
                gradient_rounding = 0;
                gradient_round_only_edges = false;
              };
            };

            misc = {
              disable_hyprland_logo = true;
              disable_splash_rendering = true;
              focus_on_activate = true;
              anr_missed_pings = 3;
              on_focus_under_fullscreen = 1;
              key_press_enables_dpms = true;
              mouse_move_enables_dpms = true;
            };

          };
        };
    };

    # HM normally generates this only when it also installs the compositor.
    xdg.configFile."hypr/.luarc.json".text = builtins.toJSON {
      workspace.library = [ "${pkgs.hyprland}/share/hypr/stubs" ];
      diagnostics.globals = [ "hl" ];
    };
  };
}
