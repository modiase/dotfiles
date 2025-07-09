{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    yabai
  ];

  home.file.".config/yabai/yabairc".text = ''
    #!/usr/bin/env sh

    sudo yabai --load-sa
    yabai -m signal --add event=dock_did_restart action="sudo yabai --load-sa"

    yabai -m config layout bsp
    yabai -m config window_placement second_child
    
    yabai -m config top_padding 10
    yabai -m config bottom_padding 10
    yabai -m config left_padding 10
    yabai -m config right_padding 10
    yabai -m config window_gap 10
    
    yabai -m config window_border on
    yabai -m config window_border_width 2
    yabai -m config active_window_border_color 0xff775759
    yabai -m config normal_window_border_color 0xff554444
    yabai -m config insert_feedback_color 0xffd75f5f
    
    yabai -m config split_ratio 0.50
    yabai -m config auto_balance off
    yabai -m config mouse_follows_focus on
    yabai -m config focus_follows_mouse autofocus
    yabai -m config mouse_action1 move
    yabai -m config mouse_action2 resize
    yabai -m config mouse_drop_action swap
  '';
  
  home.file.".config/yabai/yabairc".executable = true;
}
