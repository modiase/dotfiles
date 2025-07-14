{ pkgs, ... }:

let
  execFish = ''
    in_nix_environment() {
       [[ -n "$IN_NIX_SHELL" ]] && return 0
       [[ -n "$NIX_BUILD_CORES" ]] && return 0
       [[ -n "$__structuredAttrs" ]] && return 0
       [[ -n "$NIX_SHELL" ]] && return 0
       [[ -n "$NIX_PATH" ]] && return 0
       [[ -n "$NIX_PROFILES" ]] && return 0
       [[ -n "$NIX_CC" ]] && return 0
       [[ -n "$NIX_BINTOOLS" ]] && return 0
       [[ -n "$NIX_BUILD_TOP" ]] && return 0
       [[ -n "$NIX_STORE" ]] && return 0
       [[ -n "$__NIX_DARWIN_SET_ENVIRONMENT_DONE" ]] && return 0
       
       if [[ -n "$PWD" && "$PWD" == /nix/store/* ]]; then
           return 0
       fi
       
       if [[ -n "$PATH" ]] && echo "$PATH" | grep -q "/nix/store" 2>/dev/null; then
           return 0
       fi
       
       if command -v env >/dev/null 2>&1; then
           if env 2>/dev/null | grep -q "^nix_" 2>/dev/null; then
               return 0
           fi
           if env 2>/dev/null | grep -q "^NIX_" 2>/dev/null; then
               return 0
           fi
       fi
       
       if [[ -n "$PS1" ]]; then
           [[ "$PS1" == *"nix-shell"* ]] && return 0
           [[ "$PS1" == *"impure"* ]] && return 0
       fi
       
       if command -v ps >/dev/null 2>&1 && [[ -n "$PPID" ]]; then
           local pid=$PPID
           local depth=0
           while [[ $pid -ne 1 && $depth -lt 5 ]]; do
               local comm
               local args
               
               if comm=$(ps -o comm= -p $pid 2>/dev/null) && [[ -n "$comm" ]]; then
                   [[ "$comm" == *nix* ]] && return 0
                   [[ "$comm" == *"nix-daemon"* ]] && return 0
               fi
               
               if args=$(ps -o args= -p $pid 2>/dev/null) && [[ -n "$args" ]]; then
                   [[ "$args" == *"nix develop"* ]] && return 0
                   [[ "$args" == *"nix-shell"* ]] && return 0
                   [[ "$args" == *"nix shell"* ]] && return 0
               fi
               
               if pid=$(ps -o ppid= -p $pid 2>/dev/null) && [[ -n "$pid" ]]; then
                   pid=$(echo "$pid" | tr -d ' ')
                   [[ -z "$pid" || "$pid" == "0" ]] && break
               else
                   break
               fi
               ((depth++))
           done
       fi
       
       if command -v nix >/dev/null 2>&1; then
           if [[ -f "flake.nix" ]] && [[ -n "$NIX_CC" ]]; then
               local expected_output
               if expected_output=$(nix print-dev-env --json 2>/dev/null) && [[ -n "$expected_output" ]]; then
                   if echo "$expected_output" | grep -q "NIX_CC" 2>/dev/null; then
                       local expected_cc
                       if expected_cc=$(echo "$expected_output" | grep -o '"NIX_CC"[^}]*"value":"[^"]*"' 2>/dev/null | sed 's/.*"value":"\([^"]*\)".*/\1/' 2>/dev/null) && [[ -n "$expected_cc" ]]; then
                           [[ "$NIX_CC" == "$expected_cc" ]] && return 0
                       fi
                   fi
               fi
           fi
       fi
       
       return 1
    }

    if [[ $- == *i* && -z "$NO_FISH" ]] && \
      type fish > /dev/null 2>&1 && \
      ! in_nix_environment; then
       exec fish
    fi
  '';

  nixInit = ''
    if [ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
      . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
    fi
    if [ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
      . "$HOME/.nix-profile/etc/profile.d/nix.sh"
    fi
  '';

in
{
  programs = {
    bash = {
      enable = true;
      initExtra = nixInit + execFish;
    };

    zsh = {
      enable = true;
      profileExtra = ''
        if [ -n "$ZSH_VERSION" ]; then
          source ~/.zshrc
        fi
      '';
      initContent = nixInit + execFish;
    };
  };
}
