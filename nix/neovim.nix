{
  config,
  lib,
  pkgs,
  ...
}:

let
  colors = import ./colors.nix;
  devlogsLib = pkgs.callPackage ./nixpkgs/devlogs-lib { };
  cfg = config.dotfiles.neovim;
  corePlugins = [
    # keep-sorted start
    "base16"
    "neoscroll"
    "noice"
    "nvim-notify"
    "nvim-web-devicons"
    "tmux"
    "treesitter"
    # keep-sorted end
  ];
in
{
  options.dotfiles.neovim.plugins = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [
      # keep-sorted start
      "airline"
      "blamer"
      "buffer-management"
      "centerpad"
      "claudecode"
      "coc"
      "copy-path"
      "diffview"
      "fidget"
      "flash"
      "gitsigns"
      "image"
      "neogit"
      "opencode"
      "persistence"
      "pick-buffer"
      "pick-path"
      "render-markdown"
      "telescope"
      "vim-bbye"
      "vim-svelte"
      "which-key"
      "winresize"
      "yazi"
      # keep-sorted end
    ];
    description = "Neovim plugin specs to load (filenames without .lua extension).";
  };

  config = lib.mkIf config.programs.neovim.enable {
    programs.neovim.extraPackages = [ pkgs.tree-sitter ];

    xdg.configFile."nvim/lua/enabled-plugins.lua".text =
      let
        allPlugins = lib.sort lib.lessThan (lib.unique (corePlugins ++ cfg.plugins));
        entries = map (p: ''["${p}"] = true'') allPlugins;
      in
      "return {\n  ${lib.concatStringsSep ",\n  " entries},\n}\n";

    xdg.configFile."nvim/lua/devlogs.lua".source = "${devlogsLib.lua}/lua/devlogs.lua";

    xdg.configFile."nvim/lua/colors.lua".text = ''
      return {
        background = "#${colors.background}",
        foreground = "#${colors.foreground}",
        foregroundDim = "#${colors.foregroundDim}",
        foregroundMuted = "#${colors.foregroundMuted}",
        cursor = "#${colors.cursor}",
        cursorText = "#${colors.cursorText}",
        selection = "#${colors.selection}",

        diffAdd = "#${colors.diffAdd}",
        diffChange = "#${colors.diffChange}",
        diffText = "#${colors.diffText}",
        diffDelete = "#${colors.diffDelete}",

        base00 = "#${colors.base16.base00}",
        base01 = "#${colors.base16.base01}",
        base02 = "#${colors.base16.base02}",
        base03 = "#${colors.base16.base03}",
        base04 = "#${colors.base16.base04}",
        base05 = "#${colors.base16.base05}",
        base06 = "#${colors.base16.base06}",
        base07 = "#${colors.base16.base07}",
        base08 = "#${colors.base16.base08}",
        base09 = "#${colors.base16.base09}",
        base0A = "#${colors.base16.base0A}",
        base0B = "#${colors.base16.base0B}",
        base0C = "#${colors.base16.base0C}",
        base0D = "#${colors.base16.base0D}",
        base0E = "#${colors.base16.base0E}",
        base0F = "#${colors.base16.base0F}",
      }
    '';
  };
}
