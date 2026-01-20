{ config, pkgs, ... }:

{
  programs.yazi = {
    enable = true;
    settings = {
      opener = {
        edit = [
          {
            run = ''nvim "$@"'';
            block = true;
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
