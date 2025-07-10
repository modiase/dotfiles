{ pkgs }:

with pkgs;
[
  awscli2
  cargo
  claude-code
  coreutils
  direnv
  docker
  fd
  fzf
  google-cloud-sdk
  gcc
  gemini-cli
  gnused
  gpt-cli
  httpie
  jq
  jwt-cli
  nix-prefetch-git
  nix-tree
  nodePackages.pnpm
  nodePackages.ts-node
  nodePackages.typescript
  nodejs
  pass
  pass-git-helper
  poetry
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
]
