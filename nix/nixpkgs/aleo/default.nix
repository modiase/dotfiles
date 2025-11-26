{
  stdenv,
  fetchzip,
  lib,
}:

stdenv.mkDerivation rec {
  pname = "aleo";
  version = "master";

  src = fetchzip {
    url = "https://github.com/AlessioLaiso/aleo/archive/refs/heads/master.zip";
    sha256 = "sha256-IlKlVZu4wiZWolaRrxhgryFfE0INNZcEZj5kgq8LwIA=";
    stripRoot = false;
  };

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/fonts/truetype
    find aleo-master/fonts -name "*.ttf" -exec cp {} $out/share/fonts/truetype/ \;

    runHook postInstall
  '';

  meta = with lib; {
    description = "Aleo - A slab serif typeface family";
    homepage = "https://github.com/AlessioLaiso/aleo";
    license = licenses.ofl;
    platforms = platforms.all;
    maintainers = [ ];
  };
}
