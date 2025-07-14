{
  lib,
  python3Packages,
  gnused,
}:

python3Packages.buildPythonApplication rec {
  pname = "gpt_command_line";
  version = "0.4.3";

  format = "pyproject";

  src = python3Packages.fetchPypi {
    inherit pname version;
    sha256 = "1ilrsk5f3zsbz3gmm1qgmc6y8rn60cdr1x02k4j1b6752lbfcgg3";
  };

  nativeBuildInputs =
    with python3Packages;
    [
      setuptools
      wheel
      pip
    ]
    ++ [ gnused ];

  propagatedBuildInputs = with python3Packages; [
    click
    openai
    rich
    pyyaml
    anthropic
    attrs
    black
    cohere
    google-genai
    prompt-toolkit
    pytest
    typing-extensions
  ];

  postPatch = ''
    sed -i 's/~=/>=/' pyproject.toml
    sed -i '/^TERMINAL_WELCOME = """/,/^"""/c\TERMINAL_WELCOME = ""' gptcli/cli.py
  '';

  postInstall = ''
    ln -s $out/bin/gpt $out/bin/gptcli
  '';

  pythonImportsCheck = [ "gptcli" ];

  meta = with lib; {
    description = "A command-line interface for GPT models";
    homepage = "https://github.com/kharvd/gpt-cli";
    license = licenses.mit;
    maintainers = with maintainers; [ ];
  };
}
