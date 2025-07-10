{ pkgs, ... }:

{
  programs.zsh = {
    enable = true;
    initContent = ''
      if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
        . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
      fi
      if [ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
        . "$HOME/.nix-profile/etc/profile.d/nix.sh"
      fi
    '' + (if pkgs.stdenv.isDarwin then ''
      if [[ $- == *i* && -z "$IN_NIX_SHELL" && -z "$NO_FISH" ]] && type fish > /dev/null 2>&1; then
        exec fish
      fi
    '' else
      "");
  };
}
