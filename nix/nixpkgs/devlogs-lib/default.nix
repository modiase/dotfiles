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
in
{
  inherit shell python;
}
