{
  config,
  pkgs,
  system,
  lib,
  ...
}:

{
  imports =
    [
      ./alacritty.nix
      ./bat.nix
      ./btop.nix
      ./fish.nix
      ./git.nix
      ./neovim.nix
      ./sh.nix
      ./tmux.nix
    ]
    ++ (if system == "aarch64-darwin" then [ ./platforms/darwin.nix ] else [ ./platforms/linux.nix ])
    ++ (
      if lib.hasPrefix "aarch64" system then
        [ ./architectures/aarch64.nix ]
      else
        [ ./architectures/x86_64.nix ]
    );

  home.username = "moye";

  home.packages = with pkgs; [
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
    gopls
    google-cloud-sdk
    gcc
    gemini-cli
    gnused
    gpt-cli
    httpie
    jq
    jwt-cli
    kubectl
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
  ];

  home.file.".config/nvim" = {
    source = ../nvim;
    recursive = true;
  };

  home.file.".config/pass-git-helper/git-pass-mapping.ini" = {
    text = ''
      [github.com*]
      target=git/github.com
    '';
  };

  home.stateVersion = "24.05";
}
