{
  config,
  lib,
  ...
}:
let
  inherit (lib) mkIf mkEnableOption;
  cfg = config.modules.cosmic;
in
{
  options = {
    modules.cosmic.enable = mkEnableOption "Enable COSMIC desktop module" // {
      default = true;
    };
  };
  config = mkIf cfg.enable {
    # COSMIC is native in nixpkgs on unstable and cached by cache.nixos.org,
    # so no nixos-cosmic flake input or extra cachix cache is needed. This
    # pulls in the whole DE: cosmic-session, panel, notifications, idle
    # daemon, and xdg-desktop-portal-cosmic (registered for
    # XDG_CURRENT_DESKTOP=COSMIC, so it doesn't collide with the hyprland
    # portal config).
    services.desktopManager.cosmic.enable = true;
    # COSMIC enables power-profiles-daemon for its power settings panel, but
    # ppd refuses to coexist with TLP (which nixos-hardware enables on
    # tiberius). Where TLP is in charge, keep it in charge; COSMIC just loses
    # the profile switcher there.
    services.power-profiles-daemon.enable = mkIf config.services.tlp.enable (lib.mkForce false);
    # Deliberately NOT services.displayManager.cosmic-greeter: it drives
    # greetd itself and would fight our services.greetd.settings. The shared
    # greetd/tuigreet module (../greeter) picks up COSMIC's session file
    # automatically.
  };
}
