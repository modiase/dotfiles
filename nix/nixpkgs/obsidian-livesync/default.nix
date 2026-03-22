{ stdenv, fetchurl }:
let
  version = "0.25.54";
  base = "https://github.com/vrtmrz/obsidian-livesync/releases/download/${version}";
in
stdenv.mkDerivation {
  pname = "obsidian-livesync";
  inherit version;
  dontUnpack = true;
  installPhase = ''
    mkdir -p $out
    cp ${
      fetchurl {
        url = "${base}/main.js";
        hash = "sha256-BH3o8jWDv9mpVkeGILz+ILCc15MTTJcO3ns+6yvR498=";
      }
    } $out/main.js
    cp ${
      fetchurl {
        url = "${base}/manifest.json";
        hash = "sha256-sz/Z1SuCWoNWYl3B0UZ+ERPM4JAh56qH1zQMrCCfFGQ=";
      }
    } $out/manifest.json
    cp ${
      fetchurl {
        url = "${base}/styles.css";
        hash = "sha256-SKokAKsGwX0YAoczW+1++6ukiOc9QAi8NB8LJsrox8E=";
      }
    } $out/styles.css
  '';
}
