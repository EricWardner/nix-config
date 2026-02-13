{
  lib,
  buildNpmPackage,
  fetchurl,
  nodejs_22,
  python3,
  pkg-config,
  makeWrapper,
  linux-pam,
}:

buildNpmPackage rec {
  pname = "vibetunnel";
  version = "1.0.0-beta.15.1";

  src = fetchurl {
    url = "https://registry.npmjs.org/vibetunnel/-/vibetunnel-${version}.tgz";
    hash = "sha256-cPRwIci0F/rgWuKtQ9Wqi8Ao1rFXJdbE7qNb/yG8X8A=";
  };

  sourceRoot = "package";

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-zRPIjUl+eGkZWbziRfGtbSijh0VAScPtlYXSvWr4jb0=";

  nodejs = nodejs_22;
  makeCacheWritable = true;

  nativeBuildInputs = [
    python3
    pkg-config
    makeWrapper
  ];
  buildInputs = [ linux-pam ];

  env.PUPPETEER_SKIP_DOWNLOAD = "1";

  dontNpmBuild = true;

  postInstall = ''
    # Extract node-pty prebuilt binary (postinstall script doesn't run in nix)
    local vtdir=$out/lib/node_modules/vibetunnel
    local nodeABI=$(node -e "console.log(process.versions.modules)")
    tar -xzf $vtdir/prebuilds/node-pty-v1.0.0-node-v''${nodeABI}-linux-x64.tar.gz \
      -C $vtdir/node-pty

    # Fix the bin wrapper to run dist/vibetunnel-cli directly instead of
    # bin/vibetunnel which require()'s it (fails due to require.main guard)
    rm $out/bin/vibetunnel
    makeWrapper ${nodejs_22}/bin/node $out/bin/vibetunnel \
      --add-flags "$vtdir/dist/vibetunnel-cli"
    makeWrapper $out/bin/vibetunnel $out/bin/vt \
      --add-flags "fwd"
  '';

  meta = {
    description = "Turn any browser into your terminal";
    homepage = "https://vibetunnel.sh";
    license = lib.licenses.mit;
    mainProgram = "vibetunnel";
  };
}
