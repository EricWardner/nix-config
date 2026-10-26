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

  # The Gather logo, a one-glyph font at U+FFF00 for Gather's workspace icon
  gatherSymbol = pkgs.callPackage ../../../../pkgs/gather-symbol { };

  # U+2002 EN SPACE between a workspace's number and its app icons: the icons
  # (Symbols Nerd Font) have no side bearings, and an en space spaces them as
  # the old Nerd-patched SF Pro did with a plain space
  enSpace = builtins.fromJSON ''"\u2002"'';
  wpctl = "${pkgs.wireplumber}/bin/wpctl";

  # Status icons are SF Symbols, Apple's icon set drawn to match SF Pro:
  # they share its stroke weight and baseline and space like text, so an
  # icon sits one ordinary space from its number. They ship inside SF Pro
  # as private-use characters (U+100000 up), named here because most
  # editors show them as boxes; the code points come from this SF Pro
  # build and could move if the font is updated. SF Symbols has no logos,
  # so the nix icon and the workspace app icons stay Nerd Font glyphs. The
  # bar-tools watchers use the same set (bar_tools::sf).
  sf = {
    cpu = "􀫥"; # U+100AE5 cpu
    memory = "􀫦"; # U+100AE6 memorychip
    thermometer = "􀇬"; # U+1001EC thermometer
    sunMin = "􀆫"; # U+1001AB sun.min
    sunMax = "􀆭"; # U+1001AD sun.max
    battery0 = "􀛪"; # U+1006EA battery.0
    battery25 = "􀛩"; # U+1006E9 battery.25
    battery50 = "􀺶"; # U+100EB6 battery.50
    battery75 = "􀺸"; # U+100EB8 battery.75
    battery100 = "􀛨"; # U+1006E8 battery.100
    batteryBolt = "􀢋"; # U+10088B battery.100.bolt
  };

  # Numbers beside icons are drawn a size smaller (14px against the bar's
  # 16px) so the icon leads; a relative size keeps the ratio if the bar's
  # font size changes. `rise` (1/1024 px) lifts them ~0.75px so they centre
  # on the icon instead of sitting on the 16px baseline. volume-watch
  # matches it (bar_tools::waybar::number).
  num = text: "<span size='87.5%' rise='768'>${text}</span>";

  # Start an app from a click in its own transient systemd scope. A plain
  # child of waybar stays in waybar.service's cgroup, so the monitor-hotplug
  # restart below would kill it.
  launch = cmd: "${pkgs.systemd}/bin/systemd-run --user --scope --collect --quiet -- ${cmd}";
  pavucontrol = launch "${pkgs.pavucontrol}/bin/pavucontrol";
  # webcam-watch sees the cameras come and go through inotify, so the
  # toggle needs no refresh signal.
  webcamToggle = "sudo /run/current-system/sw/bin/webcam-toggle toggle";
  # Each time it opens a camera with pan/tilt/zoom (the Brio's digital
  # ones count), cameractrls runs three helpers in turn to list gamepad,
  # MIDI and SpaceMouse controllers for steering it: ~0.8s of a ~1.6s
  # start. None are used here, so it lists none; the PTZ sliders remain.
  cameractrls = pkgs.cameractrls-gtk4.overrideAttrs (old: {
    postPatch = old.postPatch + ''
      substituteInPlace cameractrls.py --replace-fail \
        "self.controllers = get_ptz_hw_controllers(ptz_hw_executables)" \
        "self.controllers = []"
    '';
  });
  # Opens the camera settings, or closes them if they're already open,
  # instead of stacking another window: the app runs in a named scope that
  # the next click stops. GTK's software renderer skips loading Mesa.
  cameraSettings = pkgs.writeShellScript "camera-settings" ''
    if ${pkgs.systemd}/bin/systemctl --user --quiet is-active camera-settings.scope; then
      exec ${pkgs.systemd}/bin/systemctl --user stop camera-settings.scope
    fi
    export GSK_RENDERER=cairo
    exec ${pkgs.systemd}/bin/systemd-run --user --scope --collect --quiet \
      --unit=camera-settings -- ${cameractrls}/bin/cameractrlsgtk4
  '';

  # The record button's right-click menu (a GtkBuilder file; each item's id
  # names its entry in menu-actions)
  recordMenu = pkgs.writeText "record-menu.xml" ''
    <?xml version="1.0" encoding="UTF-8"?>
    <interface>
      <object class="GtkMenu" id="menu">
        <child>
          <object class="GtkMenuItem" id="folder">
            <property name="label">Open recordings folder</property>
          </object>
        </child>
        <child>
          <object class="GtkMenuItem" id="last">
            <property name="label">Last recording…</property>
          </object>
        </child>
      </object>
    </interface>
  '';
  # Thunar, through the file-manager D-Bus interface it starts on demand
  videosFolder = "${pkgs.systemd}/bin/busctl --user call org.freedesktop.FileManager1 /org/freedesktop/FileManager1 org.freedesktop.FileManager1 ShowFolders ass 1 file://${config.home.homeDirectory}/Videos ''";

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
    modules.hyprland.waybar.recordButton =
      mkEnableOption ''
        a record button beside the webcam icon (screen-record; Super+R does
        the same). The recording's progress shows after the clock either way''
      // {
        default = true;
      };
  };
  config = mkIf cfg.enable {
    # micctl for keybinds; the rest are handy to run by hand when debugging
    home.packages = [
      barTools
      gatherSymbol
    ];

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
          # A screen recording's progress follows the clock while one is
          # under way.
          modules-center = [
            "hyprland/window"
            "clock"
            "custom/recording"
          ];
          # The applets sit on a glass island (waybar.css): the tray, whose
          # applets (net-panel, blueman) cover network and bluetooth so those
          # have no modules of their own, led by the Do Not Disturb moon
          # (wms/notifications) while it's on. The row packs from the right
          # edge, so the island growing leftward for the moon moves nothing.
          # The status icons stay on the bare bar.
          modules-right = [
            "group/applets"
          ]
          ++ lib.optional cfg.recordButton "custom/record"
          ++ [
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
            format = "{name}${enSpace}{windows}";
            format-window-separator = enSpace;
            window-rewrite-default = "";
            window-rewrite = {
              "class<google-chrome>" = "";
              "class<firefox>" = "";
              "class<kitty>" = "󰆍";
              "class<com.mitchellh.ghostty>" = "󰆍";
              "class<code>" = "󰨞";
              "class<slack>" = "󰒱";
              "class<spotify>" = "󰓇";
              # U+FFF00, the Gather logo (gatherSymbol)
              "title<.* Gather .*>" = "󿼀";
              "class<.*(gather|work\\.tiberius\\.com).*>" = "󿼀";
              "title<(.*) - (.*) - Visual Studio Code>" = "[󰨞 $2]";
            };
          };

          "hyprland/window" = {
            format = "{class}";
            max-length = 20;
            rewrite = {
              "^(?!.*\\S).*" = "Desktop";
              "^com\\.mitchellh\\.ghostty$" = "Ghostty";
              "^com\\.mitchellh\\.ghostty\\.btop$" = "btop";
            };
          };

          "custom/nix" = {
            format = "󱄅";
            on-click = "${config.programs.vicinae.package}/bin/vicinae toggle";
            on-click-right = launch "system-menu";
            tooltip-format = "Left: App Launcher\nRight: System Menu";
          };

          # restart-interval only matters if a watcher ever exits
          "custom/webcam" = {
            exec = "${barTools}/bin/webcam-watch";
            return-type = "json";
            restart-interval = 5;
            # like mic/volume: middle mutes, right opens (or closes) the
            # settings app
            on-click = webcamToggle;
            on-click-middle = webcamToggle;
            on-click-right = "${cameraSettings}";
          };

          # Screen recording (home/tools/screen-record), started in its own
          # scope so a waybar restart can't kill a recording. The button
          # starts or stops; the status module after the clock shows the
          # selection, countdown and timer, and a finished recording opens
          # its preview.
          "custom/record" = {
            exec = "${barTools}/bin/record-watch button";
            return-type = "json";
            restart-interval = 5;
            on-click = launch "screen-record";
            menu = "on-click-right";
            menu-file = "${recordMenu}";
            menu-actions = {
              folder = videosFolder;
              # the newest recording's preview (capture-preview)
              last = launch "screen-record menu";
            };
          };
          "custom/recording" = {
            exec = "${barTools}/bin/record-watch status";
            return-type = "json";
            restart-interval = 5;
            on-click = launch "screen-record click";
          };

          "group/applets" = {
            orientation = "horizontal";
            modules = [
              "custom/dnd"
              "tray"
            ];
          };

          tray = {
            icon-size = 16; # matches the SF Symbols at the bar's 16px font
            # 16px icons + 24px spacing keep the 40px pitch of the status
            # icons beside the island
            spacing = 24;
          };

          cpu = {
            interval = 5;
            format = sf.cpu;
            format-alt = "${sf.cpu} ${num "{usage}%"}";
            # the class must be a valid app ID (with a dot) or ghostty ignores
            # it, and the floating rule in hypr/lua/rules.lua matches on it
            on-click-right = launch "${pkgs.ghostty}/bin/ghostty --class=com.mitchellh.ghostty.btop -e ${pkgs.btop}/bin/btop";
          };

          memory = {
            format = sf.memory;
            format-alt = "${sf.memory} ${num "{}%"}";
          };

          temperature = {
            critical-threshold = 80;
            format-critical = "{icon} ${num "{temperatureC}°C"}";
            format = "{icon}";
            format-alt = "{icon} ${num "{temperatureC}°C"}";
            format-icons = [ sf.thermometer ];
          };

          backlight = {
            format = "{icon}";
            format-alt = "{icon} ${num "{percent}%"}";
            format-icons = [
              sf.sunMin
              sf.sunMax
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

          battery = {
            format = "{icon}";
            format-charging = "${sf.batteryBolt} ${num "{capacity}%"}";
            format-plugged = "${sf.batteryBolt} ${num "{capacity}%"}";
            format-alt = "{icon} ${num "{capacity}%"}";
            format-icons = [
              sf.battery0
              sf.battery25
              sf.battery50
              sf.battery75
              sf.battery100
            ];
            format-full = sf.batteryBolt;
            tooltip-format = "{power}W {timeTo}";
            interval = 5;
            states = {
              warning = 30;
              critical = 15;
            };
          };

          # Left-click arms/disarms push-to-talk (pttd does the muting).
          "custom/mic" = {
            exec = "${barTools}/bin/mic-watch";
            return-type = "json";
            restart-interval = 5;
            on-click = "${barTools}/bin/micctl ptt";
            on-click-middle = "${barTools}/bin/micctl mute";
            on-click-right = pavucontrol;
            # no scroll actions: each tick would toggle mute, so scrolling
            # across the bar could unmute you
          };

          # Any volume change flashes the percentage and hover shows it; a
          # left-click keeps it shown, like cpu and memory.
          "custom/volume" = {
            exec = "${barTools}/bin/volume-watch";
            return-type = "json";
            format-alt = "{alt} ${num "{percentage}%"}";
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
