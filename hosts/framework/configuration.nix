{ ... }:
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

  modules.powerProfiles.autoSwitch = true;
  # stable virtual keyboard for push-to-talk (see modules/nixos/peripherals)
  modules.peripherals.keyd.enable = true;
  services.fwupd.enable = true;
  # nixos-hardware turns this on; the reader is unused, and when its USB
  # controller died on resume fprintd hung sudo and stalled shutdown
  services.fprintd.enable = false;
  hardware = {
    enableRedistributableFirmware = true;
    keyboard.zsa.enable = true;
    # nixos-hardware turns the 32-bit graphics drivers on for Steam and
    # Wine, neither of which is here: 886 MiB of Mesa
    graphics.enable32Bit = false;
  };

  boot.extraModprobeConfig = ''
    options cfg80211 ieee80211_regdom=US
  '';

  system.stateVersion = "25.05";
}
