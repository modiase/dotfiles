{
  python3,
  runCommand,
}:

let
  python = python3.withPackages (ps: [ ps.cryptography ]);
in
runCommand "gcp-wif-token" { } ''
  mkdir -p $out/bin
  cp ${./gcp-wif-token.py} $out/bin/gcp-wif-token
  chmod +x $out/bin/gcp-wif-token
  substituteInPlace $out/bin/gcp-wif-token \
    --replace-fail "#!/usr/bin/env python3" "#!${python}/bin/python3"
''
