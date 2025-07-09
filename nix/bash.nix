{ pkgs, ... }:

{
  programs.bash = {
    enable = true;
    profileExtra = if !pkgs.stdenv.isDarwin then ''
      if [ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
        . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
      fi
    '' else "";
    initExtra = if !pkgs.stdenv.isDarwin then ''
      if [[ $- == *i* && -z "$IN_NIX_SHELL" && -z "$NO_FISH" ]] && type fish > /dev/null 2>&1; then
        exec fish
      fi
    '' else "";
  };
}
