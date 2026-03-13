{ pkgs, lib, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./disks.nix
    ../../modules/nixos
  ];
  modules = {
    hostName = "framework";
    grub = false;
    peripherals = {
      enable = true;
      scarlettRite.enable = true;
    };
  };
  boot.resumeDevice = "/dev/mapper/crypted";
  # Get offset with: sudo btrfs inspect-internal map-swapfile -r /.swapvol/swapfile
  boot.kernelParams = [ "resume_offset=533760" ];

  services.tlp.enable = lib.mkForce false;
  services.fwupd.enable = true;
  fonts.packages = [
    pkgs.nerd-fonts.jetbrains-mono
    pkgs.font-awesome
  ];
  hardware = {
    enableRedistributableFirmware = true;
    keyboard.zsa.enable = true;
  };

  system.stateVersion = "25.05";
}
