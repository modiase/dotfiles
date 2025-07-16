{
  pkgs ? import <nixpkgs> { },
  stdenv ? pkgs.stdenv,
  lib ? pkgs.lib,
}:

let
  apple-containers = pkgs.stdenv.mkDerivation rec {
    pname = "apple-containers";
    version = "0.2.0";

    src = pkgs.fetchurl {
      url = "https://github.com/apple/container/releases/download/${version}/container-${version}-installer-signed.pkg";
      sha256 = "sha256-aJEIy6IknBDvM7IOhnl/C4xnr7KJVggJJjmajqoHdsU=";
    };

    nativeBuildInputs = with pkgs; [
      xar
      gnutar
      gzip
      file
      cpio
    ];

    preBuild = ''
      if [ "$(uname -m)" != "arm64" ]; then
        echo "ERROR: Apple Containers requires Apple Silicon (arm64) architecture"
        exit 1
      fi

      # Check macOS version using system_profiler or kernel version as fallback
      if command -v system_profiler >/dev/null 2>&1; then
        MACOS_VERSION=$(system_profiler SPSoftwareDataType | grep "System Version" | awk '{print $4}' | head -1)
      elif [ -f /System/Library/CoreServices/SystemVersion.plist ]; then
        MACOS_VERSION=$(defaults read /System/Library/CoreServices/SystemVersion.plist ProductVersion 2>/dev/null || echo "unknown")
      else
        echo "WARNING: Cannot determine macOS version, skipping version checks"
        MACOS_VERSION="unknown"
      fi

      if [ "$MACOS_VERSION" != "unknown" ]; then
        MACOS_MAJOR=$(echo $MACOS_VERSION | cut -d. -f1)
        echo "Detected macOS version: $MACOS_VERSION"

        if [ "$MACOS_MAJOR" -lt 15 ]; then
          echo "WARNING: Apple Containers may not work properly on macOS versions below 15"
        fi

        if [ "$MACOS_MAJOR" -eq 15 ]; then
          echo "WARNING: macOS 15 has significant networking limitations with Apple Containers"
        fi
      fi
    '';

    unpackPhase = ''
      runHook preUnpack

      mkdir -p extracted
      cd extracted

      xar -xf $src

      if [ -f "container.pkg/Payload" ]; then
        cd container.pkg
        PAYLOAD_FILE="Payload"
      elif [ -f "Payload" ]; then
        PAYLOAD_FILE="Payload"
      else
        echo "Could not find Payload in pkg file"
        exit 1
      fi

      if file $PAYLOAD_FILE | grep -q "gzip"; then
        cat $PAYLOAD_FILE | gunzip -dc | cpio -i
      else
        cpio -i < $PAYLOAD_FILE
      fi

      runHook postUnpack
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out/bin
      mkdir -p $out/share/man/man1

      if [ -f "usr/local/bin/container" ]; then
        cp usr/local/bin/container $out/bin/
      elif [ -f "bin/container" ]; then
        cp bin/container $out/bin/
      else
        echo "Could not find container binary"
        exit 1
      fi

      if [ -d "usr/local/share/man" ]; then
        cp -r usr/local/share/man/* $out/share/man/ || true
      fi

      chmod +x $out/bin/container

      runHook postInstall
    '';

    postInstall = ''
      $out/bin/container --version
    '';

    meta = with lib; {
      description = "Tool to create and run Linux containers as lightweight VMs on Apple Silicon Macs";
      homepage = "https://github.com/apple/container";
      license = licenses.asl20;
      maintainers = with maintainers; [ ];
      platforms = [ "aarch64-darwin" ];
      broken = false;
      requiredSystemFeatures = [ "apple-silicon" ];
    };
  };
in
apple-containers
