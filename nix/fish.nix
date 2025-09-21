{ pkgs, ... }:
let
  dotfiles = ../.;
  functionFiles = builtins.attrNames (builtins.readDir (dotfiles + /fish/functions));
  toFunctionName = file: pkgs.lib.strings.removeSuffix ".fish" file;
  functions =
    pkgs.lib.genAttrs (map toFunctionName functionFiles) (
      name: builtins.readFile (dotfiles + /fish/functions + "/${name}.fish")
    )
    // {
      ls = "eza --icons=always --color=always --git $argv | moar --no-linenumbers --no-statusbar --quit-if-one-screen";
      ll = "eza --icons=always --color=always -l --git $argv | moar --no-linenumbers --no-statusbar --quit-if-one-screen";
      lt = "eza --icons=always --color=always --tree  $argv | moar --no-linenumbers --no-statusbar --quit-if-one-screen";
    };
in
{
  programs.fish = {
    enable = true;
    functions = functions;
    shellAliases = {
      cat = "bat";
      du = "dust";
      ps = "procs";
      top = "btop";
    };
    shellAbbrs = {
      csv2json = "python -c 'import csv, json, sys; print(json.dumps([dict(r) for r in csv.DictReader(sys.stdin)]))'";
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
        echo -n (hostname)
        echo -n " "
        echo -n (set_color d8dee9)">"
        echo -n (set_color d8dee9)">"
        echo -n (set_color 88c0d0)">"
        echo -n (set_color normal)" "
      end

      functions -q gbr && complete -c 'gbr' -w 'git branch'
      functions -q gco && complete -c 'gco' -w 'git checkout'
      functions -q gfch && complete -c 'gfch' -w 'git fetch'
      functions -q gadd && complete -c 'gadd' -w 'git add'
      functions -q gmrg && complete -c 'gmrg' -w 'git merge'
      functions -q grb && complete -c 'grb' -w 'git rebase'
      functions -q grst && complete -c 'grst' -w 'git reset'
      functions -q gsw && complete -c 'gsw' -w 'git switch'
      functions -q gtag && complete -c 'gtag' -w 'git tag'

      if test -f $HOME/.config/fish/config.local.fish
          source $HOME/.config/fish/config.local.fish
      end
    '';
  };
}
