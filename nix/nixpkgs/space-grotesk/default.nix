{
  stdenv,
  fetchzip,
  lib,
}:

stdenv.mkDerivation rec {
  pname = "space-grotesk";
  version = "2.0.0";

  src = fetchzip {
    url = "https://github.com/floriankarsten/space-grotesk/releases/download/${version}/SpaceGrotesk-${version}.zip";
    sha256 = "sha256-niwd5E3rJdGmoyIFdNcK5M9A9P2rCbpsyZCl7CDv7I8=";
    stripRoot = false;
  };

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/fonts/truetype
    find SpaceGrotesk-2.0.0/ttf -name "*.ttf" -exec cp {} $out/share/fonts/truetype/ \;

    runHook postInstall
  '';

  meta = with lib; {
    description = "Space Grotesk - A proportional variant of Space Mono";
    homepage = "https://github.com/floriankarsten/space-grotesk";
    license = licenses.ofl;
    platforms = platforms.all;
    maintainers = [ ];
  };
}
