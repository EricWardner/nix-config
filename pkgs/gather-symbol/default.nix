# The Gather logo as a one-glyph font, "Gather Symbol", for the bar's
# workspace icon. It sits at U+FFF00, a private-use code point no other
# installed font has, so text in any font falls back to it through
# fontconfig with no rules needed. Built in a second or two, where patching
# it into every SF Pro face took minutes on each nixpkgs update.
{ runCommand, python3 }:
runCommand "gather-symbol"
  {
    nativeBuildInputs = [ (python3.withPackages (ps: [ ps.fontforge ])) ];
    meta.description = "The Gather logo as a one-glyph font at U+FFF00";
  }
  ''
    python3 ${./make-font.py} ${./gather.svg} GatherSymbol.ttf
    install -Dm644 GatherSymbol.ttf $out/share/fonts/truetype/GatherSymbol.ttf
  ''
