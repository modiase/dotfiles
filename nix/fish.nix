{ pkgs, ... }:
let
  dotfiles = ../.;
  functionFiles =
    builtins.attrNames (builtins.readDir (dotfiles + /fish/functions));
  toFunctionName = file: pkgs.lib.strings.removeSuffix ".fish" file;
  functions = pkgs.lib.genAttrs (map toFunctionName functionFiles)
    (name: builtins.readFile (dotfiles + /fish/functions + "/${name}.fish"));
in {
  programs.fish = {
    enable = true;
    functions = functions;
    shellAliases = {
      gadd = "git add";
      gamd = "git commit --amend --no-edit";
      gblg = "git reflog show (git branch --show)";
      gci = "git commit";
      gco = "git checkout";
      gcp = "git cherry-pick";
      gdff = "git diff";
      gfch = "git fetch";
      ggc = "git gc";
      ggrep = "git grep";
      ggrph = "git log --all --decorate --oneline --graph";
      ghm = ''
        test "(git branch --show)" = "(git symbolic-ref --short HEAD)" or git checkout (git symbolic-ref --short HEAD)'';
      glg = "git log --oneline";
      gls = "git ls-files";
      gmb = "git merge-base";
      gmrg = "git merge";
      gpath = ''
        git status &>/dev/null; and python -c 'import sys;assert len(sys.argv) >= 3, "Missing argument";from pathlib import Path;print(Path(sys.argv[2]).absolute().relative_to(Path(sys.argv[1])))' (git rev-parse --show-toplevel)'';
      gpll = "git pull";
      gpsh = "git push";
      gpwd =
        "git status &>/dev/null; and python -c 'import sys;from pathlib import Path;print(Path(sys.argv[2]).relative_to(Path(sys.argv[1])))' (git rev-parse --show-toplevel) (pwd)";
      grb = "git rebase";
      grbi =
        "git rebase -i (git merge-base HEAD (git symbolic-ref --short refs/remotes/origin/HEAD | cut -d '/' -f2))";
      grbm =
        "git rebase (git symbolic-ref --short refs/remotes/origin/HEAD | cut -d '/' -f2)";
      grlg = "git reflog";
      grm = "git rm";
      grmt = "git remote";
      grst = "git reset";
      grsto = "git restore";
      grt = ''
        git rev-parse --show-toplevel &>/dev/null; and cd (git rev-parse --show-toplevel) or echo "Not in a git repo"'';
      grv = "git revert";
      gsbtr = "git subtree";
      gshow = "git show";
      gst = "git status";
      gstsh = "git stash";
      gsw = "git switch";
      gtag = "git tag";
      gtch = ''
        GIT_COMMITTER_DATE="(date)" git commit --amend --no-edit --date "(date)"'';
      gupd = "git fetch origin main:main; and git rebase main";
      gwhich = "git branch --show";
      gwt = "git worktree";
    };
    shellAbbrs = {
      csv2json =
        "python -c 'import csv, json, sys; print(json.dumps([dict(r) for r in csv.DictReader(sys.stdin)]))'";
    };
    shellInit = ''
      set -gx DOTFILES "$HOME/Dotfiles"
      set -gx MANPAGER "nvim +Man!"
      set -U fish_prompt_prefix (hostname)
    '';
    interactiveShellInit = ''
      function change_directory
          if test -d .git
              set -f _is_git_repo true
          else
              begin
                set -l info (command git rev-parse --git-dir --is-bare-repository 2>/dev/null)
                if set -q info[2]; and test $info[2] = false
                    set -f _is_git_repo true
                else
                    set -f _is_git_repo false
                end
              end
          end
          if test $_is_git_repo = true
            set -f root (git rev-parse --show-toplevel)
          else
            set -f root (pwd)
          end
          cd (cat (echo $root | psub) (fd . --type d $root | psub) | fzf; or echo '.')
      end

      fish_user_key_bindings
      bind \cs change_directory
      function fish_greeting
        fish_prompt
      end
    '';
  };
}
