{ config, pkgs, ... }:

let
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
          fg = "#a8d8ea";
        };
        hovered = {
          reversed = true;
        };
        preview_hovered = {
          underline = true;
        };
        find_keyword = {
          fg = "#d8d0b8";
          bold = true;
        };
        find_position = {
          fg = "#f4b6c2";
          bg = "reset";
          bold = true;
        };
        marker_copied = {
          fg = "#a8c99a";
          bg = "#a8c99a";
        };
        marker_cut = {
          fg = "#d08080";
          bg = "#d08080";
        };
        marker_marked = {
          fg = "#a8d8ea";
          bg = "#a8d8ea";
        };
        marker_selected = {
          fg = "#d8d0b8";
          bg = "#d8d0b8";
        };
        tab_active = {
          fg = "#1c1c1c";
          bg = "#a8d8ea";
        };
        tab_inactive = {
          fg = "#e0e0e0";
          bg = "#3a3a3a";
        };
        count_copied = {
          fg = "#1c1c1c";
          bg = "#a8c99a";
        };
        count_cut = {
          fg = "#1c1c1c";
          bg = "#d08080";
        };
        count_selected = {
          fg = "#1c1c1c";
          bg = "#d8d0b8";
        };
        border_symbol = "│";
        border_style = {
          fg = "#3a3a3a";
        };
      };
      status = {
        separator_open = "";
        separator_close = "";
        separator_style = {
          fg = "#3a3a3a";
          bg = "#3a3a3a";
        };
        mode_normal = {
          fg = "#1c1c1c";
          bg = "#8fa8c9";
          bold = true;
        };
        mode_select = {
          fg = "#1c1c1c";
          bg = "#f4b6c2";
          bold = true;
        };
        mode_unset = {
          fg = "#1c1c1c";
          bg = "#d08080";
          bold = true;
        };
        progress_label = {
          fg = "#e0e0e0";
          bold = true;
        };
        progress_normal = {
          fg = "#8fa8c9";
          bg = "#3a3a3a";
        };
        progress_error = {
          fg = "#d08080";
          bg = "#3a3a3a";
        };
        perm_type = {
          fg = "#8fa8c9";
        };
        perm_read = {
          fg = "#d8d0b8";
        };
        perm_write = {
          fg = "#d08080";
        };
        perm_exec = {
          fg = "#a8c99a";
        };
        perm_sep = {
          fg = "#707070";
        };
      };
      select = {
        border = {
          fg = "#8fa8c9";
        };
        active = {
          fg = "#f4b6c2";
          bold = true;
        };
        inactive = { };
      };
      input = {
        border = {
          fg = "#8fa8c9";
        };
        title = { };
        value = { };
        selected = {
          reversed = true;
        };
      };
      completion = {
        border = {
          fg = "#8fa8c9";
        };
        active = {
          reversed = true;
        };
        inactive = { };
      };
      tasks = {
        border = {
          fg = "#8fa8c9";
        };
        title = { };
        hovered = {
          fg = "#f4b6c2";
          underline = true;
        };
      };
      which = {
        mask = {
          bg = "#2a2a2a";
        };
        cand = {
          fg = "#a8d8ea";
        };
        rest = {
          fg = "#707070";
        };
        desc = {
          fg = "#c9a8c9";
        };
        separator = "  ";
        separator_style = {
          fg = "#3a3a3a";
        };
      };
      help = {
        on = {
          fg = "#a8d8ea";
        };
        run = {
          fg = "#c9a8c9";
        };
        hovered = {
          reversed = true;
          bold = true;
        };
        footer = {
          fg = "#707070";
        };
      };
      notify = {
        title_info = {
          fg = "#a8d8ea";
        };
        title_warn = {
          fg = "#d8d0b8";
        };
        title_error = {
          fg = "#d08080";
        };
      };
      filetype = {
        rules = [
          {
            mime = "image/*";
            fg = "#d8d0b8";
          }
          {
            mime = "{audio,video}/*";
            fg = "#c9a8c9";
          }
          {
            mime = "application/{,g}zip";
            fg = "#d08080";
          }
          {
            mime = "application/x-{tar,bzip*,7z-compressed,xz,rar}";
            fg = "#d08080";
          }
          {
            mime = "application/{pdf,doc,rtf,vnd.*}";
            fg = "#a8d8ea";
          }
          {
            name = "*";
            is = "orphan";
            fg = "#d08080";
          }
          {
            name = "*";
            is = "exec";
            fg = "#a8c99a";
          }
          {
            name = "*/";
            fg = "#8fa8c9";
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
          1
          2
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
