{
  lib,
  rustPlatform,
  pkg-config,
  wrapGAppsHook4,
  gtk4,
  gtk4-layer-shell,
  gst_all_1,
  ffmpeg,
  wl-clipboard-rs,
  systemd,
}:
let
  manifest = (lib.importTOML ./Cargo.toml).package;
in
rustPlatform.buildRustPackage {
  pname = manifest.name;
  inherit (manifest) version;
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./Cargo.toml
      ./Cargo.lock
      ./src
    ];
  };
  cargoLock.lockFile = ./Cargo.lock;
  nativeBuildInputs = [
    pkg-config
    wrapGAppsHook4
  ];
  buildInputs = [
    gtk4
    gtk4-layer-shell
    # GtkVideo: the MP4 demuxer (good), VA-API decoding on the GPU (bad),
    # and a software decoder to fall back on (libav)
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-bad
    gst_all_1.gst-libav
  ];
  # ffprobe and the GIF conversion, and the actions: wl-copy and busctl
  # (Thunar's FileManager1)
  preFixup = ''
    gappsWrapperArgs+=(--prefix PATH : ${
      lib.makeBinPath [
        ffmpeg
        wl-clipboard-rs
        systemd
      ]
    })
  '';
  meta = {
    inherit (manifest) description;
    mainProgram = manifest.name;
  };
}
