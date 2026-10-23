{
  config,
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
    grub = false;
    peripherals = {
      enable = true;
      scarlettRite.enable = true;
    };
  };
  # TEMPORARY, until the pinned nixpkgs includes e81ffa28fd (2026-10-19).
  # nixpkgs now signs kernel modules with kmodigest during `make
  # modules_install`, and the module aggregator merges every external
  # module's .ko.cer. framework-laptop-kmod (from nixos-hardware) still
  # copied its .ko by hand, so the system build failed with
  # "extra/framework_laptop.ko.cer: No such file or directory". This mirrors
  # the upstream fix: install through modules_install. mkForce replaces the
  # whole list, which only holds this module on this host.
  boot.extraModulePackages = lib.mkForce [
    (config.boot.kernelPackages.framework-laptop-kmod.overrideAttrs (old: {
      makeFlags = old.makeFlags ++ [
        "INSTALL_MOD_PATH=${placeholder "out"}"
        "INSTALL_MOD_DIR=extra"
        "DEPMOD=true"
      ];
      installTargets = [ "modules_install" ];
      installPhase = null;
    }))
  ];

  boot.resumeDevice = "/dev/mapper/crypted";
  # Get offset with: sudo btrfs inspect-internal map-swapfile -r /.swapvol/swapfile
  boot.kernelParams = [ "resume_offset=533760" ];

  services.tlp.enable = lib.mkForce false;
  modules.powerProfiles.autoSwitch = true;
  # stable virtual keyboard for push-to-talk (see modules/nixos/peripherals)
  modules.peripherals.keyd.enable = true;
  services.fwupd.enable = true;
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
