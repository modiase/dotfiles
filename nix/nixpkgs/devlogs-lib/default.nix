{ writeTextFile }:
let
  shell = writeTextFile {
    name = "devlogs-shell";
    destination = "/lib/devlogs.sh";
    text = builtins.readFile ./devlogs.sh;
  };
  python = writeTextFile {
    name = "devlogs-python";
    destination = "/lib/devlogs.py";
    text = builtins.readFile ./devlogs.py;
  };
  lua = writeTextFile {
    name = "devlogs-lua";
    destination = "/lua/devlogs.lua";
    text = builtins.readFile ./devlogs.lua;
  };
  typescript = writeTextFile {
    name = "devlogs-typescript";
    destination = "/lib/devlogs.ts";
    text = builtins.readFile ./devlogs.ts;
  };
in
{
  inherit
    shell
    python
    lua
    typescript
    ;
}
