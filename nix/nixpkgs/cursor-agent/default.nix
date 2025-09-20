{
  pkgs,
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  ...
}:

let
  version = "2025.09.12-4852336";

  src =
    if stdenv.isDarwin then
      if stdenv.isAarch64 then
        fetchurl {
          url = "https://downloads.cursor.com/lab/${version}/darwin/arm64/agent-cli-package.tar.gz";
          sha256 = "sha256-jv2g4zKhcWGJc/0/LSYoXiXHjJqimaaPw24x73o0m6M=";
        }
      else
        fetchurl {
          url = "https://downloads.cursor.com/lab/${version}/darwin/x64/agent-cli-package.tar.gz";
          sha256 = "sha256-iP3RNgy5qQeGd9STWI/eN8p2MKG3ZGdQ/NUsQn/oUrk=";
        }
    else if stdenv.isAarch64 then
      fetchurl {
        url = "https://downloads.cursor.com/lab/${version}/linux/arm64/agent-cli-package.tar.gz";
        sha256 = "sha256-zWIg5lrwVGpmO8jW0vglo8r9wmCvxyfvgWv6LO8P9mg=";
      }
    else
      fetchurl {
        url = "https://downloads.cursor.com/lab/${version}/linux/x64/agent-cli-package.tar.gz";
        sha256 = "sha256-tUy4sxaDsPL2aIMjd3W/1aAj2uL04He90sQ0k3YxRtE=";
      };
in
stdenv.mkDerivation rec {
  pname = "cursor-agent";
  inherit version;
  inherit src;

  nativeBuildInputs = lib.optionals stdenv.isLinux [ autoPatchelfHook ];

  buildInputs = lib.optionals stdenv.isLinux [
    stdenv.cc.cc.lib
    stdenv.cc.libc
  ];

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp -r dist-package/* $out/bin/

    # Rename bundled binaries to avoid conflicts
    mv $out/bin/node $out/bin/cursor-node
    if [ -f $out/bin/rg ]; then
      mv $out/bin/rg $out/bin/cursor-rg
    fi

    # Update cursor-agent script to use renamed node
    sed -i 's|NODE_BIN="$SCRIPT_DIR/node"|NODE_BIN="$SCRIPT_DIR/cursor-node"|' $out/bin/cursor-agent

    # Make only cursor-agent executable in PATH, keep other binaries private
    chmod +x $out/bin/cursor-agent $out/bin/cursor-node
    if [ -f $out/bin/cursor-rg ]; then
      chmod +x $out/bin/cursor-rg
    fi

    runHook postInstall
  '';

  meta = with lib; {
    description = "Cursor Agent CLI tool for AI-powered code editing";
    homepage = "https://cursor.com";
    license = licenses.unfree;
    maintainers = [ ];
    platforms = platforms.unix;
    mainProgram = "cursor-agent";
  };
}
