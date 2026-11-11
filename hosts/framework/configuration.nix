{
  pkgs,
  lib,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ./disks.nix
    ../../modules/nixos
  ];
  modules = {
    hostName = "framework";
    peripherals = {
      enable = true;
      scarlettRite.enable = true;
    };
  };
  boot.resumeDevice = "/dev/mapper/crypted";
  # Get offset with: sudo btrfs inspect-internal map-swapfile -r /.swapvol/swapfile
  boot.kernelParams = [ "resume_offset=533760" ];

  services.tlp.enable = lib.mkForce false;
  modules.powerProfiles.autoSwitch = true;
  # stable virtual keyboard for push-to-talk (see modules/nixos/peripherals)
  modules.peripherals.keyd.enable = true;
  services.fwupd.enable = true;
  # nixos-hardware turns this on; the reader is unused, and when its USB
  # controller died on resume fprintd hung sudo and stalled shutdown
  services.fprintd.enable = false;
  fonts.packages = [
    pkgs.nerd-fonts.jetbrains-mono
    pkgs.font-awesome
  ];
  hardware = {
    enableRedistributableFirmware = true;
    keyboard.zsa.enable = true;
  };

  boot.extraModprobeConfig = ''
    options cfg80211 ieee80211_regdom=US
  '';

  system.stateVersion = "25.05";
}
