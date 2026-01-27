{
  python3,
  runCommand,
}:

runCommand "derive-age-key" { } ''
  mkdir -p $out/bin
  cp ${./derive-age-key.py} $out/bin/derive-age-key
  chmod +x $out/bin/derive-age-key
  substituteInPlace $out/bin/derive-age-key \
    --replace-fail "/usr/bin/env python3" "${python3}/bin/python3"
''
