{ homebrew-core, homebrew-cask, ... }:

{
  nix-homebrew = {
    enable = true;
    enableRosetta = true;
    user = "moye";
    autoMigrate = true;
    mutableTaps = false;
    taps = {
      "homebrew/homebrew-core" = homebrew-core;
      "homebrew/homebrew-cask" = homebrew-cask;
    };
  };

  homebrew = {
    enable = true;
    onActivation.cleanup = "none";
    taps = [
      "homebrew/homebrew-core"
      "homebrew/homebrew-cask"
    ];
    brews = [
      "container"
    ];
    casks = [
      "font-hack-nerd-font"
      "font-iosevka-nerd-font"
      "ghostty"
      "hammerspoon"
      "homerow"
    ];
  };
}
