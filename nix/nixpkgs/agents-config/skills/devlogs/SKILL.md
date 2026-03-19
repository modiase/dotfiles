---
name: devlogs
description: How to use the devlogs logging library (shell, Python, Lua, Go) for unified syslog logging.
---

# Devlogs Logging Library

Unified logging library for shell, Python, Lua (Neovim), and Go that logs to the devlogs syslog stream.

## Shell

Set `DEVLOGS_COMPONENT` and source the library before calling `clog`:

```bash
export DEVLOGS_COMPONENT="my-script"
source ${devlogsLib.shell}/lib/devlogs.sh

clog info "something happened"
clog debug "detail=$value"
clog error "something broke"
```

### Nix integration

```nix
devlogsLib = pkgs.callPackage ../devlogs-lib { };

writeShellApplication {
  name = "my-script";
  runtimeInputs = [ ... ];
  text = ''
    export DEVLOGS_COMPONENT="my-script"
    # shellcheck source=/dev/null
    source ${devlogsLib.shell}/lib/devlogs.sh
    ${builtins.readFile ./my-script.sh}
  '';
};
```

The `.sh` file uses `clog` directly — no boilerplate needed.

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

## Log format

```
[devlogs] LEVEL component(@window): message
```

- `LEVEL`: DEBUG, INFO, WARNING, ERROR (uppercase)
- `component`: value of `DEVLOGS_COMPONENT` (shell), argument to `setup_logging` (Python), `new` (Lua), or `NewLogger` (Go)
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

**Always use this library** for logging in shell, Python, and Go — never call `logger` or `log/syslog` directly. This ensures consistent log format, automatic tmux window tagging, and correct syslog priorities.
