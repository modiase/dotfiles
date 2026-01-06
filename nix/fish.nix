{
  pkgs,
  lib,
  ...
}:
let
  dotfiles = ../.;
  functionFiles = builtins.attrNames (builtins.readDir (dotfiles + /fish/functions));
  toFunctionName = file: pkgs.lib.strings.removeSuffix ".fish" file;
  displayResolver = pkgs.writeShellScript "resolve-display" ''
    if [ "$(uname -s)" != "Darwin" ]; then exit 0; fi
    if ! command -v launchctl >/dev/null 2>&1; then exit 0; fi
    display="$(launchctl getenv DISPLAY 2>/dev/null)"
    if [ -z "$display" ]; then
      display="$(launchctl print gui/$(id -u) 2>/dev/null | sed -n 's/.*DISPLAY => //p' | tail -n 1)"
    fi
    [ -n "$display" ] && printf '%s\n' "$display"
  '';
  ezaBase = "eza --icons=always --color=always";
  moorFlags = "moor --no-linenumbers --no-statusbar --quit-if-one-screen -terminal-fg";
  functions =
    pkgs.lib.genAttrs (map toFunctionName functionFiles) (
      name: builtins.readFile (dotfiles + /fish/functions + "/${name}.fish")
    )
    // {
      ls = "${ezaBase} --git $argv | ${moorFlags}";
      ll = "${ezaBase} -l --git $argv | ${moorFlags}";
      lt = "${ezaBase} --tree  $argv | ${moorFlags}";
    }
    // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
      pbcopy = ''
        set -l data (cat | base64 -w0)
        printf '\e]52;c;%s\a' $data
      '';
    };
in
{
  programs.fish = {
    enable = true;
    inherit functions;
    shellAliases = {
      cat = "bat";
      df = "duf";
      du = "dust";
      icat = "chafa";
      ps = "procs";
      top = "btop";
    };
    shellAbbrs = {
      csv2json = "python -c 'import csv, json, sys; print(json.dumps([dict(r) for r in csv.DictReader(sys.stdin)]))'";
    };
    shellInit = ''
      if test -z "$DISPLAY"
          set -l hm_display ( "${displayResolver}" ); or set -l hm_display ""
          if test -n "$hm_display"
              set -gx DISPLAY $hm_display
          end
          set -e hm_display
      end
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
