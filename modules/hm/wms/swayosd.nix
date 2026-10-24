{ config, lib, ... }:
let
  inherit (config.lib.stylix) colors;
  # Matches the bar's tray island and net-panel: a translucent pill over
  # Hyprland's blur (the "swayosd" layer rule in hypr/lua/rules.lua).
  style = builtins.toFile "swayosd.css" ''
    window#osd {
      border-radius: 999px;
      border: 1px solid alpha(#${colors.base05}, 0.1);
      box-shadow: inset 0 1px alpha(#${colors.base05}, 0.08);
      background: alpha(#${colors.base00}, 0.72);
      font-family: "${config.stylix.fonts.sansSerif.name}";
    }
    window#osd #container {
      margin: 12px 18px;
    }
    window#osd image,
    window#osd label {
      color: #${colors.base05};
    }
    window#osd progressbar:disabled,
    window#osd image:disabled {
      opacity: 0.5;
    }
    window#osd progressbar,
    window#osd segmentedprogress {
      min-height: 6px;
      border-radius: 999px;
      background: transparent;
      border: none;
    }
    window#osd trough,
    window#osd segment {
      min-height: inherit;
      border-radius: inherit;
      border: none;
      background: alpha(#${colors.base05}, 0.2);
    }
    window#osd progress,
    window#osd segment.active {
      min-height: inherit;
      border-radius: inherit;
      border: none;
      background: #${colors.base05};
    }
    window#osd segment {
      margin-left: 8px;
    }
    window#osd segment:first-child {
      margin-left: 0;
    }
  '';
in
{
  # On-screen popups for volume, brightness and media keys; the keys call
  # swayosd-client (hypr/hyprland.nix). The root libinput backend is left
  # out: it only adds the caps/num-lock popups, and Caps Lock is Compose.
  config = lib.mkIf config.modules.hyprland.enable {
    services.swayosd = {
      enable = true;
      stylePath = style;
    };
    systemd.user.services.swayosd.Service.Environment = [
      # GTK's software renderer draws the small popup just as well without
      # loading Mesa, like net-panel.
      "GSK_RENDERER=cairo"
    ];
    xdg.configFile."swayosd/config.toml".source = (
      builtins.toFile "swayosd-config.toml" ''
        [server]
        # wpctl's old -l 1.5 limit
        max_volume = 150
        min_brightness = 5
      ''
    );
  };
}
