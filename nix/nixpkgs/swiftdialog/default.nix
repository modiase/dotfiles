{
  lib,
  stdenv,
  fetchurl,
  cpio,
  xar,
}:

stdenv.mkDerivation rec {
  pname = "swiftdialog";
  version = "2.5.6";

  src = fetchurl {
    url = "https://github.com/swiftDialog/swiftDialog/releases/download/v${version}/dialog-${version}-4805.pkg";
    sha256 = "sha256-ab1/ZBKhsjk5BvwFk2nmXFrlivXMjSiUZ+/9EdiGKyo=";
  };

  nativeBuildInputs = [
    xar
    cpio
  ];

  unpackPhase = ''
    xar -xf $src
    cd tmp-package.pkg
    cat Payload | gunzip -dc | cpio -i
  '';

  installPhase = ''
    mkdir -p $out/bin $out/Applications
    cp -r "Library/Application Support/Dialog/Dialog.app" $out/Applications/

    substitute usr/local/bin/dialog $out/bin/dialog \
      --replace-fail '/Library/Application Support/Dialog/Dialog.app' "$out/Applications/Dialog.app"
    chmod +x $out/bin/dialog
  '';

  meta = with lib; {
    description = "macOS admin utility for displaying custom dialogs";
    homepage = "https://swiftdialog.app/";
    license = licenses.asl20;
    platforms = platforms.darwin;
    mainProgram = "dialog";
  };
}
