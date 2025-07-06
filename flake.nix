{
  description = "USERS personal flake";
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hyprland.url = "git+https://github.com/hyprwm/Hyprland?submodules=1";
    stylix.url = "github:danth/stylix";
    # SecondFront Modules and Projects
    secondfront.url = "github:tonybutt/modules";
    # twofctl = {
    #   type = "gitlab";
    #   host = "code.il2.gamewarden.io";
    #   owner = "gamewarden%2Fplatform";
    #   repo = "2fctl";
    # };
  };
  nixConfig = {
    extra-substituters = [ "https://hyprland.cachix.org" ];
    extra-trusted-public-keys = [
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
    ];
  };

  outputs =
    {
      nixpkgs,
      stylix,
      home-manager,
      hyprland,
      disko,
      nixos-hardware,
      secondfront,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        # overlays = [ twofctl.overlays.default ];
      };
      user = {
        name = "USERNAME";
        fullName = "USER FULL NAME";
        email = "USER EMAIL";
        signingkey = "USER SIGNING KEY";
      };
    in
    {
      formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt-rfc-style;
      nixosConfigurations = {
        nixtop = nixpkgs.lib.nixosSystem {
          inherit pkgs system;
          specialArgs = {
            inherit user inputs hyprland;
          };
          modules = [
            nixos-hardware.nixosModules.dell-xps-15-9530-nvidia
            ./hosts/nixtop/configuration.nix
            stylix.nixosModules.stylix
            disko.nixosModules.disko
            secondfront.nixosModules.secondfront
          ];
        };
        # Minimal Installation ISO.
        iso = nixpkgs.lib.nixosSystem {
          inherit pkgs system;
          specialArgs = {
            inherit user;
          };

          modules = [
            ./hosts/iso/configuration.nix
          ];
        };
      };
      homeConfigurations = {
        "${user.name}" = home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          extraSpecialArgs = {
            inherit inputs user;
          };
          modules = [
            ./home/home.nix
            stylix.homeManagerModules.stylix
            secondfront.homeManagerModules.secondfront
          ];
        };
      };
    };
}
