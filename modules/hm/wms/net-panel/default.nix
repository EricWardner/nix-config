{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.lib.stylix) colors;

  # The Wi-Fi and network panel behind the tray icon (pkgs/net-panel), in
  # place of nm-applet: the icon, the panel and NetworkManager's secret agent
  # (password prompts) in one process.
  netPanel = pkgs.callPackage ../../../../pkgs/net-panel { };

  # Loaded over the panel's built-in stylesheet: the theme's colours and the
  # desktop font, so it matches the bar's glass island.
  theme = pkgs.writeText "net-panel-theme.css" ''
    @define-color np_fg #${colors.base05};
    @define-color np_bg alpha(#${colors.base00}, 0.72);
    @define-color np_accent #${colors.base0D};
    @define-color np_on_accent #${colors.base00};
    @define-color np_warn #${colors.base0A};

    .panel {
      font-family: "${config.stylix.fonts.sansSerif.name}";
    }
  '';
in
{
  config = lib.mkIf config.modules.hyprland.enable {
    home.packages = [
      netPanel
      # nm-connection-editor, behind "Network settings…"
      pkgs.networkmanagerapplet
    ];

    # Like the bar: kept alive by systemd, only under a Hyprland session. It
    # re-registers its tray icon whenever the tray host (the islands bar)
    # restarts.
    systemd.user.services.net-panel = {
      Unit = {
        Description = "Network panel and tray icon";
        After = [ "hyprland-session.target" ];
        PartOf = [ "hyprland-session.target" ];
        StartLimitIntervalSec = 0;
      };
      Service = {
        ExecStart = lib.concatStringsSep " " [
          (lib.getExe netPanel)
          "--css ${theme}"
          "--icon-color ${colors.base05}"
          "--editor ${pkgs.networkmanagerapplet}/bin/nm-connection-editor"
          # Apps it opens get their own scope, outside this service's cgroup.
          "--systemd-run ${pkgs.systemd}/bin/systemd-run"
        ];
        # GTK's software renderer draws this small panel just as well and
        # halves its memory (~35 MiB PSS vs ~70 with Mesa loaded for GL).
        Environment = [ "GSK_RENDERER=cairo" ];
        Restart = "always";
        RestartSec = 1;
      };
      Install.WantedBy = [ "hyprland-session.target" ];
    };
  };
}
