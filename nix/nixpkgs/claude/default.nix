{ pkgs ? import <nixpkgs> { } }:

let
  claude-code = pkgs.stdenv.mkDerivation {
    pname = "claude-code";
    version = "0.2.36";
    src = pkgs.fetchFromGitHub {
      owner = "anthropics";
      repo = "claude-code";
      rev = "555b6b5b8a5f06f1e8725a584e62fb6b7c8eece5"; # Match with version
      sha256 =
        "sha256-9nF+RrtuQ3pIiePG90iKHeZosNwHX9XBzhS7z7nTkJE="; # Update this
    };

    nativeBuildInputs = [ pkgs.nodejs-18_x ];
    buildInputs = [ pkgs.nodejs-18_x ];

    installPhase = ''
            runHook preInstall
            export HOME="$TMPDIR"
      	  npm config set strict-ssl false
      	  npm install --prefix "$out" @anthropic-ai/claude-code


            runHook postInstall
    '';
    postInstall = ''
        mkdir -p "$out/bin"
      cat <<EOF > "$out/bin/claude"
      #!/usr/bin/env sh
      ${pkgs.nodejs-18_x}/bin/node "$out/node_modules/@anthropic-ai/claude-code/cli.js"
      EOF
      chmod +x "$out/bin/claude"
    '';

    installFlags = [ "PREFIX=$(out)" ];

    meta = with pkgs.lib; {
      description = "CLI to interact with the Claude model";
      homepage = "https://github.com/anthropics/claude-code";
      license = licenses.mit;
      maintainers = with maintainers; [ ];
      platforms = platforms.unix;
    };
  };
in claude-code
