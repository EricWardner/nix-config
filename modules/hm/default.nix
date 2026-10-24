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
    # The hyprland target would also turn hyprpaper on to show stylix.image;
    # the wallpaper is swaybg (wms/hypr/wallpaper.nix).
    stylix.targets.hyprland.hyprpaper.enable = false;
    xdg = {
      enable = true;
      mimeApps = {
        enable = true;
        defaultApplications = {
          "x-scheme-handler/https" = [ "google-chrome.desktop" ];
          "x-scheme-handler/http" = [ "google-chrome.desktop" ];
          "text/html" = [ "google-chrome.desktop" ];
          "inode/directory" = [ "thunar.desktop" ];
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
        forgejo-cli # fj: Forgejo CLI for code.grail.tiberius.com (replaces tea)
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
    # fj (forgejo-cli) only offers `fj auth login` (OAuth + PKCE) for hosts it
    # has a client id for; otherwise it says "doesn't support login". This is a
    # dedicated "fj" OAuth2 app registered under my Forgejo user (public client,
    # redirect http://127.0.0.1:26218/). Forgejo's built-in tea app can't be shared:
    # one grant per user per app, and tea's grant has a different scope.
    xdg.configFile."forgejo-cli/client_ids".text = ''
      code.grail.tiberius.com 5cba57d5-9fcf-4707-af96-3a3bc9e7ef5a
    '';
    xdg.userDirs = {
      enable = true;
      setSessionVariables = true;

      createDirectories = true;
      desktop = null;
      documents = null;
      music = null;
      templates = null;
      publicShare = null;
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
