{
  pkgs,
  lib,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ./disko-config.nix
  ];

  boot.extraModprobeConfig = ''
    options snd-hda-intel model=dell-headset-multi
  '';

  modules = {
    hostName = "nixtop";
    peripherals = {
      enable = true;
      obs.enable = true;
      scarlettRite.enable = true;
      dellXpsEqualizer.enable = true;
    };
  };

  services.xserver.videoDrivers = ["nvidia"];
  hardware.nvidia.prime.sync.enable = lib.mkForce true;
  hardware.nvidia.prime.offload.enable = lib.mkForce false;
  hardware.nvidia.modesetting.enable = lib.mkForce true;

  # Add the required NVIDIA environment variables globally
  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "nvidia";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    NVD_BACKEND = "direct"; # For hardware video acceleration
  };

  fonts.packages = [
    pkgs.nerd-fonts.jetbrains-mono
    pkgs.font-awesome
  ];

  # Lid close and power button behavior
  services.logind = {
    lidSwitch = "suspend";
    lidSwitchDocked = "suspend"; # or "ignore" if you want it to stay awake when docked

    extraConfig = ''
      # Suspend after 20 minutes of inactivity
      IdleAction=suspend
      IdleActionSec=20min

      # Handle lid switch when on external power
      HandleLidSwitchExternalPower=suspend

      # Short press = suspend, long press = poweroff
      HandlePowerKey=suspend
      PowerKeyIgnoreInhibited=no

      # Long press duration (default is 2s, you can adjust)
      HoldoffTimeoutSec=2s
      HandlePowerKeyLongPress=poweroff      
    '';
  };

  # Basic power management
  powerManagement = {
    enable = true;
  };

  # Advanced power management with TLP
  services.tlp = {
    enable = true;
    settings = {
      # CPU scaling governors
      CPU_SCALING_GOVERNOR_ON_AC = "performance";
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";

      # CPU performance scaling (for Intel)
      CPU_ENERGY_PERF_POLICY_ON_AC = "performance";
      CPU_ENERGY_PERF_POLICY_ON_BAT = "power";

      # Wi-Fi power management
      WIFI_PWR_ON_AC = "off";
      WIFI_PWR_ON_BAT = "on";

      # Optional: Battery charge thresholds (if supported by your hardware)
      # START_CHARGE_THRESH_BAT0 = 20;
      # STOP_CHARGE_THRESH_BAT0 = 80;

      # Optional: Disk power management
      DISK_IDLE_SECS_ON_AC = 0;
      DISK_IDLE_SECS_ON_BAT = 2;
    };
  };

  system.stateVersion = "24.05";
}
