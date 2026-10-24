{ config, lib, ... }:
{
  # The password prompt for polkit, which GUI apps go through when they need
  # root: mounting an internal disk in Thunar, enrolling a fingerprint.
  # Without an agent in the session, polkitd turns those requests down
  # without asking. (Terminal tools like systemctl and fwupdmgr bring their
  # own text prompt. pkexec doesn't run at all: NixOS 26.11 made its setuid
  # wrapper opt-in, security.polkit.enablePkexecWrapper.)
  config = lib.mkIf config.modules.hyprland.enable {
    services.hyprpolkitagent.enable = true;
  };
}
