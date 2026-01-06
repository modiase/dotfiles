{
  config,
  pkgs,
  lib,
  isFrontend ? false,
  ...
}:

let
  commonPackages = with pkgs; [
    coreutils
    delta
    direnv
    doggo
    duf
    dust
    eternal-terminal
    eza
    fd
    fzf
    gnused
    jq
    lsof
    moor
    procs
    pstree
    ripgrep
    sd
    watch
    (callPackage ./nixpkgs/secrets { })
  ];

  frontendPackages = with pkgs; [
    (callPackage ./nixpkgs/ankigen { })
    (callPackage ./nixpkgs/coder { })
    cargo
    (writeShellScriptBin "chafa" ''
      if [[ -n "$TMUX" ]]; then
        exec ${chafa}/bin/chafa --format kitty --passthrough tmux "$@"
      else
        exec ${chafa}/bin/chafa "$@"
      fi
    '')
    claude-code
    docker
    gcc
    gemini-cli
    gh
    go
    google-cloud-sdk
    gopls
    httpie
    imagemagick
    jwt-cli
    kubectl
    ncdu
    ngrok
    nix-prefetch-git
    nix-tree
    nixfmt-rfc-style
    nmap
    nodePackages.pnpm
    nodePackages.svelte-language-server
    nodePackages.typescript
    nodejs
    ntfy-sh
    opentofu
    pgcli
    pre-commit
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
    terraform-ls
    tldr
    tshark
    uv
    wireguard-tools
  ];
in
{
  imports = [
    ./bat.nix
    ./btop.nix
    ./fish.nix
    ./git.nix
    ./ghostty.nix
    ./neovim.nix
    ./sh.nix
    ./tmux.nix
  ];

  home.username = "moye";

  home.packages =
    commonPackages
    ++ lib.optionals isFrontend frontendPackages
    ++ lib.optionals (isFrontend && pkgs.stdenv.isLinux) (
      with pkgs;
      [
        pass
        pass-git-helper
      ]
    );

  home.file.".config/nvim" = {
    source = ../nvim;
    recursive = true;
  };

  home.file.".config/pass-git-helper/git-pass-mapping.ini" =
    lib.mkIf (isFrontend && pkgs.stdenv.isLinux)
      {
        text = ''
          [github.com*]
          target=git/github.com
        '';
      };

  home.stateVersion = "24.05";
}
