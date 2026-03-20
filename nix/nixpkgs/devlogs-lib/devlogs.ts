import { spawnSync } from "child_process";

type Level = "debug" | "info" | "warning" | "error";

const PRIORITY_MAP: Record<Level, string> = {
  debug: "user.info", // macOS unified logging drops user.debug from history
  info: "user.info",
  warning: "user.warning",
  error: "user.err",
};

let _window = "";
const pane = process.env.TMUX_PANE;
if (pane) {
  try {
    const result = spawnSync(
      "tmux",
      ["display-message", "-t", pane, "-p", "#{window_index}"],
      { encoding: "utf-8", timeout: 2000 },
    );
    if (result.status === 0 && result.stdout) {
      _window = result.stdout.trim();
    }
  } catch {}
}

function log(level: Level, component: string, msg: string) {
  const tag = _window ? `${component}(@${_window})` : component;
  const formatted = `[devlogs] ${level.toUpperCase()} ${tag}: ${msg}`;
  try {
    spawnSync("logger", ["-t", "devlogs", "-p", PRIORITY_MAP[level], formatted], {
      timeout: 2000,
    });
  } catch {}
}

export interface Logger {
  debug(msg: string): void;
  info(msg: string): void;
  warning(msg: string): void;
  error(msg: string): void;
}

export function createLogger(component: string): Logger {
  return {
    debug: (msg) => log("debug", component, msg),
    info: (msg) => log("info", component, msg),
    warning: (msg) => log("warning", component, msg),
    error: (msg) => log("error", component, msg),
  };
}
