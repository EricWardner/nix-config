{ pkgs, ... }:
{
  imports = [
    ./tools/oath.nix
    ./tools/wf-recorder.nix
    ../modules/hm
  ];
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color_scheme = "prefer-dark";
    };
    "org/virt-manager/virt-manager/connections" = {
      autoconnect = [ "qemu:///system" ];
      uris = [ "qemu:///system" ];
    };
  };
  stylix = {
    targets.k9s.enable = true;
    cursor.package = pkgs.rose-pine-cursor;
    cursor.name = "BreezeX-RosePine-Linux";
    cursor.size = 24;
  };
  modules = {
    ai.claude-cognitive.enable = false;
    editors.vscode.enable = true;
  };
  home.packages = with pkgs; [
    networkmanagerapplet
    mpv
    gimp3
    unzip
    claude-code
    pavucontrol
    cloudflared
    openssl
    spotify
    libnotify
    yubioath-flutter
    signal-desktop
    stern
    ssm-session-manager-plugin
    pcsc-tools
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
        *Logout*) hyprctl dispatch exit ;;
      esac
    '')
  ];

  programs = {
    kitty.settings = {
      scrollback_lines = 100000;
      copy_on_select = "clipboard";
    };
    google-chrome = {
      enable = true;
      package = pkgs.google-chrome;
    };
    zsh.sessionVariables = {
      BROWSER = "google-chrome-stable";
      EDITOR = "vim";
    };
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
