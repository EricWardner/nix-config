{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkIf;

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

    services.mako.enable = true;
    services.mako.settings = {
      "default-timeout" = 5000;
      border-radius = 12;
      padding = "12";
      margin = "12";
      anchor = "top-right";
      border-size = 2;
      # Dismissed notifications Super+Shift+N (makoctl restore) can bring
      # back, newest first
      max-history = 20;

      # Do Not Disturb hides popups; they still arrive and go to history.
      # Critical ones and the YubiKey touch prompt (without it, sudo and
      # signing look hung) stay visible. Later sections win, and Home
      # Manager writes them in name order, so the exceptions come after.
      "mode=do-not-disturb".invisible = 1;
      "mode=do-not-disturb app-name=yubikey-touch-detector".invisible = 0;
      "mode=do-not-disturb urgency=critical".invisible = 0;

      "app-name=yubikey-touch-detector" = {
        "icon-path" = "${config.home.homeDirectory}/.nix-profile/share/icons/hicolor";
        "max-icon-size" = 128;
        "default-timeout" = 0;
        anchor = "center";
        layer = "overlay";
        on-notify = "exec pw-play ${pkgs.sound-theme-freedesktop}/share/sounds/freedesktop/stereo/dialog-warning.oga";
      };
    };
  };
}
