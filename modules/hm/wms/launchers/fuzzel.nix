{
  programs.fuzzel = {
    enable = true;
    settings = {
      main = {
        # All values divisible by 4 for clean 1.25x scaling
        horizontal-pad = 40; # 40 * 1.25 = 50
        vertical-pad = 8; # 8 * 1.25 = 10
        inner-pad = 4; # 4 * 1.25 = 5
        line-height = 20; # 20 * 1.25 = 25
        icon-theme = "Papirus-Dark";
      };
      border = {
        width = 4; # 4 * 1.25 = 5 (was 1 → 1.25 fractional)
        radius = 8; # 8 * 1.25 = 10
      };
    };
  };
}
