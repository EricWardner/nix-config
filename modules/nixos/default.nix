{
  pkgs,
  config,
  lib,
  user,
  ...
}:
let
  inherit (lib)
    mkIf
    mkOption
    mkEnableOption
    types
    ;
  cfg = config.modules;
in
{
  imports = [
    ./packages.nix
    ./power-profiles.nix
    ./wms
    ./peripherals
    ./users
    ./virtualizations
    ../stylix
  ];

  options = {
    modules.enable = mkEnableOption "Enable NixOS modules" // {
      default = true;
    };
    modules.timeZone = mkOption {
      type = types.str;
      default = "America/New_York";
      description = "The system time zone.";
    };
    modules.hostName = mkOption {
      type = types.str;
      default = "";
      description = "The system hostname.";
    };
    modules.grub = mkOption {
      type = types.bool;
      default = true;
      description = "Enable GRUB bootloader.";
    };
  };
  config = mkIf cfg.enable {
    nix = {
      channel.enable = false;
      settings = {
        trusted-users = [ user.username ];
        experimental-features = [
          "nix-command"
          "flakes"
        ];
        substituters = [
          "https://claude-code.cachix.org"
        ];
        trusted-substituters = [
          "https://claude-code.cachix.org"
        ];
        trusted-public-keys = [
          "claude-code.cachix.org-1:YeXf2aNu7UTX8Vwrze0za1WEDS+4DuI2kVeWEE4fsRk="
        ];
        # Give up on an unreachable cache after 5s instead of hanging, and
        # build locally when substituting fails instead of erroring out.
        connect-timeout = 5;
        fallback = true;
      };
      # Hard-link identical files across the store, weekly at low priority
      # (catches up after the laptop was asleep).
      optimise = {
        automatic = true;
        dates = [ "weekly" ];
      };
    };

    # Let nix-daemon read private flake inputs (tokens etc.) from a file
    # kept out of the repo.
    systemd.services.nix-daemon.serviceConfig.EnvironmentFile = "/etc/nix/private-modules.env";

    boot = {
      loader.grub = mkIf cfg.grub {
        enable = true;
        efiSupport = true;
      };
      loader.systemd-boot = mkIf (!cfg.grub) {
        enable = true;
        # A new generation gets 3 tries: one that never reaches
        # boot-complete.target (systemd-bless-boot) is skipped for the one
        # before it, which makes the hidden menu below safe.
        bootCounting.enable = true;
        # No editing the kernel command line from the boot menu.
        editor = false;
      };
      # Boot the default entry straight away; hold Space as the machine
      # starts to get the menu.
      loader.timeout = 0;
      # Themed boot splash (stylix's plymouth target) that also asks for the
      # disk password. Both hosts load their GPU driver in the initrd
      # (amdgpu, i915), so it comes up at native resolution.
      plymouth.enable = true;
      # Disable(quiet) most of the logging that happens during boot. The
      # initrd is systemd's (nixpkgs dropped the scripted one).
      consoleLogLevel = 0;
      kernelParams = [
        "quiet"
        "udev.log_level=0"
      ];
    };

    networking = {
      hostName = cfg.hostName;
      firewall = {
        enable = true;
      };
      networkmanager = {
        enable = true;
        # Lets NetworkManager tell a working connection from a captive
        # portal or one with no internet (net-panel's "Sign-in required"
        # and "No internet"). GNOME's endpoint is made for NetworkManager
        # and served from Fastly; captive portals don't special-case it the
        # way some let Apple's and Google's probes through to hide the login
        # popup, which would read as online before signing in.
        settings.connectivity = {
          uri = "http://nmcheck.gnome.org/check_network_status.txt";
          interval = 300;
        };
      };
      # NetworkManager turns this on for mobile broadband; neither host has
      # a cellular modem.
      modemmanager.enable = false;
    };

    hardware = {
      gpgSmartcards.enable = true;
      bluetooth = {
        enable = true;
        powerOnBoot = true;
        settings = {
          General = {
            Enable = "Source,Sink,Media,Socket";
            Experimental = true;
            ControllerMode = "Dual";
            FastConnectable = true;
          };
          Policy = {
            AutoEnable = "true";
          };
          LE = {
            EnableAdvMonInterleaveScan = "true";
          };
        };
      };
    };

    security = {
      sudo-rs = {
        enable = false;
        execWheelOnly = true;
      };
      sudo.enable = true;
      auditd.enable = true;
      audit.enable = true;
      rtkit.enable = true;
      pam.services = {
        hyprlock = { };
        greetd.enableGnomeKeyring = true;
      };
    };

    programs = {
      zsh.enable = true;
      ssh.startAgent = false;
      seahorse.enable = true;
      nh = {
        enable = true;
        clean.enable = true;
        # --no-gcroots is load-bearing: without it, nh clean deletes any
        # gcroot older than --keep-since, including home-manager's
        # current-home root. Standalone HM generations are rooted ONLY by
        # that link, so the next `nix store gc` sweeps the live home
        # closure (2026-07-13 incident: all ~/.config/hypr symlinks went
        # dangling after the weekly timer fired 4.5 days after the last
        # `nh home switch`).
        clean.extraArgs = "--keep-since 7d --keep 5 --no-gcroots";
        flake = "/home/${user.username}/nix-config";
      };

      gnupg.agent = {
        enable = true;
        enableSSHSupport = true;
      };

      thunar = {
        enable = true;
        plugins = with pkgs; [
          thunar-archive-plugin
          thunar-volman
        ];
      };
      xfconf.enable = true;
    };

    powerManagement.enable = true;

    systemd.sleep.settings.Sleep = {
      HibernateDelaySec = "1h";
      HibernateOnACPower = "no";
    };

    services = {
      tlp.enable = true;
      upower.enable = true;
      devmon.enable = true;
      gvfs.enable = true;
      udisks2.enable = true;
      tumbler.enable = true;
      printing.enable = true;
      # Monthly checksum pass over the disk, an early warning of a failing
      # SSD (metadata is DUP, so its errors get repaired; data is single,
      # so data errors are only reported). "/" alone: the other mounts are
      # subvolumes of the same filesystem and would scrub it again.
      btrfs.autoScrub = {
        enable = true;
        interval = "monthly";
        fileSystems = [ "/" ];
      };
      blueman.enable = true;
      pcscd.enable = true;
      gnome.gnome-keyring.enable = true;

      logind.settings.Login = {
        HandleLidSwitch = "suspend-then-hibernate";
        HandleLidSwitchDocked = "suspend-then-hibernate";
        HandleLidSwitchExternalPower = "suspend-then-hibernate";
        HandlePowerKey = "suspend-then-hibernate";
        HandlePowerKeyLongPress = "poweroff";
      };
    };

    time.timeZone = cfg.timeZone;
    i18n.defaultLocale = "en_US.UTF-8";
    i18n.extraLocaleSettings = {
      LC_ADDRESS = "en_US.UTF-8";
      LC_IDENTIFICATION = "en_US.UTF-8";
      LC_MEASUREMENT = "en_US.UTF-8";
      LC_MONETARY = "en_US.UTF-8";
      LC_NAME = "en_US.UTF-8";
      LC_NUMERIC = "en_US.UTF-8";
      LC_PAPER = "en_US.UTF-8";
      LC_TELEPHONE = "en_US.UTF-8";
      LC_TIME = "en_US.UTF-8";
    };
  };
}
