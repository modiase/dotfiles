{
  config,
  pkgs,
  lib,
  isFrontend ? false,
  user ? "moye",
  ...
}:

let
  secrets = pkgs.callPackage ./nixpkgs/secrets { };
  ntfy-me = pkgs.callPackage ./nixpkgs/ntfy-me { inherit secrets; };

  commonPackages = with pkgs; [
    bat
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
    git-crypt
    gnused
    google-cloud-sdk
    gum
    httpie
    jq
    lsof
    moor
    neovim-remote
    ntfy-me
    pre-commit
    procs
    pstree
    ripgrep
    sd
    secrets
    watch
  ];

  frontendPackages = with pkgs; [
    (callPackage ./nixpkgs/ankigen { })
    (callPackage ./nixpkgs/semsearch { })
    (callPackage ./nixpkgs/awrit { })
    (callPackage ./nixpkgs/coder { })
    cargo
    (writeShellScriptBin "chafa" ''
      if [[ -n "$TMUX" ]]; then
        exec ${chafa}/bin/chafa --format kitty --passthrough tmux "$@"
      else
        exec ${chafa}/bin/chafa "$@"
      fi
    '')
    docker
    gcc
    gemini-cli
    gh
    go
    gopls
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
    ./nixpkgs/claude-code
    ./nixpkgs/yazi
  ];

  home.username = user;

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
    source = lib.cleanSourceWith {
      src = ../nvim;
      filter =
        path: type:
        !(lib.hasSuffix "coc-settings.json" path) && !(lib.hasSuffix "lua/plugins/coc.lua" path);
    };
    recursive = true;
  };

  home.file.".config/nvim/coc-settings.json" = lib.mkDefault {
    text =
      let
        base = builtins.fromJSON (builtins.readFile ../nvim/coc-settings.json);
        svelte = builtins.fromJSON (builtins.readFile ../nvim/coc-languageservers/svelte.json);
        terraform = builtins.fromJSON (builtins.readFile ../nvim/coc-languageservers/terraform.json);
      in
      builtins.toJSON (lib.recursiveUpdate base { languageserver = svelte // terraform; });
  };

  home.file.".config/nvim/lua/plugins/coc.lua" = lib.mkDefault {
    text =
      let
        cocLua = builtins.readFile ../nvim/lua/plugins/coc.lua;
        baseExts = builtins.fromJSON (builtins.readFile ../nvim/coc-extensions/base.json);
        frontendExts = builtins.fromJSON (builtins.readFile ../nvim/coc-extensions/frontend.json);
        extsList = builtins.concatStringsSep ", " (map (e: ''"${e}"'') (baseExts ++ frontendExts));
      in
      builtins.replaceStrings [ "-- @COC_EXTENSIONS@" ] [ extsList ] cocLua;
  };

  home.file.".config/pass-git-helper/git-pass-mapping.ini" =
    lib.mkIf (isFrontend && pkgs.stdenv.isLinux)
      {
        text = ''
          [github.com*]
          target=git/github.com
        '';
      };

  programs.claude-code.enable = isFrontend;

  home.stateVersion = "24.05";
}
