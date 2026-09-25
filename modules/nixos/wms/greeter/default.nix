{
  pkgs,
  config,
  lib,
  user,
  ...
}:
let
  inherit (lib) mkIf mkEnableOption;
  cfg = config.modules.greeter;
  tuigreet = "${pkgs.tuigreet}/bin/tuigreet";
  # Merged session .desktop files from every enabled DE/WM. tuigreet presents
  # them as a picker; --remember-user-session preselects whatever was chosen
  # last.
  sessions = "${config.services.displayManager.sessionData.desktops}/share/wayland-sessions";
in
{
  options = {
    modules.greeter.enable = mkEnableOption "Enable greetd/tuigreet greeter module" // {
      default = true;
    };
  };
  config = mkIf cfg.enable {
    services.greetd = {
      enable = true;
      settings = {
        # Auto-login straight into Hyprland on boot. greetd only runs
        # initial_session once per boot, so logging out drops to tuigreet
        # below rather than looping back into a fresh session.
        initial_session = {
          command = "${config.programs.hyprland.package}/bin/start-hyprland";
          user = user.username;
        };
        default_session = {
          command = "${tuigreet} --greeting 'Welcome to NixOS!' --asterisks --time --remember --remember-user-session --sessions ${sessions}";
          user = "greeter";
        };
      };
    };
    systemd.services.greetd.serviceConfig = {
      Type = "idle";
      StandardInput = "tty";
      StandardOutput = "tty";
      StandardError = "journal"; # Without this errors will spam on screen
      # Without these bootlogs will spam on screen
      TTYReset = true;
      TTYVHangup = true;
      TTYVTDisallocate = true;
    };
  };
}
