{ pkgs, ... }:
{
  # A notification while the YubiKey waits for a touch: a commit being
  # signed, an SSH login. Both use the FIDO2 key in ~/.ssh directly, with no
  # agent in between.
  #
  # Installed as well as run: the notification names its icon, which is
  # found through the profile's share/icons.
  home.packages = [ pkgs.yubikey-touch-detector ];

  systemd.user.services.yubikey-touch-detector = {
    Unit.Description = "YubiKey touch detector";
    Service = {
      ExecStart = "${pkgs.yubikey-touch-detector}/bin/yubikey-touch-detector --libnotify";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "default.target" ];
  };
}
