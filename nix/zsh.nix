{ pkgs, ... }:

{
  programs.zsh = {
    enable = true;
    profileExtra = ''
      if [ -n "$ZSH_VERSION" ]; then
        source ~/.zshrc
      fi
    '';
    initContent =
      ''
        if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
          . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
        fi
        if [ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
          . "$HOME/.nix-profile/etc/profile.d/nix.sh"
        fi
      ''
      + (
        if pkgs.stdenv.isDarwin then
          ''
            in_nix_process() {
                local pid=$PPID
                while [ $pid -ne 1 ]; do
                    local comm=$(ps -o comm= -p $pid 2>/dev/null)
                    if [[ "$comm" == *nix* ]] || [[ "$comm" == *"nix-daemon"* ]]; then
                        return 0
                    fi
                    pid=$(ps -o ppid= -p $pid 2>/dev/null | tr -d ' ')
                    [ -z "$pid" ] && break
                done
                return 1
            }

            if [[ $- == *i* && -z "$NO_FISH" && -z "$IN_NIX_SHELL" && -z "$NIX_BUILD_CORES" && -z "$__structuredAttrs" ]] && \
               type fish > /dev/null 2>&1 && \
               ! in_nix_process; then
               exec fish
            fi
          ''
        else
          ""
      );
  };
}
