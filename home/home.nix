{ config, pkgs, ... }:
{
  imports = [
    ./tools/oath.nix
    ../modules/hm
  ];
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
    };
  };
  stylix = {
    targets.k9s.enable = true;
    # Rofi isn't used, and the target still sets programs.rofi.font, which
    # Home Manager renamed to programs.rofi.settings.font: a warning on
    # every evaluation until stylix catches up.
    targets.rofi.enable = false;
    # The gtksourceview target also patches the library itself (its overlay),
    # which changes the hash of everything built on it: Inkscape then misses
    # cache.nixos.org and compiles from source on every nixpkgs update. The
    # target still installs its style under ~/.local/share/gtksourceview-*,
    # where GtkSourceView finds it without the patch.
    overlays.enable = false;
    cursor.package = pkgs.rose-pine-cursor;
    cursor.name = "BreezeX-RosePine-Linux";
    cursor.size = 24;
  };
  # Stylix populates home.pointerCursor from stylix.cursor but doesn't set
  # enable; home-manager deprecated inferring it. Drop once stylix does
  # this itself.
  home.pointerCursor.enable = true;
  modules = {
    ai.gitnexus.enable = true;
    ai.team-skills.enable = true;
    editors.vscode.enable = true;
  };
  home.packages = with pkgs; [
    mpv
    stremio-linux-shell
    inkscape
    discord
    unzip
    claude-code
    openssl
    libnotify
    yubioath-flutter
    stern
    ssm-session-manager-plugin
    pcsc-tools
    v4l-utils
    cameractrls
    (pkgs.writeShellScriptBin "setup-browser-CAC" ''
      NSSDB="''${HOME}/.pki/nssdb"
      mkdir -p ''${NSSDB}

      ${pkgs.nssTools}/bin/modutil -force -dbdir sql:$NSSDB -add yubi-smartcard \
        -libfile ${pkgs.opensc}/lib/opensc-pkcs11.so
    '')
    (pkgs.writeShellScriptBin "launch-webapp" ''
      exec ${config.programs.google-chrome.finalPackage}/bin/google-chrome-stable --app="$1" "''${@:2}"
    '')
  ];

  programs = {
    google-chrome = {
      enable = true;
      package = pkgs.google-chrome;
      # Links go to chrome-here.desktop, so Chrome would keep offering to be
      # the default, and accepting overwrites the managed mimeapps.list
      commandLineArgs = [ "--no-default-browser-check" ];
    };
  };
  # A launcher entry per Chrome profile (the directory names under
  # ~/.config/google-chrome). Chrome opens a new window in that profile,
  # or hands the request to the running instance.
  xdg.desktopEntries =
    builtins.mapAttrs
      (_: profile: {
        name = "Google Chrome (${profile.label})";
        genericName = "Web Browser";
        icon = "google-chrome";
        exec = ''${config.programs.google-chrome.finalPackage}/bin/google-chrome-stable --profile-directory="${profile.dir}" %U'';
        categories = [
          "Network"
          "WebBrowser"
        ];
        settings.Keywords = "chrome;browser;profile;${profile.keywords}";
      })
      {
        chrome-work = {
          label = "Work";
          dir = "Default";
          keywords = "work;tiberius";
        };
        chrome-personal = {
          label = "Personal";
          dir = "Profile 1";
          keywords = "personal;gmail;home";
        };
      };
  home.sessionVariables = {
    EDITOR = "vim";
    SOPS_AGE_SSH_PRIVATE_KEY_FILE = "$HOME/.ssh/id_ed25519_sops";
  };
  gtk = {
    enable = true;
    iconTheme = {
      package = pkgs.papirus-icon-theme;
      name = "Papirus-Dark";
    };
  };

  stylix.targets.gtk.extraCss = ''
    /* Menu hover styling for GTK apps */
    window > menu > menuitem:hover,
    window > menu > menuitem:hover > check,
    window > menu > menuitem:hover > box,
    window > menu > menuitem:hover > box > *,
    window > menu > menuitem:hover > label,
    window > menu > menuitem:hover > label > *,
    window > menu > menuitem:hover > arrow {
      background-color: @theme_selected_bg_color;
      color: @theme_selected_fg_color;
    }
  '';
}
