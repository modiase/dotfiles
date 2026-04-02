{
  hookBin,
  openPlanBin,
  closePlanBin,
  formatHookBin,
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
  experimental.subagents = true;
  useWriteTodos = true;
  ide.enabled = true;
  ui.hideTips = true;
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
            command = "${hookBin} init --wrapper-id $WRAPPER_ID";
          }
        ];
      }
    ];
    BeforeAgent = [
      {
        hooks = [
          {
            type = "command";
            command = "${hookBin} before-agent --wrapper-id $WRAPPER_ID";
          }
        ];
      }
    ];
    AfterAgent = [
      {
        hooks = [
          {
            type = "command";
            command = "${hookBin} stop --wrapper-id $WRAPPER_ID";
          }
        ];
      }
    ];
    AfterTool = [
      {
        matcher = "edit_file";
        hooks = [
          {
            type = "command";
            command = formatHookBin;
          }
        ];
      }
      {
        matcher = "write_file";
        hooks = [
          {
            type = "command";
            command = formatHookBin;
          }
        ];
      }
      {
        matcher = "write_file";
        hooks = [
          {
            type = "command";
            command = "${openPlanBin} --wrapper-id $WRAPPER_ID";
          }
        ];
      }
      {
        matcher = "exit_plan_mode";
        hooks = [
          {
            type = "command";
            command = "${hookBin} after-plan --wrapper-id $WRAPPER_ID";
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
            command = "${closePlanBin} --wrapper-id $WRAPPER_ID";
          }
        ];
      }
      {
        matcher = "write_file";
        hooks = [
          {
            type = "command";
            command = "${hookBin} before-plan-write --wrapper-id $WRAPPER_ID";
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
            command = "${hookBin} permission --wrapper-id $WRAPPER_ID";
          }
        ];
      }
    ];
  };
}
