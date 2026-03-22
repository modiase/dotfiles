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

function log(level: Level, component: string, instance: string, msg: string) {
  let tag = `${component}{${instance}}`;
  if (_window) {
    tag = `${component}{${instance}}(@${_window})`;
  }
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

export function createLogger(component?: string, instance?: string): Logger {
  const comp = component || process.env.DEVLOGS_COMPONENT || "unknown";
  const inst = instance || process.env.DEVLOGS_INSTANCE || "-";
  return {
    debug: (msg) => log("debug", comp, inst, msg),
    info: (msg) => log("info", comp, inst, msg),
    warning: (msg) => log("warning", comp, inst, msg),
    error: (msg) => log("error", comp, inst, msg),
  };
}
