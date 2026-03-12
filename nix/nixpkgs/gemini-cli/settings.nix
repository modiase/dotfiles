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
  context.includeDirectories = [ ];
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
    BeforeAgent = [
      {
        hooks = [
          {
            type = "command";
            command = "${hookBin} before-agent";
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
