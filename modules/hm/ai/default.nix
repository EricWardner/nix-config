{
  imports = [
    ./team-skills.nix
  ];

  config.home.file.".claude/CLAUDE.md".source = ./CLAUDE.md;
}
