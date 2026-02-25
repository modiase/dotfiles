{
  config,
  pkgs,
  lib,
  isDev ? false,
  user ? "moye",
  ...
}:

let
  secrets = pkgs.callPackage ./nixpkgs/secrets { };
  ntfy-me = pkgs.callPackage ./nixpkgs/ntfy-me { inherit secrets; };

  commonPackages = with pkgs; [
    git-crypt
  ];

  devPackages = with pkgs; [
    (callPackage ./nixpkgs/ankigen { })
    (callPackage ./nixpkgs/semsearch { })
    (callPackage ./nixpkgs/coder { })
    (writeShellScriptBin "chafa" ''
      if [[ -n "$TMUX" ]]; then
        exec ${chafa}/bin/chafa --format kitty --passthrough tmux "$@"
      else
        exec ${chafa}/bin/chafa "$@"
      fi
    '')
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
    bat
    cargo
    coreutils
    delta
    docker
    doggo
    duf
    dust
    eternal-terminal
    eza
    fd
    fzf
    gcc
    gemini-cli
    gh
    gnused
    go
    google-cloud-sdk
    gopls
    gum
    httpie
    imagemagick
    jq
    just
    jwt-cli
    kubectl
    lsof
    moor
    ncdu
    neovim-remote
    ngrok
    nix-prefetch-git
    nix-tree
    nixfmt-rfc-style
    nmap
    nodePackages.pnpm
    nodePackages.svelte-language-server
    nodePackages.typescript
    nodejs
    ntfy-me
    ntfy-sh
    opentofu
    pgcli
    pre-commit
    procs
    pstree
    ripgrep
    sd
    secrets
    terraform-ls
    tldr
    tshark
    uv
    watch
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
    ./nixpkgs/agents-config
    ./nixpkgs/claude-code
    ./nixpkgs/yazi
  ];

  home = {
    username = user;

    packages =
      commonPackages
      ++ lib.optionals isDev devPackages
      ++ lib.optionals (isDev && pkgs.stdenv.isLinux) (
        with pkgs;
        [
          pass
          pass-git-helper
        ]
      );

    file = {
      ".config/nvim" = {
        source = lib.cleanSourceWith {
          src = ../nvim;
          filter =
            path: type:
            !(lib.hasSuffix "coc-settings.json" path)
            && !(lib.hasSuffix "lua/plugins/coc.lua" path)
            && !(lib.hasSuffix "lua/plugins/claudecode.lua" path);
        };
        recursive = true;
      };

      ".config/nvim/coc-settings.json" = lib.mkDefault {
        text =
          let
            base = builtins.fromJSON (builtins.readFile ../nvim/coc-settings.json);
            svelte = builtins.fromJSON (builtins.readFile ../nvim/coc-languageservers/svelte.json);
            terraform = builtins.fromJSON (builtins.readFile ../nvim/coc-languageservers/terraform.json);
          in
          builtins.toJSON (lib.recursiveUpdate base { languageserver = svelte // terraform; });
      };

      ".config/nvim/lua/plugins/coc.lua" = lib.mkDefault {
        text =
          let
            cocLua = builtins.readFile ../nvim/lua/plugins/coc.lua;
            baseExts = builtins.fromJSON (builtins.readFile ../nvim/coc-extensions/base.json);
            frontendExts = builtins.fromJSON (builtins.readFile ../nvim/coc-extensions/frontend.json);
            extsList = builtins.concatStringsSep ", " (map (e: ''"${e}"'') (baseExts ++ frontendExts));
          in
          builtins.replaceStrings [ "-- @COC_EXTENSIONS@" ] [ extsList ] cocLua;
      };

      ".config/nvim/lua/plugins/claudecode.lua" = lib.mkDefault {
        text = builtins.readFile ../nvim/lua/plugins/claudecode.lua;
      };

      ".config/pass-git-helper/git-pass-mapping.ini" = lib.mkIf (isDev && pkgs.stdenv.isLinux) {
        text = ''
          [github.com*]
          target=git/github.com
        '';
      };
    };

    stateVersion = "24.05";
  };

  programs = {
    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    tmux.enable = lib.mkDefault isDev;
    neovim.enable = lib.mkDefault isDev;
    fish.enable = lib.mkDefault isDev;
  };

  dotfiles.agents-config.enable = isDev;
  dotfiles.claude-code.enable = isDev;
}
