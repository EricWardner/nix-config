{
  pkgs,
  lib,
  pre-commit-hooks,
  treefmtEval,
}:
let
  # Since nixpkgs' cargo hook started forcing system libraries (Nov 8),
  # convco 0.7.2 needs a libgit2 built with SHA-256 support, which
  # nixpkgs#585314 adds. Once that lands, nixpkgs' convco has a libgit2
  # of its own and this fails, to say the override can go.
  convco =
    assert lib.assertMsg (!lib.any (p: lib.getName p == "libgit2") pkgs.convco.buildInputs)
      "nixpkgs' convco builds with libgit2 now (nixpkgs#585314 landed): drop the convco override in pre-commit.nix";
    pkgs.convco.overrideAttrs (old: {
      buildInputs = old.buildInputs ++ [ (pkgs.libgit2.override { withExperimentalSha256 = true; }) ];
    });
in
pre-commit-hooks.lib.${pkgs.stdenv.hostPlatform.system}.run {
  src = ./.;
  hooks = {
    flake-checker.enable = true;
    treefmt-nix = {
      enable = true;
      entry = "${treefmtEval.config.build.wrapper}/bin/treefmt --ci";
      pass_filenames = false;
    };
    convco = {
      enable = true;
      package = convco;
    };
  };
}
