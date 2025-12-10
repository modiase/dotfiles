{
  config,
  pkgs,
  system,
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
    go
    gopls
    google-cloud-sdk
    gcc
    gemini-cli
    gh
    gnused
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
    procs
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
