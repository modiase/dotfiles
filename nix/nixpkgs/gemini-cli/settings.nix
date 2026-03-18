{
  hookBin,
  openPlanBin,
  closePlanBin,
  ...
}:
{
  general = {
    defaultApprovalMode = "plan";
    sessionRetention = {
      enabled = true;
      maxAge = "120d";
    };
  };
  experimental.plan = true;
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
    AfterTool = [
      {
        matcher = "write_file";
        hooks = [
          {
            type = "command";
            command = "${openPlanBin}";
          }
        ];
      }
    ];
    BeforeTool = [
      {
        matcher = "exit_plan_mode";
        hooks = [
          {
            type = "command";
            command = "${closePlanBin}";
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
