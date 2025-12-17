{
  config,
  pkgs,
  lib,
  ...
}:

{
  imports = [
    ./alacritty.nix
    ./bat.nix
    ./btop.nix
    ./fish.nix
    ./git.nix
    ./neovim.nix
    ./sh.nix
    ./tmux.nix
  ];

  home.username = "moye";

  home.packages = with pkgs; [
    (callPackage ./nixpkgs/ankigen { })
    (callPackage ./nixpkgs/cursor-agent { })
    (callPackage ./nixpkgs/coder { })
    (callPackage ./nixpkgs/secretsmanager { })
    cargo
    claude-code
    codex-cli
    coreutils
    delta
    direnv
    docker
    duf
    dust
    eza
    fd
    fzf
    gcc
    gemini-cli
    gh
    glow
    gnused
    go
    google-cloud-sdk
    gopls
    gpt-cli
    httpie
    jq
    jwt-cli
    kubectl
    lsof
    moor
    ncdu
    ngrok
    nix-prefetch-git
    nix-tree
    nixfmt-rfc-style
    nmap
    nodePackages.pnpm
    nodePackages.typescript
    nodejs
    ntfy-sh
    opentofu
    pass
    pass-git-helper
    pgcli
    poetry
    pre-commit
    procs
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
    sd
    nodePackages.svelte-language-server
    terraform-ls
    tldr
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
