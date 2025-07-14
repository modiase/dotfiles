{ pkgs, ... }:

{
  programs.bash = {
    enable = true;
    initExtra =
      ''
        if [ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
          . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
        fi
        if [ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
          . "$HOME/.nix-profile/etc/profile.d/nix.sh"
        fi
      ''
      + (
        if !pkgs.stdenv.isDarwin then
          ''
            if [[ $- == *i* && -z "$NO_FISH" && -z "$IN_NIX_SHELL" && -z "$NIX_BUILD_CORES" && -z "$__structuredAttrs" ]] && \
               type fish > /dev/null 2>&1 && \
               ! ps -o comm= -p $PPID 2>/dev/null | grep -q "nix"; then
              exec fish
            fi
          ''
        else
          ""
      );
  };
}
