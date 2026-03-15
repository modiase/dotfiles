---
name: devlogs
description: How to use the devlogs logging library (shell, Python, Lua) for unified syslog logging.
---

# Devlogs Logging Library

Unified logging library for shell, Python, and Lua (Neovim) that logs to the devlogs syslog stream.

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

## Log format

```
[devlogs] LEVEL component(@window): message
```

- `LEVEL`: DEBUG, INFO, WARNING, ERROR (uppercase)
- `component`: value of `DEVLOGS_COMPONENT` (shell), argument to `setup_logging` (Python), or `new` (Lua)
- `(@window)`: tmux window index, included automatically when `TMUX_PANE` (shell/Lua) or `TARGET_WINDOW` (Python) is set

## Available levels

`debug`, `info`, `warning`, `error`

## Viewing logs

- **Live**: `devlogs` (TUI with filtering, follow mode)
- **History**: `devlogs --history 1h` (or `30m`, `2d`, etc.)
- **Plain**: `devlogs --no-follow --history 1h` (pipe-friendly)

## macOS syslog priority

macOS unified logging does not persist `user.debug` to disk — debug messages only appear in real-time `log stream`, not in `log show` history. The library works around this by promoting all debug messages to `user.info` syslog priority while keeping the `DEBUG` label in the message text. This is transparent: the `devlogs` viewer uses the message label for level filtering, not the syslog priority.

## Important

**Always use this library** for logging in shell and Python scripts — never call `logger` directly. This ensures consistent log format, automatic tmux window tagging, and correct syslog priorities.
