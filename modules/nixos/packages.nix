{
  pkgs,
  config,
  lib,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.modules;
in
{
  options = {
    modules.extraDefaultPackages = mkOption {
      type = types.listOf types.package;
      default = [ ];
      description = "Additional default packages to be installed in the system.";
    };
  };
  config = {
    environment.systemPackages =
      with pkgs;
      [
        pavucontrol
        git
        vim
        unityhub
        e2fsprogs
        tcpdump
        ltrace
        strace
        pciutils
        usbutils
        psmisc
        procfd
        nmap
        dnsutils
        file
      ]
      ++ cfg.extraDefaultPackages;
  };
}
