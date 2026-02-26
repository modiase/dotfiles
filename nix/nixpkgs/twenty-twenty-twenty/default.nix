{
  python313,
  python313Packages,
  fetchPypi,
  terminal-notifier,
  runCommand,
  makeBinaryWrapper,
}:

let
  rumps = python313Packages.buildPythonPackage {
    pname = "rumps";
    version = "0.4.0";
    pyproject = true;
    src = fetchPypi {
      pname = "rumps";
      version = "0.4.0";
      hash = "sha256-F/szwhtUseJdsNcdHXk9wZ3DwLfYx53G2DPQz/yLFZY=";
    };
    build-system = [ python313Packages.setuptools ];
    dependencies = [ python313Packages.pyobjc-framework-Cocoa ];
    pythonImportsCheck = [ "rumps" ];
  };

  python = python313.withPackages (ps: [
    rumps
    ps.pyobjc-framework-Quartz
    ps.pyobjc-framework-Cocoa
  ]);
in
runCommand "twenty-twenty-twenty"
  {
    nativeBuildInputs = [ makeBinaryWrapper ];
  }
  ''
    mkdir -p $out/bin $out/libexec
    cp ${./main.py} $out/libexec/main.py
    substituteInPlace $out/libexec/main.py \
      --replace-fail "@@TERMINAL_NOTIFIER@@" "${terminal-notifier}/bin/terminal-notifier"

    makeBinaryWrapper ${python}/bin/python3 $out/bin/twenty-twenty-twenty \
      --add-flags $out/libexec/main.py
  ''
