import { type Plugin } from "@opencode-ai/plugin";
import { createLogger } from "./devlogs";

const log = createLogger("opencode-notify");
const DING = "@ding@";

const plugin: Plugin = async ({ $ }) => {
  log.debug("plugin loaded");
  return {
    event: async ({ event }) => {
      switch (event.type) {
        case "session.idle":
          await $`${DING} --focus-pane -i '#{t_window_name}' -m 'Agent stopped'`
            .quiet()
            .nothrow();
          break;
        case "permission.updated":
          await $`${DING} --focus-pane -i 'OpenCode' -m 'Permission needed' -t request`
            .quiet()
            .nothrow();
          break;
        case "session.error":
          await $`${DING} --focus-pane -i 'OpenCode' -m 'Error occurred'`
            .quiet()
            .nothrow();
          break;
      }
    },
  };
};

export default plugin;
