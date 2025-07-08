{
  description = "Eric's personal flake";
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
    
    # San Francisco Fonts | Apple Fonts
    apple-fonts.url= "github:Lyndeno/apple-fonts.nix";
    apple-fonts.inputs.nixpkgs.follows = "nixpkgs";
    
    stylix.url = "github:danth/stylix";

    
    # SecondFront Modules and Projects
    secondfront.url = "github:ericwardner/modules/feat/flexible-monitor-resolution";
    twofctl = {
      type = "gitlab";
      host = "code.il2.gamewarden.io";
      owner = "gamewarden%2Fplatform";
      repo = "2fctl";
    };
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
      apple-fonts,
      home-manager,
      hyprland,
      disko,
      nixos-hardware,
      secondfront,
      twofctl,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [ twofctl.overlays.default ];
      };
      user = {
        name = "eric";
        fullName = "Eric Wardner";
        email = "eric.wardner@secondfront.com";
        signingkey = "CD50EBA2A34C316D93C8D72DBC4B0DB6C91C99BC";
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
            stylix.homeModules.stylix
            secondfront.homeManagerModules.secondfront
          ];
        };
      };
    };
}
