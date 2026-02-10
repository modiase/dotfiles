{ config, pkgs, ... }:

let
  colors = import ../../colors.nix;
  yaziNvim = pkgs.writeShellScript "yazi-nvim" (builtins.readFile ./yazi-nvim.sh);
  pastelGrayTheme = pkgs.writeText "pastel-gray.tmTheme" (builtins.readFile ./pastel-gray.tmTheme);
in
{
  programs.yazi = {
    enable = true;
    theme = {
      mgr = {
        syntect_theme = "${pastelGrayTheme}";
        cwd = {
          fg = "#${colors.base16.base0C}";
        };
        hovered = {
          reversed = true;
        };
        preview_hovered = {
          underline = true;
        };
        find_keyword = {
          fg = "#${colors.base16.base0B}";
          bold = true;
        };
        find_position = {
          fg = "#${colors.base16.base0A}";
          bg = "reset";
          bold = true;
        };
        marker_copied = {
          fg = "#${colors.base16.base09}";
          bg = "#${colors.base16.base09}";
        };
        marker_cut = {
          fg = "#${colors.base16.base08}";
          bg = "#${colors.base16.base08}";
        };
        marker_marked = {
          fg = "#${colors.base16.base0C}";
          bg = "#${colors.base16.base0C}";
        };
        marker_selected = {
          fg = "#${colors.base16.base0B}";
          bg = "#${colors.base16.base0B}";
        };
        tab_active = {
          fg = "#${colors.background}";
          bg = "#${colors.base16.base0C}";
        };
        tab_inactive = {
          fg = "#${colors.foreground}";
          bg = "#${colors.selection}";
        };
        count_copied = {
          fg = "#${colors.background}";
          bg = "#${colors.base16.base09}";
        };
        count_cut = {
          fg = "#${colors.background}";
          bg = "#${colors.base16.base08}";
        };
        count_selected = {
          fg = "#${colors.background}";
          bg = "#${colors.base16.base0B}";
        };
        border_symbol = "│";
        border_style = {
          fg = "#${colors.selection}";
        };
      };
      status = {
        separator_open = "";
        separator_close = "";
        separator_style = {
          fg = "#${colors.selection}";
          bg = "#${colors.selection}";
        };
        mode_normal = {
          fg = "#${colors.background}";
          bg = "#${colors.base16.base0D}";
          bold = true;
        };
        mode_select = {
          fg = "#${colors.background}";
          bg = "#${colors.base16.base0A}";
          bold = true;
        };
        mode_unset = {
          fg = "#${colors.background}";
          bg = "#${colors.base16.base08}";
          bold = true;
        };
        progress_label = {
          fg = "#${colors.foreground}";
          bold = true;
        };
        progress_normal = {
          fg = "#${colors.base16.base0D}";
          bg = "#${colors.selection}";
        };
        progress_error = {
          fg = "#${colors.base16.base08}";
          bg = "#${colors.selection}";
        };
        perm_type = {
          fg = "#${colors.base16.base0D}";
        };
        perm_read = {
          fg = "#${colors.base16.base0B}";
        };
        perm_write = {
          fg = "#${colors.base16.base08}";
        };
        perm_exec = {
          fg = "#${colors.base16.base09}";
        };
        perm_sep = {
          fg = "#${colors.foregroundDim}";
        };
      };
      select = {
        border = {
          fg = "#${colors.base16.base0D}";
        };
        active = {
          fg = "#${colors.base16.base0A}";
          bold = true;
        };
        inactive = { };
      };
      input = {
        border = {
          fg = "#${colors.base16.base0D}";
        };
        title = { };
        value = { };
        selected = {
          reversed = true;
        };
      };
      completion = {
        border = {
          fg = "#${colors.base16.base0D}";
        };
        active = {
          reversed = true;
        };
        inactive = { };
      };
      tasks = {
        border = {
          fg = "#${colors.base16.base0D}";
        };
        title = { };
        hovered = {
          fg = "#${colors.base16.base0A}";
          underline = true;
        };
      };
      which = {
        mask = {
          bg = "#${colors.base16.base01}";
        };
        cand = {
          fg = "#${colors.base16.base0C}";
        };
        rest = {
          fg = "#${colors.foregroundDim}";
        };
        desc = {
          fg = "#${colors.base16.base0E}";
        };
        separator = "  ";
        separator_style = {
          fg = "#${colors.selection}";
        };
      };
      help = {
        on = {
          fg = "#${colors.base16.base0C}";
        };
        run = {
          fg = "#${colors.base16.base0E}";
        };
        hovered = {
          reversed = true;
          bold = true;
        };
        footer = {
          fg = "#${colors.foregroundDim}";
        };
      };
      notify = {
        title_info = {
          fg = "#${colors.base16.base0C}";
        };
        title_warn = {
          fg = "#${colors.base16.base0B}";
        };
        title_error = {
          fg = "#${colors.base16.base08}";
        };
      };
      icon = {
        prepend_conds = [
          {
            "if" = "dir";
            text = "󰉖";
            fg = "#${colors.base16.base0B}";
          }
        ];
      };
      filetype = {
        rules = [
          {
            mime = "image/*";
            fg = "#${colors.base16.base0B}";
          }
          {
            mime = "{audio,video}/*";
            fg = "#${colors.base16.base0E}";
          }
          {
            mime = "application/{,g}zip";
            fg = "#${colors.base16.base08}";
          }
          {
            mime = "application/x-{tar,bzip*,7z-compressed,xz,rar}";
            fg = "#${colors.base16.base08}";
          }
          {
            mime = "application/{pdf,doc,rtf,vnd.*}";
            fg = "#${colors.base16.base0C}";
          }
          {
            name = "*";
            is = "orphan";
            fg = "#${colors.base16.base08}";
          }
          {
            name = "*";
            is = "exec";
            fg = "#${colors.base16.base09}";
          }
          {
            name = "*/";
            fg = "#${colors.base16.base0B}";
            bold = true;
          }
        ];
      };
    };
    initLua = ''
      -- Remove statusbar
      local old_layout = Tab.layout
      Status.redraw = function() return {} end
      Tab.layout = function(self, ...)
        self._area = ui.Rect { x = self._area.x, y = self._area.y, w = self._area.w, h = self._area.h + 1 }
        return old_layout(self, ...)
      end
    '';
    settings = {
      mgr = {
        ratio = [
          0
          1
          4
        ];
      };
      opener = {
        edit = [
          {
            run = ''${yaziNvim} open "$@"'';
            block = false;
            for = "unix";
          }
        ];
      };
      open = {
        rules = [
          {
            mime = "text/*";
            use = "edit";
          }
          {
            mime = "application/json";
            use = "edit";
          }
          {
            mime = "application/x-ndjson";
            use = "edit";
          }
          {
            mime = "application/*javascript*";
            use = "edit";
          }
          {
            mime = "application/*typescript*";
            use = "edit";
          }
          {
            mime = "application/x-sh";
            use = "edit";
          }
          {
            mime = "application/toml";
            use = "edit";
          }
          {
            mime = "application/x-yaml";
            use = "edit";
          }
          {
            mime = "application/xml";
            use = "edit";
          }
          {
            name = "*.md";
            use = "edit";
          }
          {
            name = "*.nix";
            use = "edit";
          }
          {
            name = "*.lua";
            use = "edit";
          }
          {
            name = "*.fish";
            use = "edit";
          }
          {
            name = "*.conf";
            use = "edit";
          }
          {
            name = "*";
            use = "open";
          }
        ];
      };
    };
    keymap = {
      mgr.prepend_keymap = [
        {
          on = [
            "g"
            "n"
          ];
          run = ''shell '${yaziNvim} cd "$1"' '';
          desc = "cd neovim to hovered dir";
        }
        {
          on = [
            "g"
            "s"
          ];
          run = ''shell '${yaziNvim} split "$1"' '';
          desc = "open in nvim horizontal split";
        }
        {
          on = [
            "g"
            "v"
          ];
          run = ''shell '${yaziNvim} vsplit "$1"' '';
          desc = "open in nvim vertical split";
        }
      ];
    };
  };
}
