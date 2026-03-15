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
in
{
  inherit shell python lua;
}
