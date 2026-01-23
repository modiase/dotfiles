{ pkgs, ... }:

let
  secrets = pkgs.callPackage ../nixpkgs/secrets { };
  ntfy-me = pkgs.callPackage ../nixpkgs/ntfy-me { inherit secrets; };
in
{
  nixpkgs.config.allowUnfree = true;

  home.packages = with pkgs; [
    colima
    coreutils-prefixed
    iproute2mac
    gettext
    gnupg
    zstd
  ];

  home.file.".local/bin/bash" = {
    source = "${pkgs.bash}/bin/bash";
  };

  home.file.".hammerspoon/init.lua".text = ''
    hs.hotkey.bind({"cmd", "shift"}, "b", function() hs.application.launchOrFocus("Google Chrome") end)
    hs.hotkey.bind({"cmd", "shift"}, "d", function() hs.application.launchOrFocus("Notion") end)
    hs.hotkey.bind({"cmd", "shift"}, "q", function() hs.application.launchOrFocus("Google Gemini") end)
    hs.hotkey.bind({"cmd", "shift"}, "k", function() hs.application.launchOrFocus("Google Calendar") end)
    hs.hotkey.bind({"cmd", "shift"}, "l", function() hs.application.launchOrFocus("Todoist") end)
    hs.hotkey.bind({"cmd", "shift"}, "t", function() hs.application.launchOrFocus("Ghostty") end)
    hs.hotkey.bind({"cmd", "shift"}, "u", function() hs.application.launchOrFocus("Apple Music") end)
  '';

  launchd.agents.ntfy-listen = {
    enable = true;
    config = {
      ProgramArguments = [ "${ntfy-me}/bin/ntfy-listen" ];
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "/tmp/ntfy-listen.log";
      StandardErrorPath = "/tmp/ntfy-listen.err";
    };
  };
}
