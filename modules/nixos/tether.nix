# Tether from its own flake's module (programs.tether), plus what that
# module leaves out
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
  cfg = config.programs.tether;
in
{
  imports = [ inputs.tether.nixosModules.tether ];

  config = lib.mkIf cfg.enable {
    # The package's own tetherd user unit, which the module doesn't install.
    # NixOS ignores a packaged unit's [Install], so want it as that does.
    systemd.packages = [ cfg.package ];
    systemd.user.services.tetherd = {
      wantedBy = [ "default.target" ];
      # Wanting it gives it NixOS's bare PATH, and tetherd runs btmgmt and
      # bluetoothctl, and tether-gtk for a notification's Reply, by name
      path = [
        pkgs.bluez
        cfg.package
      ];
    };

    # WirePlumber's stock roles make this machine a Bluetooth speaker and
    # hands-free unit, so a linked iPhone plays its music, sounds and calls
    # here. These are the roles headphones use, without the ones a phone
    # connects to. Leaving hfp_hf to BlueZ is also what Tether's call
    # control needs.
    services.pipewire.wireplumber.extraConfig."51-tether-phone-audio" = {
      "monitor.bluez.properties"."bluez5.roles" = [
        "a2dp_source"
        "bap_source"
        "hfp_ag"
      ];
    };
  };
}
