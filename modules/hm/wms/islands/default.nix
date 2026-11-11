{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkIf mkEnableOption mkOption;
  cfg = config.modules.hyprland.islands;
  inherit (config.lib.stylix) colors;

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
  # The camera icon's right click: opens the camera settings, or closes them
  # if they're already open, instead of stacking another window. The app
  # runs in a named scope that the next click stops. GTK's software renderer
  # skips loading Mesa.
  cameraSettings = pkgs.writeShellScriptBin "camera-settings" ''
    if ${pkgs.systemd}/bin/systemctl --user --quiet is-active camera-settings.scope; then
      exec ${pkgs.systemd}/bin/systemctl --user stop camera-settings.scope
    fi
    export GSK_RENDERER=cairo
    exec ${pkgs.systemd}/bin/systemd-run --user --scope --collect --quiet \
      --unit=camera-settings -- ${cameractrls}/bin/cameractrlsgtk4
  '';
  # The capture overlay's work (shell/Capture.qml): cropping, recording,
  # reading text, picking colours, and the preview
  islandsCapture = pkgs.writeShellApplication {
    name = "islands-capture";
    runtimeInputs = with pkgs; [
      grim
      imagemagick
      wl-screenrec
      ffmpeg
      wl-clipboard-rs
      libnotify
      qrtool
      # English is all it reads; every language would be ~650 MB
      (tesseract.override { enableLanguages = [ "eng" ]; })
      coreutils
      findutils
      gawk
      gnugrep
      gnused
      (import ./capture-preview.nix { inherit config pkgs; })
    ];
    text = builtins.readFile ./islands-capture;
  };
  islandsSharePick = pkgs.writeShellApplication {
    name = "islands-share-pick";
    runtimeInputs = with pkgs; [
      quickshell
      coreutils
      gawk
    ];
    text = builtins.readFile ./islands-share-pick;
  };
  # The work calendar's events for the bar (shell/Events.qml), from its
  # secret iCal address in the keyring
  islandsCalendar =
    pkgs.writers.writePython3Bin "islands-calendar"
      {
        libraries = with pkgs.python3Packages; [
          icalendar
          recurring-ical-events
        ];
        flakeIgnore = [ "E501" ];
      }
      (
        builtins.replaceStrings [ "@secretTool@" ] [ "${pkgs.libsecret}/bin/secret-tool" ] (
          builtins.readFile ./islands-calendar.py
        )
      );
  islandsWeather = pkgs.writeShellApplication {
    name = "islands-weather";
    runtimeInputs = with pkgs; [
      curl
      jq
      coreutils
    ];
    text = builtins.readFile ./islands-weather;
  };
  # Claude Code's prompt and agent hooks (~/.claude/settings.json) call it to
  # put a prompt still being worked on in the job island
  islandsClaudeJob = pkgs.writeShellApplication {
    name = "islands-claude-job";
    runtimeInputs = with pkgs; [
      jq
      coreutils
      util-linux
    ];
    text = builtins.readFile ./islands-claude-job;
  };
  # The control centre's load line opens it. The class must be a valid app
  # ID (with a dot) or ghostty ignores it; the floating rule in
  # hypr/lua/rules.lua matches it.
  systemMonitor = pkgs.writeShellScriptBin "system-monitor" ''
    exec ${pkgs.ghostty}/bin/ghostty --class=com.mitchellh.ghostty.btop -e ${pkgs.btop}/bin/btop
  '';
in
{
  # The islands desktop shell (Quickshell): the bar, the islands that grow
  # out of it (notifications, the volume popup, the notification and control
  # centres, Wi-Fi, pairing and password prompts), the notification server
  # and the polkit agent. It replaced waybar, mako, swayosd, net-panel,
  # blueman's applet and hyprpolkitagent. Home Manager installs a copy as
  # the `islands` config, which the service below runs. To work on it with
  # reload on every save:
  #
  #   systemctl --user stop islands
  #   qs -p ~/nix-config/modules/hm/wms/islands/shell
  #
  # (Run a second copy beside the service with ISLANDS_NO_AGENT=1, so it
  # leaves the prompts, polkit's too, to the running one.)
  options.modules.hyprland.islands = {
    enable = mkEnableOption "the islands Quickshell shell" // {
      default = true;
    };
    temperatureSensor = mkOption {
      type = lib.types.str;
      default = "/sys/class/thermal/thermal_zone0/temp";
      description = ''
        The file the bar reads the temperature from, in millidegrees. A
        shell glob, so a hwmon directory whose number changes between boots
        can be matched.
      '';
    };
    powerSensor = mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        The file the battery page reads the chip's power draw from, in
        microwatts (an AMD APU's amdgpu power1_average, say), as a shell
        glob; "" leaves it out.
      '';
    };
    fanSensor = mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        The file the battery page reads the fan's speed from, in rpm, as a
        shell glob; "" leaves it out.
      '';
    };
    temperatureUnit = mkOption {
      type = lib.types.enum [
        "fahrenheit"
        "celsius"
      ];
      default = "fahrenheit";
      description = "The weather island's temperatures.";
    };
  };

  config = mkIf (config.modules.hyprland.enable && cfg.enable) {
    home.packages = [
      # nixpkgs' build is in cache.nixos.org; the upstream flake's isn't,
      # and overriding it would compile it locally on every Qt update
      pkgs.quickshell
      # Push-to-talk (pttd), micctl for keybinds, and the status watchers
      # the bar runs (pkgs/bar-tools)
      pkgs.bar-tools
      # The Gather logo, a one-glyph font at U+FFF00 for Gather's workspace
      # icon
      pkgs.gather-symbol
      cameraSettings
      systemMonitor
      # the brightness keys go through the shell (shell/Osd.qml)
      pkgs.brightnessctl
      # NetworkManager's secret agent, BlueZ's pairing agent and
      # gnome-keyring's prompter, whose questions the shell asks in its
      # centre island (shell/Agent.qml)
      pkgs.islands-agent
      islandsCapture
      islandsCalendar
      islandsWeather
      islandsClaudeJob
      # nm-connection-editor, behind the Wi-Fi page's "Network settings…"
      pkgs.networkmanagerapplet
    ];

    xdg.configFile."quickshell/islands".source = ./shell;

    # Tells the bar what each terminal is running, for its job island
    # (shell/Jobs.qml)
    programs.zsh.initContent = lib.mkAfter (builtins.readFile ./islands-jobs.zsh);

    # blueman-manager (Bluetooth settings…) starts blueman's applet, whose
    # agent would take pairing from islands-agent, with a tray icon
    dconf.settings."org/blueman/general".plugin-list = [
      "!AuthAgent"
      "!StatusNotifierItem"
    ];

    # Screen shares are chosen in the shell's capture overlay. Joined to the
    # restore-token setting from the Hyprland module; the portal reads it at
    # start.
    xdg.configFile."hypr/xdph.conf".text = ''
      screencopy:custom_picker_binary = ${islandsSharePick}/bin/islands-share-pick
    '';

    # The stylix theme for shell/Theme.qml, and this machine's settings for
    # shell/Host.qml. They live outside the config directory so a checkout
    # run with `qs -p` finds them too.
    xdg.configFile."islands/theme.json".text = builtins.toJSON {
      colours = lib.genAttrs [
        "base00"
        "base01"
        "base02"
        "base03"
        "base04"
        "base05"
        "base06"
        "base07"
        "base08"
        "base09"
        "base0A"
        "base0B"
        "base0C"
        "base0D"
        "base0E"
        "base0F"
      ] (name: "#${colors.${name}}");
      fonts = {
        sans = config.stylix.fonts.sansSerif.name;
        mono = config.stylix.fonts.monospace.name;
      };
    };
    xdg.configFile."islands/config.json".text = builtins.toJSON {
      inherit (cfg)
        temperatureSensor
        temperatureUnit
        powerSensor
        fanSensor
        ;
      attentionSound = "${pkgs.sound-theme-freedesktop}/share/sounds/freedesktop/stereo/dialog-warning.oga";
    };

    # Kept alive by systemd, only under a Hyprland session. Quickshell's
    # crash handler would restart it in place behind a crash report window,
    # where systemd can't see it; off, a crash ends the process and systemd
    # starts a new one. The start-rate limit is off so a burst of crashes
    # (a monitor hotplug bug, say) can't leave the session without a bar.
    systemd.user.services.islands = {
      Unit = {
        Description = "islands, the Quickshell desktop shell";
        After = [ "hyprland-session.target" ];
        PartOf = [ "hyprland-session.target" ];
        StartLimitIntervalSec = 0;
        # A new config, agent or watchers: restart into them on switch. The
        # theme and settings files are read once, at start.
        X-Restart-Triggers = [
          "${./shell}"
          "${pkgs.islands-agent}"
          "${pkgs.bar-tools}"
          "${config.xdg.configFile."islands/theme.json".source}"
          "${config.xdg.configFile."islands/config.json".source}"
        ];
      };
      Service = {
        # The job island watches this for the shells' files (shell/Jobs.qml)
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p %t/islands/jobs";
        ExecStart = "${pkgs.quickshell}/bin/qs -c islands";
        Environment = [
          "QS_DISABLE_CRASH_HANDLER=1"
          # Apps' and notifications' icons, from the GTK apps' theme
          "QS_ICON_THEME=${config.gtk.iconTheme.name}"
          # The agent is handed the keyring's and the networks' passwords:
          # this build of it, not whichever islands-agent is first on PATH
          # (shell/Agent.qml)
          "ISLANDS_AGENT=${lib.getExe pkgs.islands-agent}"
        ];
        Restart = "always";
        RestartSec = 1;
      };
      Install.WantedBy = [ "hyprland-session.target" ];
    };

    # Annotating a screenshot, from the preview's Annotate or run by hand.
    # Enter copies the result and closes; Ctrl+S saves it (over a saved
    # screenshot, or a new file in ~/Pictures/Screenshots for one not saved
    # yet).
    programs.satty = {
      enable = true;
      settings = {
        general = {
          copy-command = "${pkgs.wl-clipboard-rs}/bin/wl-copy";
          actions-on-enter = [
            "save-to-clipboard"
            "exit"
          ];
          output-filename = "~/Pictures/Screenshots/%m-%d-%Y-%H-%M-%S.png";
          initial-tool = "arrow";
          no-window-decoration = true;
          # An image too big for the screen opens scaled down to fit, not
          # at its own size in pixels, which a whole screen's is well past
          resize.mode = "smart";
          # Named for Hyprland's float rule (rules.lua)
          app-id = "com.gabm.satty";
        };
        font = {
          family = config.stylix.fonts.sansSerif.name;
          style = "Regular";
        };
      };
    };

    # Push-to-talk (pkgs/bar-tools/src/bin/pttd.rs): while armed from the mic
    # icon, every mic stays muted except while Right Alt is held. It reads
    # keyd's virtual keyboard (stable by-id symlink, see
    # modules/nixos/peripherals), so real keyboards coming and going never
    # matter, and reopens it if keyd itself restarts. User service (you're in
    # the `input` group) on graphical-session.target, unlike the bar: it's
    # evdev + audio with no compositor dependency, and a shell crash must
    # never leave a mic open.
    systemd.user.services.pttd = {
      Unit = {
        Description = "Push-to-talk (hold Right Alt while armed)";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
        StartLimitIntervalSec = 0;
      };
      Service = {
        ExecStart = "${pkgs.bar-tools}/bin/pttd /dev/input/by-id/keyd-virtual-keyboard-event-kbd";
        Restart = "always";
        RestartSec = 1;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
