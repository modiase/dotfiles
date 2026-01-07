{ python313Packages }:

python313Packages.buildPythonPackage {
  pname = "pyutils";
  version = "0.1.0";
  src = ./.;
  format = "pyproject";

  build-system = [ python313Packages.setuptools ];

  dependencies = with python313Packages; [
    click
    inquirer
    loguru
    google-cloud-storage
    pexpect
  ];

  pythonImportsCheck = [ "pyutils" ];
}
