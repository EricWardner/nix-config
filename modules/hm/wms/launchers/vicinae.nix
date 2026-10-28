{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.lib.stylix) colors;

  # Light glass like the bar's islands once they open:
  # the theme's lightest colour, translucent over Hyprland's blur, with its
  # darkest as ink. The selected row is a pale accent with dark text: a dark
  # row outweighed the rest of the panel, and hid the labels at its right,
  # which vicinae draws in the muted colour whatever the row. Anything left
  # unset comes from vicinae's own light theme.
  #
  # vicinae draws the window, its footer and its rows at the window's
  # opacity, replacing any alpha in the theme's colour, so lighter shades are
  # mixed here instead: `mix "base0D" 0.45` is 45% accent in the panel
  # colour, `inkMix 0.08` 8% ink.
  mix =
    colour: amount:
    "#"
    +
      lib.concatMapStrings
        (
          channel:
          let
            other = lib.toInt colors."${colour}-rgb-${channel}";
            panel = lib.toInt colors."base05-rgb-${channel}";
          in
          lib.fixedWidthString 2 "0" (
            lib.toHexString (builtins.floor (panel + (other - panel) * amount + 0.5))
          )
        )
        [
          "r"
          "g"
          "b"
        ];
  inkMix = mix "base00";
  islandsTheme = {
    meta = {
      name = "islands";
      description = "Light glass, like the bar's islands";
      variant = "light";
      inherits = "vicinae-light";
    };
    colors = {
      core = {
        background = "#${colors.base05}";
        foreground = "#${colors.base00}";
        secondary_background = inkMix 0.08;
        border = "#8cffffff"; # the islands' light rim
        accent = "#${colors.base0D}";
        accent_foreground = "#${colors.base00}";
      };
      # vicinae lays the footer over the panel at the window's opacity again,
      # so no colour vanishes into it. This one, a touch darker than the
      # panel, comes out close to the frosted panel over dark windows and
      # the sky; over a white window it shows as a faint band.
      main_window.footer.background = inkMix 0.15;
      accents = {
        blue = "#${colors.base0D}";
        green = "#${colors.base0B}";
        magenta = "#${colors.base0E}";
        orange = "#${colors.base09}";
        purple = "#${colors.base0E}";
        red = "#${colors.base08}";
        yellow = "#${colors.base0A}";
        cyan = "#${colors.base0C}";
      };
      text = {
        muted = inkMix 0.75;
        placeholder = inkMix 0.55;
        selection = {
          background = "#${colors.base0D}";
          foreground = "#${colors.base00}";
        };
      };
      input = {
        border = inkMix 0.18;
        border_focus = "#${colors.base0D}";
      };
      list.item = {
        hover.background = inkMix 0.08;
        selection = {
          background = mix "base0D" 0.45;
          foreground = "#${colors.base00}";
          secondary_background = mix "base0D" 0.6;
          secondary_foreground = inkMix 0.75;
        };
      };
      grid.item = {
        background = inkMix 0.08;
        selection.outline = "#${colors.base00}";
      };
      scrollbars.background = inkMix 0.2;
      loading = {
        bar = "#${colors.base0D}";
        spinner = "#${colors.base00}";
      };
    };
  };

  # Waits (up to about 3 s) until no layer whose namespace matches the regex
  # in $1 is on screen: vicinae's window is "vicinae", its HUD "vicinae-hud".
  waitGone = pkgs.writeShellScript "vicinae-wait-gone" ''
    for _ in $(${pkgs.coreutils}/bin/seq 60); do
      ${pkgs.hyprland}/bin/hyprctl layers -j |
        ${pkgs.jq}/bin/jq -e --arg re "$1" '[.. | .namespace? // empty] | any(test($re))' >/dev/null ||
        exit 0
      ${pkgs.coreutils}/bin/sleep 0.05
    done
  '';
  # Starts a command and returns at once, once the layers matching $1 have
  # gone: setsid so vicinae doesn't wait on it, and a scope of its own so a
  # vicinae restart can't kill it (a recording, say).
  spawn = pkgs.writeShellScript "vicinae-spawn" ''
    wait=$1
    shift
    exec ${pkgs.util-linux}/bin/setsid -f \
      ${pkgs.systemd}/bin/systemd-run --user --scope --collect --quiet -- \
      ${pkgs.bash}/bin/bash -c '${waitGone} "$0" && exec "$@"' "$wait" "$@" \
      >/dev/null 2>&1 </dev/null
  '';
  # After the launcher closes: what opens next takes the keyboard
  afterLauncher = "${spawn} '^vicinae$'";
  # After the HUD fades too (1.5 s), so a screenshot doesn't catch it
  afterHud = "${spawn} '^vicinae'";

  grep = "${pkgs.gnugrep}/bin/grep";
  # The islands shell: notifications and Do Not Disturb (wms/islands)
  islands = "${pkgs.quickshell}/bin/qs ipc -c islands call";

  # A rounded tile in one of the theme's accents with a line glyph inked on
  # it, like the icons in the islands' panels. It reads on the launcher's
  # light rows and on its dark selected one alike.
  ink = "#${colors.base00}";
  tile =
    name: accent: glyph:
    pkgs.writeText "${name}.svg" ''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">
        <rect width="32" height="32" rx="8" fill="#${accent}"/>
        <g transform="translate(4 4)" fill="none" stroke="${ink}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${glyph}</g>
      </svg>
    '';
  glyphs = {
    record = ''<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="3.5" fill="${ink}" stroke="none"/>'';
    stop = ''<rect x="6.5" y="6.5" width="11" height="11" rx="2" fill="${ink}" stroke="none"/>'';
    play = ''<path d="M8 5.5v13l11-6.5z" fill="${ink}"/>'';
    folder = ''<path d="M3.5 7h6l2 2h9v10h-17z"/>'';
    area = ''<rect x="3.5" y="5" width="17" height="14" rx="2" stroke-dasharray="3 2.5"/>'';
    window = ''<rect x="3" y="4.5" width="18" height="15" rx="2.5"/><path d="M3 9h18"/>'';
    screen = ''<rect x="3" y="4.5" width="18" height="12" rx="2"/><path d="M8 20h8M12 16.5V20"/>'';
    text = ''<path d="M5 6.5V5h14v1.5M12 5v14M9 19h6"/>'';
    colour = ''<path d="M14.5 5.5l4 4M17 3.5a2.1 2.1 0 0 1 3 3l-2 2-3-3zM15.5 8.5L6 18l-2.5.5L4 16l9.5-9.5"/>'';
    moon = ''<path d="M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5z"/>'';
    bell = ''<path d="M6 16v-5a6 6 0 0 1 12 0v5l1.5 2h-15zM10 21h4"/>'';
    mic = ''<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21"/>'';
    micSlash = ''<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21M4 4l16 16"/>'';
    camera = ''<rect x="2.5" y="6.5" width="13" height="11" rx="2.5"/><path d="M15.5 10.5l6-3.5v10l-6-3.5"/>'';
    wifi = ''<path d="M2.5 9.5a14 14 0 0 1 19 0M5.5 12.8a9.5 9.5 0 0 1 13 0M8.6 16a5 5 0 0 1 6.8 0"/><circle cx="12" cy="19" r="1.2" fill="${ink}" stroke="none"/>'';
  };

  # Desktop actions in the launcher's search, as vicinae script commands.
  # In silent mode vicinae runs the script with its window still open, then
  # closes it and shows the first line of output in its HUD (a failing
  # script's line goes to a toast instead, and the window stays).
  actions = {
    record-area = {
      title = "Record an area";
      icon = tile "record" colors.base08 glyphs.record;
      keywords = [
        "screen recording"
        "video"
        "screencast"
        "capture"
      ];
      script = ''
        ${afterLauncher} ${islands} capture open record area
        echo "Drag to choose the area to record"
      '';
    };
    stop-recording = {
      title = "Stop the recording";
      icon = tile "stop" colors.base08 glyphs.stop;
      keywords = [
        "screen recording"
        "video"
        "end"
      ];
      script = ''
        case $(${islands} capture stop) in
          stopped) echo "Recording stopped" ;;
          *) echo "Nothing is being recorded" ;;
        esac
      '';
    };
    last-recording = {
      title = "Open the last recording";
      icon = tile "play" colors.base08 glyphs.play;
      keywords = [
        "screen recording"
        "video"
        "preview"
        "gif"
        "trim"
      ];
      script = ''
        ${islands} capture last
        echo "Opening the last recording"
      '';
    };
    recordings-folder = {
      title = "Open the recordings folder";
      icon = tile "folder" colors.base08 glyphs.folder;
      keywords = [
        "screen recording"
        "videos"
      ];
      script = ''
        ${pkgs.systemd}/bin/busctl --user call org.freedesktop.FileManager1 \
          /org/freedesktop/FileManager1 org.freedesktop.FileManager1 \
          ShowFolders ass 1 "file://$HOME/Videos" "" >/dev/null
        echo "Opening ~/Videos"
      '';
    };
    screenshot-area = {
      title = "Screenshot an area";
      icon = tile "area" colors.base0D glyphs.area;
      keywords = [
        "screenshot"
        "capture"
        "region"
      ];
      script = ''
        ${afterHud} ${islands} capture open screenshot area
        echo "Then drag to choose the area"
      '';
    };
    screenshot-window = {
      title = "Screenshot the focused window";
      icon = tile "window" colors.base0D glyphs.window;
      keywords = [
        "screenshot"
        "capture"
      ];
      script = ''
        ${afterHud} ${islands} capture now window
        echo "Taking the focused window"
      '';
    };
    screenshot-screen = {
      title = "Screenshot this screen";
      icon = tile "screen" colors.base0D glyphs.screen;
      keywords = [
        "screenshot"
        "capture"
        "monitor"
        "display"
      ];
      script = ''
        ${afterHud} ${islands} capture now screen
        echo "Taking this screen"
      '';
    };
    screen-text = {
      title = "Copy text from the screen";
      icon = tile "text" colors.base0C glyphs.text;
      keywords = [
        "ocr"
        "qr code"
        "screenshot"
      ];
      script = ''
        ${afterHud} ${islands} capture open text area
        echo "Then drag over the text to copy"
      '';
    };
    pick-colour = {
      title = "Pick a colour";
      icon = tile "colour" colors.base0E glyphs.colour;
      keywords = [
        "color"
        "colour picker"
        "hex"
        "eyedropper"
      ];
      script = ''
        ${afterHud} ${islands} capture open colour area
        echo "Then click to pick a colour"
      '';
    };
    do-not-disturb = {
      title = "Toggle Do Not Disturb";
      icon = tile "moon" colors.base0E glyphs.moon;
      keywords = [
        "notifications"
        "dnd"
        "focus"
        "quiet"
      ];
      script = ''
        state=$(${islands} notifications toggleDnd) || exit 1
        echo "Do Not Disturb $state"
      '';
    };
    last-notification = {
      title = "Show the last notification again";
      icon = tile "bell" colors.base0E glyphs.bell;
      keywords = [
        "notifications"
        "restore"
        "missed"
      ];
      script = ''
        case $(${islands} notifications restore) in
          restored) echo "Brought back the last notification" ;;
          *) echo "No notification to bring back" ;;
        esac
      '';
    };
    push-to-talk = {
      title = "Toggle push-to-talk";
      icon = tile "mic" colors.base0B glyphs.mic;
      keywords = [
        "ptt"
        "microphone"
        "mic"
      ];
      script = ''
        micctl ptt 2>&1 || exit 1
        if [ -e "$XDG_RUNTIME_DIR/ptt/armed" ]; then
          echo "Push-to-talk on: hold Right Alt to talk"
        else
          echo "Push-to-talk off"
        fi
      '';
    };
    mute-microphones = {
      title = "Mute or unmute the microphones";
      icon = tile "mic-slash" colors.base0B glyphs.micSlash;
      keywords = [
        "microphone"
        "mic"
        "mute"
      ];
      # micctl refuses while push-to-talk is armed. The mute takes ~60 ms
      # to show up in PipeWire, hence the pause before reading it back.
      script = ''
        out=$(micctl mute 2>&1) || { echo "$out"; exit 1; }
        sleep 0.3
        if ${pkgs.wireplumber}/bin/wpctl get-volume @DEFAULT_AUDIO_SOURCE@ | ${grep} -q MUTED; then
          echo "Microphones muted"
        else
          echo "Microphones on"
        fi
      '';
    };
    camera = {
      title = "Turn the camera on or off";
      icon = tile "camera" colors.base0A glyphs.camera;
      keywords = [
        "webcam"
        "video"
        "privacy"
      ];
      # The same sudo rule as the bar's camera icon (modules/nixos/peripherals)
      script = ''
        out=$(/run/wrappers/bin/sudo /run/current-system/sw/bin/webcam-toggle toggle 2>&1)
        case $out in
          "Cameras authorized") echo "Camera on" ;;
          "Cameras deauthorized") echo "Camera off" ;;
          *) echo "$out"; exit 1 ;;
        esac
      '';
    };
    wifi = {
      title = "Wi-Fi networks";
      icon = tile "wifi" colors.base0C glyphs.wifi;
      keywords = [
        "network"
        "internet"
        "wireless"
      ];
      script = ''
        ${islands} panel open control wifi
        echo "Wi-Fi"
      '';
    };
  };
  scriptCommand =
    name: action:
    pkgs.writeShellScript "vicinae-${name}" ''
      # @vicinae.schemaVersion 1
      # @vicinae.title ${action.title}
      # @vicinae.mode silent
      # @vicinae.packageName Desktop
      # @vicinae.icon ${action.icon}
      # @vicinae.keywords ${builtins.toJSON action.keywords}
      ${action.script}
    '';
in
{
  # Raycast-style launcher: apps, clipboard history (in place of cliphist),
  # a calculator, file search, and the desktop actions above. The server
  # stays resident (~230 MiB); Super+Space and Super+V (hypr/hyprland.nix)
  # and the bar's nix icon talk to it. The font comes from stylix's vicinae
  # target, the colours from the islands theme above.
  stylix.targets.vicinae.colors.enable = false;

  programs.vicinae = {
    enable = true;
    # Changes made in vicinae's settings window persist; the settings below
    # still win over them.
    mutableSettings = true;
    enableFirefoxIntegration = false; # Chrome, not Firefox
    systemd = {
      enable = true;
      # Like waybar, only under a Hyprland session.
      target = "hyprland-session.target";
    };
    themes.islands = islandsTheme;
    settings = {
      # The bar's tray island has room enough; no vicinae icon.
      tray.enabled = false;
      theme = {
        light.name = "islands";
        dark.name = "islands";
      };
      launcher_window = {
        # Translucent so Hyprland's blur shows through (the "vicinae" layer
        # rule in hypr/lua/rules.lua), with the islands' corners. vicinae
        # always centres itself on screen; it has no setting for where.
        opacity = lib.mkForce 0.8;
        rounding = 24;
      };
      # Start each app in its own transient scope. A plain child of the
      # server stays in vicinae.service's cgroup, along with every app
      # opened from it.
      providers.applications.preferences.launchPrefix = "${pkgs.systemd}/bin/systemd-run --user --scope --collect --quiet --";
    };
  };

  # vicinae finds script commands in its data directory and rescans it
  # every so often ("Reload Script Directories" does it at once).
  xdg.dataFile = lib.mapAttrs' (
    name: action: lib.nameValuePair "vicinae/scripts/${name}.sh" { source = scriptCommand name action; }
  ) actions;
}
