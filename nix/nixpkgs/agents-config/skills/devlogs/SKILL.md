---
name: devlogs
description: How to use the devlogs logging library (shell, Fish, Python, Lua, Go, TypeScript) for unified syslog logging. MUST be activated when debugging development tools or when asked to 'check devlogs'.
---

# Devlogs Logging Library

Unified logging library for shell, Fish, Python, Lua (Neovim), Go, and TypeScript that logs to the devlogs syslog stream.

## Shell

Source the library and call `devlogs_init` with the component name before calling `clog`:

```bash
source ${devlogsLib.shell}/lib/devlogs.sh
devlogs_init my-script

clog info "something happened"
clog debug "detail=$value"
clog error "something broke"
```

`devlogs_init [component]` sets the component from: arg → `$DEVLOGS_COMPONENT` → `"unknown"`, and instance from `$DEVLOGS_INSTANCE` → `"-"`.

### Nix integration

```nix
devlogsLib = pkgs.callPackage ../devlogs-lib { };

writeShellApplication {
  name = "my-script";
  runtimeInputs = [ ... ];
  text = ''
    # shellcheck source=/dev/null
    source ${devlogsLib.shell}/lib/devlogs.sh
    devlogs_init my-script
    ${builtins.readFile ./my-script.sh}
  '';
};
```

The `.sh` file uses `clog` directly — no boilerplate needed.

## Fish

The `clog` function is available in all fish sessions:

```fish
clog info "something happened"
clog debug "detail=$value"
clog error "something broke"
```

Set `DEVLOGS_COMPONENT` and optionally `DEVLOGS_INSTANCE` to tag messages:

```fish
set -gx DEVLOGS_COMPONENT my-component
set -gx DEVLOGS_INSTANCE (uuidgen)
clog info "tagged message"
```

The tmux fish wrapper logs every command to devlogs at debug level by default. Set `TMUX_NO_TRACE` to suppress:

```fish
set -gx TMUX_NO_TRACE 1
```

## Python

```python
from devlogs import setup_logging
log = setup_logging("my-component")

log.info("something happened")
log.debug("detail=%s", value)
log.error("something broke")
```

### Nix integration

Set `PYTHONPATH` so `import devlogs` works:

```nix
devlogsLib = pkgs.callPackage ../devlogs-lib { };

text = ''
  export PYTHONPATH="${devlogsLib.python}/lib:''${PYTHONPATH:-}"
  exec python3 ${./my-script.py} "$@"
'';
```

## Lua (Neovim)

```lua
local log = require("devlogs").new("my-component")

log.info("something happened")
log.debug("detail=" .. value)
log.error("something broke")
```

The module is installed via `xdg.configFile` in `neovim.nix` — no extra setup needed in Neovim plugins.

## Go

```go
import "devlogs-lib"

var log = devlogs.NewLogger("my-component")

log.Info("something happened")
log.Debug(fmt.Sprintf("detail=%s", value))
log.Error("something broke")
```

Methods: `Debug`, `Info`, `Warn`, `Error` — each takes a single string.

### Nix integration

Use a `replace` directive in `go.mod` to point at the local library:

```
require devlogs-lib v0.0.0
replace devlogs-lib => ../devlogs-lib
```

Do **not** vendor — use a `combinedSrc` pattern in Nix to assemble both directories:

```nix
let
  combinedSrc = pkgs.runCommand "my-tool-src" { } ''
    mkdir -p $out/my-tool $out/devlogs-lib
    cp -r ${./.}/* $out/my-tool/
    cp -r ${../devlogs-lib}/* $out/devlogs-lib/
  '';
in
pkgs.buildGoModule {
  src = combinedSrc;
  sourceRoot = "${combinedSrc.name}/my-tool";
  vendorHash = null;
}
```

## TypeScript

```typescript
import { createLogger } from "./devlogs";

const log = createLogger("my-component");

log.info("something happened");
log.debug(`detail=${value}`);
log.error("something broke");
```

Methods: `debug`, `info`, `warning`, `error` — each takes a single string.

### Nix integration

Copy the library alongside your TypeScript source:

```nix
devlogsLib = pkgs.callPackage ../devlogs-lib { };

# Copy devlogs.ts into your plugin/source directory
postPatch = ''
  cp ${devlogsLib.typescript}/lib/devlogs.ts plugins/devlogs.ts
'';
```

Import with a relative path — no package manager needed.

## Log format

```
[devlogs] LEVEL component{instance}(@window): message
```

- `LEVEL`: DEBUG, INFO, WARNING, ERROR (uppercase)
- `component`: value from init arg, `DEVLOGS_COMPONENT` env, or `"unknown"`
- `{instance}`: value from `DEVLOGS_INSTANCE` env or `"-"` sentinel (always present)
- `(@window)`: tmux window index, included automatically when `TMUX_PANE` (shell/Lua) or `TARGET_WINDOW` (Python) is set

## Available levels

`debug`, `info`, `warning`, `error`

## Viewing logs

Use `devlogs` to read logs from this logging stack. System log tools (`/usr/bin/log show`, `journalctl`) are for OS-level logs — devlogs wraps them with the right filters and formatting for development logging.

```
devlogs [flags]
  -H, --history string   Show history (e.g. 1h, 30m, 2d)
  -l, --level string     Minimum log level: debug, info, warn, error (default "info")
  -n, --no-follow        Show history and exit (no live stream)
  -p, --plain            Force plain text output (no TUI)
  -w, --window string    Window filter (-1 for all, N for specific)
```

Common usage:

- **Live TUI**: `devlogs` (interactive, follow mode)
- **History**: `devlogs --history 1h` (or `30m`, `2d`, etc.)
- **Scriptable/grep-friendly**: `devlogs --plain --history 5m -w "-1"`
- **Debug-level logs**: `devlogs --plain --history 5m --level debug` (default is info, so debug messages are hidden unless you pass this)
- **Specific window**: `devlogs --plain --history 5m -w 3`

## macOS syslog priority

macOS unified logging does not persist `user.debug` to disk — debug messages only appear in real-time `log stream`, not in `log show` history. The library works around this by promoting all debug messages to `user.info` syslog priority while keeping the `DEBUG` label in the message text. This is transparent: the `devlogs` viewer uses the message label for level filtering, not the syslog priority.

## Important

**Always use this library** for logging in shell, Fish, Python, Lua, Go, and TypeScript — never call `logger` or `log/syslog` directly. This ensures consistent log format, automatic tmux window tagging, and correct syslog priorities.
