{
  config,
  pkgs,
  lib,
  ...
}:

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

  home.packages = with pkgs; [
    (callPackage ./nixpkgs/ankigen { })
    (callPackage ./nixpkgs/cursor-agent { })
    (callPackage ./nixpkgs/coder { })
    (callPackage ./nixpkgs/secretsmanager { })
    cargo
    (writeShellScriptBin "chafa" ''
      if [[ -n "$TMUX" ]]; then
        exec ${chafa}/bin/chafa --format kitty --passthrough tmux "$@"
      else
        exec ${chafa}/bin/chafa "$@"
      fi
    '')
    (writeShellScriptBin "yank" ''
      # OSC52 clipboard script - https://sunaku.github.io/tmux-yank-osc52.html
      input=$( cat "$@" )
      input() { printf %s "$input" ;}

      # copy via OSC 52
      printf_escape() {
        esc=$1
        test -n "$TMUX" -o -z "''${TERM##screen*}" && esc="\033Ptmux;\033$esc\033\\"
        printf "$esc"
      }
      len=$( input | wc -c ) max=74994
      test $len -gt $max && echo "$0: input is $(( len - max )) bytes too long" >&2
      printf_escape "\033]52;c;$( input | head -c $max | base64 | tr -d '\r\n' )\a"
    '')
    claude-code
    codex-cli
    coreutils
    delta
    direnv
    docker
    doggo
    duf
    dust
    eza
    fd
    fzf
    gcc
    gemini-cli
    gh
    gnused
    glow
    go
    google-cloud-sdk
    gopls
    httpie
    jq
    jwt-cli
    kubectl
    lsof
    mosh
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
