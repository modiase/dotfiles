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
  functions =
    pkgs.lib.genAttrs (map toFunctionName functionFiles) (
      name: builtins.readFile (dotfiles + /fish/functions + "/${name}.fish")
    )
    // {
      ls = "${ezaBase} --git $argv | moor";
      ll = "${ezaBase} -l --git $argv | moor";
      lt = "${ezaBase} --tree $argv | moor";
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
    shellAliases = {
      df = "duf";
      du = "dust";
      ps = "procs";
      top = "btop";
    };
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
      set -gx MANPAGER "nvim +Man!"
      set -gx MOOR "--no-linenumbers --no-statusbar --quit-if-one-screen -terminal-fg -style nord"
      set -gx FZF_DEFAULT_OPTS "--color=fg:#c0c5ce,bg:#14161c,hl:#88c0d0,fg+:#e5e9f0,bg+:#3b4252,hl+:#8fbcbb,info:#81a1c1,prompt:#b48ead,pointer:#88c0d0,marker:#608060,spinner:#b48ead,header:#81a1c1"
      set -q fish_prompt_prefix; or set -U fish_prompt_prefix (set -q hostname_override; and echo $hostname_override; or hostname)
    '';
    interactiveShellInit = ''
      fzf_configure_bindings --directory=\ct --git_log= --git_status=\cg --processes= --variables=\co

      fish_user_key_bindings
      bind \cs cd
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
