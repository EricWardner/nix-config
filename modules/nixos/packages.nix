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
        e2fsprogs
        tcpdump
        (ltrace.overrideAttrs { doCheck = false; })
        strace
        pciutils
        usbutils
        iw
        ethtool
        psmisc
        procfd
        nmap
        dnsutils
        file
        ripgrep
        wireguard-tools
      ]
      ++ cfg.extraDefaultPackages;
  };
}
