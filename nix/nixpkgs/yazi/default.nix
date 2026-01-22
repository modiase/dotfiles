{ config, pkgs, ... }:

let
  yaziNvimOpen = pkgs.writeShellScript "yazi-nvim-open" (builtins.readFile ./yazi-nvim-open.sh);
in
{
  programs.yazi = {
    enable = true;
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
            run = ''${yaziNvimOpen} "$@"'';
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
  };
}
