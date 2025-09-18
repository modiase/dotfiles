{
  stdenv,
  fetchzip,
  lib,
}:

stdenv.mkDerivation rec {
  pname = "lato";
  version = "master";

  src = fetchzip {
    url = "https://github.com/mrkelly/lato/archive/refs/heads/master.zip";
    sha256 = "sha256-hWRyyhsAAnDZnHh7z2PcG35ZREibZdehqUVrgMEpIYY=";
    stripRoot = false;
  };

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/fonts/truetype
    find lato-master/font -name "*.ttf" -exec cp {} $out/share/fonts/truetype/ \;

    runHook postInstall
  '';

  meta = with lib; {
    description = "Lato - A sanserif typeface family";
    homepage = "https://github.com/latofonts/lato";
    license = licenses.ofl;
    platforms = platforms.all;
    maintainers = [ ];
  };
}
