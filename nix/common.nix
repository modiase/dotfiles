{ pkgs }:

with pkgs;
[
  awscli2
  cargo
  claude-code
  codex-cli
  coreutils
  direnv
  docker
  fd
  fzf
  go
  google-cloud-sdk
  gcc
  gemini-cli
  gnused
  gpt-cli
  httpie
  jq
  jwt-cli
  ngrok
  nix-prefetch-git
  nix-tree
  nixfmt-rfc-style
  nodePackages.pnpm
  nodePackages.ts-node
  nodePackages.typescript
  nodejs
  pass
  pass-git-helper
  poetry
  pre-commit
  pstree
  (python313.withPackages (
    ps: with ps; [
      boto3
      ipython
      matplotlib
      numpy
      pandas
      ruff
    ]
  ))
  pstree
  ripgrep
  tldr
  tree
  tshark
  uv
  watch
  wireguard-tools
]
