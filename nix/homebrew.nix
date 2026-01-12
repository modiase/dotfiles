{
  homebrew = {
    # Homebrew doesn't support macOS 26.2 yet
    enable = false;
    onActivation.cleanup = "none";
    casks = [
      "font-hack-nerd-font"
      "font-iosevka-nerd-font"
      "ghostty"
      "hammerspoon"
    ];
  };
}
