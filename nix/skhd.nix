{ config, pkgs, ... }:

{
  home.packages = with pkgs; [ skhd ];

  home.file.".config/skhd/skhdrc".text = ''
    cmd + shift - b : open -a "Google Chrome"
    cmd + shift - t : open -a "Ghostty"
    cmd + shift - c : open -a "Cursor"
    cmd + shift - d : open ~/Downloads/

    # change window focus within space
    alt - j : yabai -m window --focus south
    alt - k : yabai -m window --focus north
    alt - h : yabai -m window --focus west
    alt - l : yabai -m window --focus east
    alt - s : yabai -m display --focus west
    alt - g : yabai -m display --focus east

    # spaces
    alt - n : yabai -m space --create
    cmd + alt - w : yabai -m space --destroy

    # swap windows
    shift + alt - j : yabai -m window --swap south
    shift + alt - k : yabai -m window --swap north
    shift + alt - h : yabai -m window --swap west
    shift + alt - l : yabai -m window --swap east

    # rotate layout clockwise
    shift + alt - r : yabai -m space --rotate 270

    # flip along y-axis
    shift + alt - y : yabai -m space --mirror y-axis

    # flip along x-axis
    shift + alt - x : yabai -m space --mirror x-axis

    # toggle window float
    shift + alt - t : yabai -m window --toggle float --grid 4:4:1:1:2:2

    #move window to prev and next space
    shift + alt - p : yabai -m window --space prev;
    shift + alt - n : yabai -m window --space next;

    # move window to space #
    shift + alt - 1 : yabai -m window --space 1;
    shift + alt - 2 : yabai -m window --space 2;
    shift + alt - 3 : yabai -m window --space 3;
    shift + alt - 4 : yabai -m window --space 4;
    shift + alt - 5 : yabai -m window --space 5;
    shift + alt - 6 : yabai -m window --space 6;
    shift + alt - 7 : yabai -m window --space 7;

    # focus monitor
    ctrl + cmd - x  : yabai -m display --focus recent
    ctrl + cmd - z  : yabai -m display --focus prev
    ctrl + cmd - c  : yabai -m display --focus next
    ctrl + cmd - 1  : yabai -m display --focus 1
    ctrl + cmd - 2  : yabai -m display --focus 2
    ctrl + cmd - 3  : yabai -m display --focus 3

    # move window
    shift + ctrl - a : yabai -m window --move rel:-20:0
    shift + ctrl - s : yabai -m window --move rel:0:20
    shift + ctrl - w : yabai -m window --move rel:0:-20
    shift + ctrl - d : yabai -m window --move rel:20:0

    # increase window size
    shift + alt - a : yabai -m window --resize left:-20:0
    shift + alt - s : yabai -m window --resize bottom:0:20
    shift + alt - w : yabai -m window --resize top:0:-20
    shift + alt - d : yabai -m window --resize right:20:0

    # decrease window size
    shift + cmd - a : yabai -m window --resize left:20:0
    shift + cmd - s : yabai -m window --resize bottom:0:-20
    shift + cmd - w : yabai -m window --resize top:0:20
    shift + cmd - d : yabai -m window --resize right:-20:0

    .load "./skhdrc.local"
  '';
}
