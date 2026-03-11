{ hookBin }:
{
  general = {
    vimMode = true;
    sessionRetention = {
      enabled = true;
      maxAge = "120d";
    };
  };
  ide.enabled = true;
  context.fileName = [
    "GEMINI.md"
  ];
  hooks = {
    SessionStart = [
      {
        matcher = "startup";
        hooks = [
          {
            type = "command";
            command = "${hookBin} init";
          }
        ];
      }
    ];
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
