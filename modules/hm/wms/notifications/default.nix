{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkIf;
  inherit (config.lib.stylix) colors;

  # Do Not Disturb: `mako-dnd toggle` (Super+N) flips mako's do-not-disturb
  # mode, `mako-dnd off` (clicking the bar's moon) leaves it, and both tell
  # waybar to redraw the moon (signal 11); `mako-dnd status` is that
  # module's output.
  makoDnd = pkgs.writeShellScriptBin "mako-dnd" ''
    makoctl=${pkgs.mako}/bin/makoctl
    redraw() {
      ${pkgs.systemd}/bin/systemctl --user kill --kill-whom=main \
        --signal=SIGRTMIN+11 waybar.service
    }
    case "$1" in
      toggle)
        $makoctl mode -t do-not-disturb >/dev/null
        redraw
        ;;
      off)
        $makoctl mode -r do-not-disturb >/dev/null
        redraw
        ;;
      status)
        # The moon (moon.fill, SF Symbols U+1001BA, like Apple's Focus) is
        # always there and only hidden by CSS while off, so its space next
        # to the clock never comes and goes and the centre never shifts.
        if $makoctl mode | ${pkgs.gnugrep}/bin/grep -qx do-not-disturb; then
          printf '{"text":"\U001001BA","tooltip":"Do Not Disturb (click to turn off)","class":"on"}\n'
        else
          printf '{"text":"\U001001BA","tooltip":"","class":"off"}\n'
        fi
        ;;
      *)
        echo "usage: mako-dnd toggle|off|status" >&2
        exit 2
        ;;
    esac
  '';

  # Claude Code notifies through Ghostty, so its notifications carry
  # Ghostty's icon name (as the image-path hint) and no app name. mako can't
  # swap an icon, but it looks that name up in icon-path, so for these a
  # directory with a Claude spark filed under Ghostty's icon name stands in.
  claudeIcon = pkgs.runCommand "claude-notification-icon" { } ''
    mkdir -p $out/48x48/apps
    cp ${./claude.svg} $out/48x48/apps/com.mitchellh.ghostty.svg
  '';
  label = name: "<span size='85%%' alpha='60%%'>${name}</span>";
in
{
  config = mkIf config.modules.hyprland.enable {
    home.packages = [ makoDnd ];

    # The bar's moon, after the clock (wms/waybar), visible only while Do
    # Not Disturb is on. Clicking its hidden space does nothing.
    programs.waybar.settings.mainBar."custom/dnd" = {
      exec = "${makoDnd}/bin/mako-dnd status";
      return-type = "json";
      interval = "once";
      signal = 11;
      on-click = "${makoDnd}/bin/mako-dnd off";
    };

    # Styled here instead (stylix's target draws an opaque box with a 2px
    # border), in the palette, to match net-panel and swayosd.
    stylix.targets.mako.enable = false;

    services.mako.enable = true;
    services.mako.settings = {
      "default-timeout" = 5000;
      anchor = "top-right";
      width = 360;
      # tall enough for a few lines of body (the default 100px cuts it to one)
      height = 160;
      margin = "10";

      # A light card, so it stands out over the dark terminals it usually
      # lands on (a dark one matched them): the theme's foreground, 65%
      # opaque over Hyprland's blur (the "notifications" layer rule in
      # hypr/lua/rules.lua), dark text, a faint dark edge, rounded corners.
      background-color = "#${colors.base05}a6";
      border-color = "#${colors.base00}1a";
      border-size = 1;
      border-radius = 14;
      padding = "14,16";
      text-color = "#${colors.base00}";
      progress-color = "over #${colors.base0D}33";

      # The app's name small and dimmed over a bold title, like iOS
      font = "${config.stylix.fonts.sansSerif.name} 11";
      format = "${label "%a"}\\n<b>%s</b>\\n%b";

      # mako looks icons up only in these directories (themes by hand, no
      # inheritance); its default is /usr/share, which NixOS doesn't have.
      icon-path = lib.concatMapStringsSep ":" (d: "${config.home.profileDirectory}/share/${d}") [
        "icons/Papirus-Dark"
        "icons/hicolor"
        "pixmaps"
      ];
      max-icon-size = 40;
      icon-border-radius = 10;

      # Dismissed notifications Super+Shift+N (makoctl restore) can bring
      # back, newest first
      max-history = 20;

      # Ghostty's notifications have no app name to show; name it. Claude
      # Code's (titled "Claude Code") read as their own app: the spark, its
      # name above, and the message as the title. Sections later in name
      # order win, so the Claude one overrides the Ghostty one.
      "desktop-entry=com.mitchellh.ghostty".format = "${label "Ghostty"}\\n<b>%s</b>\\n%b";
      "summary=\"Claude Code\"" = {
        icon-path = "${claudeIcon}";
        format = "${label "Claude Code"}\\n<b>%b</b>";
      };
      # screen-record's "GIF saved" carries the GIF as its image: a bigger
      # preview than an app icon.
      "app-name=\"Screen recording\"".max-icon-size = 96;

      "urgency=low".text-color = "#${colors.base03}";
      "urgency=critical" = {
        border-color = "#${colors.base08}";
        default-timeout = 0;
      };

      # Do Not Disturb hides popups; they still arrive and go to history.
      # Critical ones and the YubiKey touch prompt (without it, sudo and
      # signing look hung) stay visible. Later sections win, and Home
      # Manager writes them in name order, so the exceptions come after.
      "mode=do-not-disturb".invisible = 1;
      "mode=do-not-disturb app-name=yubikey-touch-detector".invisible = 0;
      "mode=do-not-disturb urgency=critical".invisible = 0;

      # The touch prompt sits mid-screen like a dialog, so it's a dark card
      # (the light glass looked out of place there), edged in the green of
      # its Yubico logo, and it has no body.
      "app-name=yubikey-touch-detector" = {
        "icon-path" = "${config.home.homeDirectory}/.nix-profile/share/icons/hicolor";
        "max-icon-size" = 128;
        "default-timeout" = 0;
        anchor = "center";
        layer = "overlay";
        on-notify = "exec pw-play ${pkgs.sound-theme-freedesktop}/share/sounds/freedesktop/stereo/dialog-warning.oga";
        background-color = "#${colors.base00}eb";
        border-color = "#97c73b";
        border-size = 2;
        text-color = "#${colors.base05}";
        format = "${label "YubiKey"}\\n<b>%s</b>";
      };
    };
  };
}
