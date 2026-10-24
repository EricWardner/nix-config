{
  modules = {
    themes.wallpaper = ../../modules/stylix/assets/walls/AI_UKRAINE.png;
    hyprland.monitors = [
      {
        name = "eDP-1";
        workspace = "10";
        enabled = true;
        scale = "1.6";
      }
      {
        name = "desc:GIGA-BYTE TECHNOLOGY CO. LTD. Gigabyte M32U 22181B002365";
        workspace = "1";
        resolution = "3840x2160@144";
        position = "-3072x-1000";
        scale = "1.25";
      }
      {
        name = "desc:ESP eD13(2022) 0x00023552";
        resolution = "highres";
        position = "auto-left";
        scale = "1";
      }
    ];
  };

  # waybar's temperature module defaults to thermal_zone0, a board sensor
  # here that runs well below the CPU. Read the CPU's own k10temp (Tctl,
  # PCI 00:18.3) so the critical threshold means something; hwmonN numbers
  # aren't stable across boots, hence the device path.
  programs.waybar.settings.mainBar.temperature = {
    hwmon-path-abs = "/sys/devices/pci0000:00/0000:00:18.3/hwmon";
    input-filename = "temp1_input";
  };
}
