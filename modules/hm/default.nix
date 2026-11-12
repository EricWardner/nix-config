{
  config,
  pkgs,
  lib,
  ...
}:
let
  chromeHere = pkgs.writeShellApplication {
    name = "chrome-here";
    runtimeInputs = [
      pkgs.hyprland
      pkgs.jq
      config.programs.google-chrome.finalPackage
    ];
    text = builtins.readFile ./chrome-here;
  };
in
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
    # No Plasma session: the target builds a look-and-feel package with the
    # wallpaper inside it, tries to apply it on every switch, and puts its
    # kdeglobals first in XDG_CONFIG_DIRS. Qt apps are themed by the qt
    # target (qtct + Kvantum), not this.
    stylix.targets.kde.enable = false;
    stylix.targets.hyprlock.enable = lib.mkForce false;
    stylix.targets.hyprpaper.enable = lib.mkForce false;
    # The hyprland target would also turn hyprpaper on to show stylix.image;
    # the wallpaper is swaybg (wms/hypr/wallpaper.nix).
    stylix.targets.hyprland.hyprpaper.enable = false;

    fonts.fontconfig = {
      # Fonts from home.packages, through each generation's own font folder
      # and a cache built with it. Otherwise they're only found through
      # ~/.nix-profile, whose cache never looks out of date (store paths are
      # all dated 1970), so a font change didn't show until fc-cache -f.
      enable = true;

      # The icon fonts: Nerd Font icons in text come from Symbols Nerd Font
      # (the Gather logo from gather-symbol, which nothing else covers).
      # - Symbols Nerd Font goes straight after the UI font, ahead of
      #   Cascadia Code NF, whose icons are sized for a terminal cell and came
      #   out far smaller in the bar.
      # - They have only a Regular face, so in bold GTK text (waybar's
      #   workspace labels were) fontconfig fakes bold by thickening their
      #   outlines, which ran the Gather logo's rings together. Qt fakes its
      #   own bold and ignores this, so the islands bar sets the icons
      #   apart in the regular weight. 90-synthetic.conf does that
      #   to a font no heavier than medium; user rules come before it
      #   (50-user.conf), so this calls them bold when bold is asked for.
      configFile.icon-fonts = {
        enable = true;
        priority = 60;
        text = ''
          <?xml version="1.0"?>
          <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
          <fontconfig>
            <match target="pattern">
              <test name="family"><string>${config.stylix.fonts.sansSerif.name}</string></test>
              <edit name="family" mode="append" binding="strong"><string>Symbols Nerd Font</string></edit>
            </match>
          ${
            lib.concatMapStrings
              (family: ''
                <match target="font">
                  <test name="family"><string>${family}</string></test>
                  <test target="pattern" name="weight" compare="more_eq"><const>bold</const></test>
                  <edit name="weight" mode="assign"><const>bold</const></edit>
                </match>
              '')
              [
                "Symbols Nerd Font"
                "Symbols Nerd Font Mono"
                "Gather Symbol"
              ]
          }</fontconfig>
        '';
      };
    };

    xdg = {
      enable = true;
      mimeApps = {
        enable = true;
        defaultApplications = {
          "x-scheme-handler/https" = [ "chrome-here.desktop" ];
          "x-scheme-handler/http" = [ "chrome-here.desktop" ];
          "text/html" = [ "chrome-here.desktop" ];
          "inode/directory" = [ "thunar.desktop" ];
        }
        # Images in Loupe: with nothing set they opened in a browser, which
        # claims them. SVGs too, to look at; Inkscape is in Open With.
        // lib.genAttrs [
          "image/apng"
          "image/avif"
          "image/bmp"
          "image/gif"
          "image/heic"
          "image/jpeg"
          "image/jxl"
          "image/png"
          "image/svg+xml"
          "image/tiff"
          "image/webp"
        ] (_: [ "org.gnome.Loupe.desktop" ]);
      };
      desktopEntries."com.google.Chrome" = {
        name = "Google Chrome (duplicate)";
        noDisplay = true;
        exec = "";
      };
      # Links open in Chrome on the workspace they're clicked from
      desktopEntries.chrome-here = {
        name = "Google Chrome (this workspace)";
        noDisplay = true;
        exec = "${chromeHere}/bin/chrome-here %U";
        mimeType = [
          "x-scheme-handler/http"
          "x-scheme-handler/https"
          "text/html"
        ];
      };
    };
    home = {
      # CLI tools open links through $BROWSER, not xdg-open
      sessionVariables.BROWSER = "${chromeHere}/bin/chrome-here";
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
        libsecret # secret-tool: the keyring from the shell

        # Clipboard
        grim
        wl-clipboard-rs

        # Fonts: Nerd Font icons for text in any font (fonts.fontconfig
        # above), and Ghostty's font-codepoint-map
        nerd-fonts.symbols-only

        # Chat
        slack
        signal-desktop

        # Image viewer (the default for images, above)
        loupe
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
