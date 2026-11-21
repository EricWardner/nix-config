{ pkgs, ... }:
{
  # A notification while the YubiKey waits for a touch: a commit being
  # signed, an SSH login. Both use the FIDO2 key in ~/.ssh directly, with no
  # agent in between.
  systemd.user.services.yubikey-touch-detector = {
    Unit.Description = "YubiKey touch detector";
    Service = {
      ExecStart = "${pkgs.yubikey-touch-detector}/bin/yubikey-touch-detector --libnotify";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "default.target" ];
  };
}
