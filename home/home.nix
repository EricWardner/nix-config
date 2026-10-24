{ pkgs, ... }:
{
  imports = [
    ./tools/oath.nix
    ./tools/wf-recorder.nix
    ../modules/hm
  ];
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
    };
    "org/virt-manager/virt-manager/connections" = {
      autoconnect = [ "qemu:///system" ];
      uris = [ "qemu:///system" ];
    };
  };
  stylix = {
    targets.k9s.enable = true;
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
    brave
    discord
    unzip
    claude-code
    pavucontrol
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
      exec ${pkgs.google-chrome}/bin/google-chrome-stable --app="$1" "''${@:2}"
    '')
    (pkgs.writeShellScriptBin "system-menu" ''
      choice=$(printf "󰌾  Lock\n󰤄  Sleep\n  Reboot\n󰐥  Shutdown\n󰗽  Logout" | ${pkgs.fuzzel}/bin/fuzzel --dmenu -p "System: ")
      case "$choice" in
        *Lock*) loginctl lock-session ;;
        *Sleep*) systemctl suspend-then-hibernate ;;
        *Reboot*) systemctl reboot ;;
        *Shutdown*) systemctl poweroff ;;
        *Logout*) hyprctl dispatch 'hl.dsp.exit()' ;;
      esac
    '')
  ];

  programs = {
    google-chrome = {
      enable = true;
      package = pkgs.google-chrome;
    };
  };
  home.sessionVariables = {
    BROWSER = "google-chrome-stable";
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
