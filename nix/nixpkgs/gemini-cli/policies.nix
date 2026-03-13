let
  shell = cmd: {
    toolName = "run_shell_command";
    commandPrefix = cmd;
  };

  shellRegex = regex: {
    toolName = "run_shell_command";
    commandRegex = regex;
  };

  allow =
    priority: rules:
    map (
      r:
      r
      // {
        decision = "allow";
        inherit priority;
      }
    ) rules;
  deny =
    priority: rules:
    map (
      r:
      r
      // {
        decision = "deny";
        inherit priority;
      }
    ) rules;

  readTools = map (t: { toolName = t; }) [
    # keep-sorted start
    "codebase_investigator"
    "glob"
    "list_directory"
    "read_file"
    "save_memory"
    "search_file_content"
    # keep-sorted end
  ];

  webRules = [
    { toolName = "google_web_search"; }
    {
      toolName = "web_fetch";
      argsPattern = "(crates\\.io|developer\\.mozilla\\.org|docs\\.anthropic\\.com|docs\\.docker\\.com|docs\\.python\\.org|docs\\.rs|github\\.com|home-assistant\\.io|huggingface\\.co|kubernetes\\.io|learn\\.microsoft\\.com|nixos\\.org|nixos\\.wiki|npmjs\\.com|pkg\\.go\\.dev|postgresql\\.org|pypi\\.org|pytorch\\.org|raw\\.githubusercontent\\.com|redis\\.io|tensorflow\\.org|wiki\\.nixos\\.org)";
    }
  ];

  nixRules = map shell [
    # keep-sorted start
    "nix build"
    "nix eval"
    "nix flake check"
    "nix flake metadata"
    "nix flake show"
    "nix-build"
    "nix-instantiate"
    "nixos-option"
    # keep-sorted end
  ];

  gitRules =
    let
      cmds = [
        # keep-sorted start
        "git blame"
        "git branch"
        "git config"
        "git describe"
        "git diff"
        "git log"
        "git ls-files"
        "git ls-tree"
        "git reflog"
        "git remote"
        "git rev-parse"
        "git shortlog"
        "git show"
        "git stash list"
        "git stash show"
        "git status"
        "git tag"
        "git worktree list"
        # keep-sorted end
      ];
    in
    (map shell cmds)
    ++ [
      (shellRegex "^git -C [^ ]+ (status|log|diff|show|branch|remote|rev-parse|ls-files|ls-tree)")
    ];

  filesystemRules = map shell [
    # keep-sorted start
    "basename"
    "bat"
    "cat"
    "chafa"
    "dirname"
    "echo"
    "eza"
    "fd"
    "find"
    "grep"
    "head"
    "ls"
    "od"
    "printf"
    "readlink"
    "realpath"
    "rg"
    "sed"
    "stat"
    "tail"
    "tree"
    "wc"
    # keep-sorted end
  ];

  buildRules = map shell [
    # keep-sorted start
    "bin/activate show"
    "curl"
    "gh auth status"
    "gh issue list"
    "gh issue status"
    "gh issue view"
    "gh pr list"
    "gh pr status"
    "gh pr view"
    "gh repo list"
    "gh repo view"
    "go build"
    "go list"
    "go mod tidy"
    "go test"
    "go vet"
    "jq"
    "just --list"
    "just --summary"
    "make"
    "pre-commit"
    "uv lock --check"
    "uv pip list"
    "wget"
    "yq"
    # keep-sorted end
  ];

  gcloudRules = map shell [
    # keep-sorted start
    "gcloud compute instances describe"
    "gcloud compute instances list"
    "gcloud config list"
    "gcloud logging"
    "gcloud projects describe"
    "gcloud storage ls"
    # keep-sorted end
  ];

  systemRules = map shell [
    # keep-sorted start
    "df"
    "du"
    "env"
    "file"
    "free"
    "hostname"
    "id"
    "journalctl"
    "lsof"
    "man"
    "pgrep"
    "printenv"
    "ps"
    "systemctl list-unit-files"
    "systemctl list-units"
    "systemctl show"
    "systemctl status"
    "tldr"
    "type"
    "uname"
    "uptime"
    "which"
    "whoami"
    # keep-sorted end
  ];

  denyRules = deny 900 [
    (shell "gcloud secrets versions access")
    (shell "secrets get")
    (shellRegex "sed (-i|--in-place)")
    {
      toolName = "read_file";
      argsPattern = "\\.ssh/";
    }
  ];

  mcpRules = allow 100 [
    { mcpName = "nvim"; }
  ];

  allowRules = allow 100 (
    readTools
    ++ webRules
    ++ nixRules
    ++ gitRules
    ++ filesystemRules
    ++ buildRules
    ++ gcloudRules
    ++ systemRules
  );

  notesRules = allow 500 [
    {
      toolName = "read_file";
      argsPattern = "notes/";
    }
    {
      toolName = "write_file";
      argsPattern = "notes/";
    }
    {
      toolName = "list_directory";
      argsPattern = "notes/";
    }
    {
      toolName = "replace";
      argsPattern = "notes/";
    }
    {
      toolName = "glob";
      argsPattern = "notes/";
    }
  ];
in
denyRules ++ allowRules ++ mcpRules ++ notesRules
