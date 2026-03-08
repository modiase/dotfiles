{ hookBin }:
{
  context.fileName = [
    "AGENTS.md"
    "GEMINI.md"
  ];
  hooks = {
    AfterAgent = [
      {
        hooks = [
          {
            type = "command";
            command = "${hookBin} stop";
          }
        ];
      }
    ];
    Notification = [
      {
        matcher = "*";
        hooks = [
          {
            type = "command";
            command = "${hookBin} permission";
          }
        ];
      }
    ];
  };
}
