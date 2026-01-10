{
  config,
  pkgs,
  lib,
  isFrontend ? false,
  ...
}:

let
  secrets = pkgs.callPackage ./nixpkgs/secrets { };
  ntfy-me = pkgs.callPackage ./nixpkgs/ntfy-me { inherit secrets; };

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
    google-cloud-sdk
    jq
    lsof
    moor
    ntfy-me
    procs
    pstree
    ripgrep
    sd
    secrets
    watch
  ];

  frontendPackages = with pkgs; [
    (callPackage ./nixpkgs/ankigen { })
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
    claude-code
    docker
    gcc
    gemini-cli
    gh
    go
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

  home.file.".claude/CLAUDE.md".text = ''
    # Code Quality Guidelines

    ## Mandatory Review
    After EVERY round of changes, review your work against these guidelines before finalising.

    ## Context Maintenance
    - After conversation compaction, re-read any `CLAUDE.md` and `AGENTS.md` files in the repo
    - Periodically reconsider repo-specific rules to ensure continued compliance
    - When in doubt about conventions, check these files rather than assuming

    ## Comments
    - Comments may be used during implementation to track ideas and intent
    - During code quality review (after each round of changes), **remove all obvious comments**
    - **ONLY keep comments that explain**: workarounds, non-obvious behaviour, security implications
    - **PRESERVE identifying labels** when names can't be inferred from context

    ### Examples

    ```bash
    # BAD: Obvious comments
    # Fetch the user data
    user_data=$(curl "$url")
    # Check if successful
    if [[ $? -eq 0 ]]; then
        # Parse the JSON response
        name=$(echo "$user_data" | jq -r '.name')
    fi

    # GOOD: No obvious comments, only non-obvious behaviour documented
    user_data=$(curl "$url")
    if [[ $? -eq 0 ]]; then
        # jq returns "null" string (not empty) for missing keys
        name=$(echo "$user_data" | jq -r '.name // empty')
    fi
    ```

    ```nix
    # BAD: Comment states the obvious
    # Enable fish shell
    programs.fish.enable = true;

    # GOOD: Comment explains WHY (non-obvious)
    # Required for proper TERM handling in tmux
    programs.fish.interactiveShellInit = "set -gx TERM xterm-256color";
    ```

    ## Shell Scripting Style

    ### Prefer `&&` chaining over if/else
    ```bash
    # BAD: Verbose if/else
    if [[ "$condition" ]]; then
        do_something
    else
        fallback_action
    fi

    # GOOD: Chain with && and early return
    [[ "$condition" ]] && do_something && return
    fallback_action
    ```

    ### Use conditional assignment
    ```bash
    # BAD: if/else for variable assignment
    if [[ "$condition" ]]; then
        local output="$alternate"
    else
        local output="$default"
    fi

    # GOOD: Conditional assignment
    local output="$default"
    [[ "$condition" ]] && output="$alternate"
    ```

    ### CRITICAL: `set -e` with `[[ ]] &&`
    When using `set -e`, a bare `[[ condition ]] && cmd` exits with code 1 if false.

    ```bash
    # WRONG: Script exits if LOG_LEVEL < 4
    set -e
    [[ ''${LOG_LEVEL:-2} -ge 4 ]] && set -x

    # CORRECT: Use if statement
    if [[ ''${LOG_LEVEL:-2} -ge 4 ]]; then set -x; fi

    # CORRECT: Add || true fallback
    [[ ''${LOG_LEVEL:-2} -ge 4 ]] && set -x || true
    ```

    ## Configuration Best Practices
    - **Research defaults first** - only specify values that differ
    - **Extract shared config** into variables when used 2+ times
    - **Inline single-use variables** - except when aiding readability

    ## Language
    - Use **British English** spelling (summarise, colour, organisation)

    ## Pre-commit
    - After each round of changes, check if the project has a `.pre-commit-config.yaml`
    - If present, run `pre-commit run` on staged files before considering work complete
    - Fix any issues reported by hooks, then re-run until clean

    ## Git Commits
    - **NEVER commit to main** unless explicitly instructed
    - Exception: when working on a separate Claude-authored branch, commits are permitted
    - When in doubt, wait for user approval before committing

    ## Preferred Tools
    | Instead of | Use | Why |
    |------------|-----|-----|
    | `find` | `fd` | Faster, respects .gitignore (less noise) |
    | `grep` | `rg` | Faster, respects .gitignore (less noise) |

    ## Core Principles
    - **Be Precise**: State facts, not assumptions
    - **Be Thorough**: Research completely before acting
    - **Be Efficient**: Anticipate issues rather than discover through trial-and-error
  '';

  home.stateVersion = "24.05";
}
