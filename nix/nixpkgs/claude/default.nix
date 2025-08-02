{
  pkgs ? import <nixpkgs> { },
}:

let
  claude-code = pkgs.stdenv.mkDerivation {
    pname = "claude-code";
    version = "1.0.62";
    src = pkgs.fetchFromGitHub {
      owner = "anthropics";
      repo = "claude-code";
      rev = "5faa082d6e4e5300485daafb94615fe133175055";
      sha256 = "1abbr41r6giw7ks5k2p471bhmihl5vhsanpjn29664xx86mkj5z9";
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
in
claude-code
