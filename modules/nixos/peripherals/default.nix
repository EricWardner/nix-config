{
  config,
  pkgs,
  lib,
  user,
  ...
}:
let
  inherit (lib) mkIf mkMerge mkEnableOption;
  cfg = config.modules.peripherals;

  webcamToggle = pkgs.writeShellApplication {
    name = "webcam-toggle";
    text = builtins.readFile ./webcam-toggle;
  };
in
{
  options = {
    modules.peripherals.enable = mkEnableOption "Enable peripheral configuration" // {
      default = true;
    };
    modules.peripherals.obs.enable = mkEnableOption "Enable OBS virtual camera";
    modules.peripherals.scarlettRite.enable = mkEnableOption "Enable Scarlett Rite";
    modules.peripherals.webcam.enable = mkEnableOption "Enable webcam toggle" // {
      default = true;
    };
    modules.peripherals.keyd.enable = mkEnableOption "Enable keyd input aggregation";
  };
  config = mkIf cfg.enable (mkMerge [
    {
      boot = {
        # snd_aloop is deliberately OBS-gated: it only exists to route the
        # Scarlett through a loopback device for OBS, so with obs.enable off
        # the scarlettRite option just sets the snd_usb_audio modprobe options.
        kernelModules = mkIf cfg.obs.enable (
          [ "v4l2loopback" ] ++ (if cfg.scarlettRite.enable then [ "snd_aloop" ] else [ ])
        );
        extraModulePackages = mkIf cfg.obs.enable [ config.boot.kernelPackages.v4l2loopback.out ];
        extraModprobeConfig =
          (
            if cfg.obs.enable then
              ''
                options v4l2loopback devices=1 video_nr=1 card_label="Virtual Camera" exclusive_caps=1
              ''
            else
              ""
          )
          + (
            if cfg.scarlettRite.enable then
              ''
                options snd_usb_audio vid=0x1235 pid=0x8212 device_setup=1
              ''
            else
              ""
          );
      };
    }
    (mkIf cfg.webcam.enable {
      environment.systemPackages = [ webcamToggle ];

      # waybar's webcam "in-use" check runs `fuser /dev/videoN` to find which
      # process holds the camera. waybar runs as a systemd --user service (for
      # crash recovery + monitor hotplug), and from that unprivileged
      # user-manager context fuser cannot read the fds/maps of the browser
      # processes that actually hold the device (they live in the seat0 login
      # session; ptrace_may_access denies the cross-context /proc read). The
      # result: the green highlight never triggered. A capability-only wrapper
      # (no setuid) gives fuser CAP_SYS_PTRACE so the check works from any
      # context. Scoped to the `video` group to limit the fd-inspection reach.
      security.wrappers.webcam-fuser = {
        source = "${pkgs.psmisc}/bin/fuser";
        owner = "root";
        group = "video";
        permissions = "0750";
        capabilities = "cap_sys_ptrace+ep";
      };

      security.sudo.extraRules = [
        {
          users = [ user.username ];
          commands = [
            {
              command = "/run/current-system/sw/bin/webcam-toggle";
              options = [ "NOPASSWD" ];
            }
          ];
        }
      ];
    })
    (mkIf cfg.keyd.enable {
      # keyd grabs every keyboard — including hotplugged ones, its core
      # competence — and re-emits events through one virtual device that is
      # created at boot and outlives any hardware coming or going. The
      # push-to-talk evdev listener (triggerhappy, HM waybar module) then
      # always has a stable device to watch instead of chasing hardware
      # hotplug; its restart-on-hotplug bridge remains only as a backstop
      # (e.g. keyd itself restarting on a rebuild). Pure passthrough — no
      # remapping — so Right Alt stays a real Alt everywhere.
      services.keyd = {
        enable = true;
        keyboards.default.ids = [ "*" ];
      };

      # keyd's virtual keyboard is created fresh at every keyd start, so its
      # /dev/input/eventN number isn't stable across boots. Give it a fixed
      # by-id path so thd (waybar's push-to-talk daemon) can target it
      # directly instead of globbing every input device.
      services.udev.extraRules = ''
        SUBSYSTEM=="input", KERNEL=="event*", ATTRS{name}=="keyd virtual keyboard", SYMLINK+="input/by-id/keyd-virtual-keyboard-event-kbd"
      '';
    })
  ]);
}
