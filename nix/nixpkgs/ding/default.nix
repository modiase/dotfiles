{
  writeShellApplication,
  coreutils,
}:

writeShellApplication {
  name = "ding";
  runtimeInputs = [ coreutils ];
  text = builtins.readFile ./ding.sh;
}
