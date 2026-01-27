{ homebrew-core, homebrew-cask, ... }:

{
  nix-homebrew = {
    enable = true;
    enableRosetta = false;
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
    onActivation.cleanup = "zap";
    taps = [
      "homebrew/homebrew-core"
      "homebrew/homebrew-cask"
    ];
    brews = [
      "container"
      "terminal-notifier"
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
