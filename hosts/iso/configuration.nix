{
  pkgs,
  modulesPath,
  system,
  user,
  ...
}:
let
  # `sudo run-install HOSTNAME [DRIVE]`, from the booted image
  run-install = pkgs.writeShellApplication {
    name = "run-install";
    runtimeInputs = with pkgs; [
      git
      disko
      btrfs-progs
    ];
    text = builtins.replaceStrings [ "__USER__" ] [ user.username ] (builtins.readFile ./install.sh);
  };
in
{

  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
    "${modulesPath}/installer/cd-dvd/channel.nix"
  ];
  nix.channel.enable = false;
  isoImage = {
    contents = [
      {
        source = ../../.;
        target = "cfg";
      }
    ];
  };

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  nixpkgs.hostPlatform = system;
  networking.wireless.enable = true;
  environment.systemPackages = with pkgs; [
    run-install
    disko
    vim
    git
    toybox
  ];
}
