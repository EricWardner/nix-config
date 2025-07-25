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

  # https://gist.github.com/alexVinarskis/77d55a0a0f4150576ba77e5f4241d512
  services.pipewire = {
    enable = true;
    pulse.enable = true;
    alsa.enable = true;
    wireplumber.enable = true;

    extraConfig.pipewire."99-dell-xps-equalizer" = {
      "context.modules" = [
        {
          name = "libpipewire-module-filter-chain";
          args = {
            "node.description" = "Internal Speakers Equalizer Sink";
            "media.name" = "Internal Speakers Equalizer Sink";
            "filter.graph" = {
              nodes = [
                {
                  type = "builtin";
                  name = "eq_band_1";
                  label = "bq_peaking";
                  control = {
                    "Freq" = 119.0;
                    "Q" = 1.5;
                    "Gain" = 11.0;
                  };
                }
                {
                  type = "builtin";
                  name = "eq_band_2";
                  label = "bq_peaking";
                  control = {
                    "Freq" = 238.0;
                    "Q" = 1.5;
                    "Gain" = 2.0;
                  };
                }
                {
                  type = "builtin";
                  name = "eq_band_3";
                  label = "bq_peaking";
                  control = {
                    "Freq" = 475.0;
                    "Q" = 1.5;
                    "Gain" = -11.0;
                  };
                }
                {
                  type = "builtin";
                  name = "eq_band_4";
                  label = "bq_peaking";
                  control = {
                    "Freq" = 947.0;
                    "Q" = 1.5;
                    "Gain" = -11.0;
                  };
                }
                {
                  type = "builtin";
                  name = "eq_band_5";
                  label = "bq_peaking";
                  control = {
                    "Freq" = 1890.0;
                    "Q" = 1.5;
                    "Gain" = -2.0;
                  };
                }
                {
                  type = "builtin";
                  name = "eq_band_6";
                  label = "bq_peaking";
                  control = {
                    "Freq" = 3771.0;
                    "Q" = 1.5;
                    "Gain" = 2.0;
                  };
                }
                {
                  type = "builtin";
                  name = "eq_band_7";
                  label = "bq_peaking";
                  control = {
                    "Freq" = 7524.0;
                    "Q" = 1.5;
                    "Gain" = 9.0;
                  };
                }
                {
                  type = "builtin";
                  name = "eq_band_8";
                  label = "bq_peaking";
                  control = {
                    "Freq" = 15012.0;
                    "Q" = 1.5;
                    "Gain" = 10.0;
                  };
                }
              ];
              links = [
                {
                  output = "eq_band_1:Out";
                  input = "eq_band_2:In";
                }
                {
                  output = "eq_band_2:Out";
                  input = "eq_band_3:In";
                }
                {
                  output = "eq_band_3:Out";
                  input = "eq_band_4:In";
                }
                {
                  output = "eq_band_4:Out";
                  input = "eq_band_5:In";
                }
                {
                  output = "eq_band_5:Out";
                  input = "eq_band_6:In";
                }
                {
                  output = "eq_band_6:Out";
                  input = "eq_band_7:In";
                }
                {
                  output = "eq_band_7:Out";
                  input = "eq_band_8:In";
                }
              ];
            };
            "audio.channels" = 2;
            "audio.position" = [
              "FL"
              "FR"
            ];
            "capture.props" = {
              "node.name" = "internal_speaker";
              "media.class" = "Audio/Sink";
            };
            "playback.props" = {
              "node.name" = "internal_speaker_equalizer_output";
              "node.passive" = true;
              "node.target" = "alsa_output.pci-0000_00_1f.3-platform-skl_hda_dsp_generic.HiFi__Speaker__sink";
            };
          };
        }
      ];
    };
  };

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
