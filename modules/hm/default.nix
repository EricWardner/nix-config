{
  pkgs,
  lib,
  ...
}:
{
  imports = [
    ./wms
    ./git
    ./gpg
    ./editors
    ./shells
    ./terminals
    ./ai
    ../stylix
  ];
  config = {
    stylix.targets.gnome.enable = false;
    stylix.targets.waybar.enable = true;
    stylix.targets.hyprlock.enable = lib.mkForce false;
    stylix.targets.hyprpaper.enable = lib.mkForce false;
    xdg = {
      enable = true;
      mimeApps = {
        enable = true;
        defaultApplications = {
          "x-scheme-handler/https" = [ "google-chrome.desktop" ];
          "x-scheme-handler/http" = [ "google-chrome.desktop" ];
          "text/html" = [ "google-chrome.desktop" ];
        };
      };
      desktopEntries."com.google.Chrome" = {
        name = "Google Chrome (duplicate)";
        noDisplay = true;
        exec = "";
      };
    };
    home = {
      packages = with pkgs; [
        # DevOpts
        awscli2
        kind
        fluxcd
        kubectl
        kubelogin-oidc
        kubernetes-helm
        kustomize
        istioctl
        cilium-cli

        # Shell Utils
        gh
        tmux
        tree
        jq
        yubikey-manager
        outfieldr

        # Clipboard
        grim
        slurp
        swappy
        wl-clipboard-rs

        # Dev Tools
        hyprpicker

        # Chat
        slack
      ];
      file."Wallpapers" = {
        recursive = true;
        source = ../stylix/assets/walls;
        target = "Wallpapers/Wallpapers/..";
      };
    };
    xdg.userDirs = {
      enable = true;
      setSessionVariables = true;

      createDirectories = true;
      desktop = null;
      documents = null;
      music = null;
      templates = null;
      videos = true;
      publicShare = null;
    };
    services.cliphist = {
      enable = true;
      allowImages = true;
    };
    programs = {
      direnv = {
        enable = true;
        nix-direnv.enable = true;
        config.global.hide_env_diff = true;
      };
      btop.enable = true;
      fzf = {
        enable = true;
        enableZshIntegration = true;
      };
      fastfetch.enable = true;
    };
  };
}
