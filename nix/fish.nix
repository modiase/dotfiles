{
  pkgs,
  lib,
  ...
}:
let
  colors = import ./colors.nix;
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
  ezaOrLs = cmd: fallback: ''
    if command -q eza
        if command -q moor
            ${cmd} | moor
        else
            ${cmd}
        end
    else
        ${fallback}
    end
  '';
  functions =
    pkgs.lib.genAttrs (map toFunctionName functionFiles) (
      name: builtins.readFile (dotfiles + /fish/functions + "/${name}.fish")
    )
    // {
      ls = ezaOrLs "${ezaBase} --git $argv" "command ls --color=auto $argv";
      ll = ezaOrLs "${ezaBase} -l --git $argv" "command ls -lh --color=auto $argv";
      lt = ezaOrLs "${ezaBase} --tree $argv" "command ls -R --color=auto $argv";
      df = "command -q duf; and duf $argv; or command df -h $argv";
      du = "command -q dust; and dust $argv; or command du -sh $argv";
      ps = "command -q procs; and procs $argv; or command ps $argv";
      top = "command -q btop; and btop $argv; or command top $argv";
      cd = ''
        if test (count $argv) -gt 0
            builtin cd $argv
            return
        end
        if not command -q yazi
            builtin cd
            return
        end
        set -l tmp (mktemp -t "yazi-cwd.XXXXXX")
        yazi --cwd-file="$tmp"
        if set -l cwd (command cat -- "$tmp"); and test -n "$cwd"; and test "$cwd" != "$PWD"
            builtin cd -- "$cwd"
        end
        rm -f -- "$tmp"
      '';
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
    plugins = [
      {
        name = "fzf.fish";
        src = pkgs.fishPlugins.fzf-fish.src;
      }
      {
        name = "bass";
        src = pkgs.fishPlugins.bass.src;
      }
    ];
    shellAbbrs = {
      csv2json = "python -c 'import csv, json, sys; print(json.dumps([dict(r) for r in csv.DictReader(sys.stdin)]))'";
    };
    shellInit = ''
      fish_add_path -gP ~/.nix-profile/bin
      if test -z "$DISPLAY"
          set -l hm_display ( "${displayResolver}" ); or set -l hm_display ""
          if test -n "$hm_display"
              set -gx DISPLAY $hm_display
          end
          set -e hm_display
      end
      set -gx DOTFILES "$HOME/dotfiles"
      set -gx MANPAGER 'nvim -M --cmd "let g:pager_mode=1" +Man! -c "set nonumber norelativenumber wrap linebreak" -c "nnoremap <buffer> q :q<CR>"'
      set -gx MOOR "--no-linenumbers --no-statusbar --quit-if-one-screen -terminal-fg -style gruvbox"
      set -gx FZF_DEFAULT_OPTS "--color=fg:#${colors.foreground},bg:-1,hl:#${colors.base16.base0C},fg+:#${colors.base16.base06},bg+:#${colors.selection},hl+:#b8e8f0,info:#${colors.base16.base0D},prompt:#${colors.base16.base0E},pointer:#${colors.base16.base0C},marker:#${colors.base16.base09},spinner:#${colors.base16.base0E},header:#${colors.base16.base0D}"
      set -q fish_prompt_prefix; or set -U fish_prompt_prefix (set -q hostname_override; and echo $hostname_override; or hostname)
    '';
    interactiveShellInit = ''
      fzf_configure_bindings --directory=\ct --git_log= --git_status=\cg --processes= --variables=\co

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
