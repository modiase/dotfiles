---
name: devlogs
description: How to use the devlogs logging library (shell and Python) for unified syslog logging.
---

# Devlogs Logging Library

Unified logging library for shell and Python scripts that log to the devlogs syslog stream.

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

## Log format

```
[devlogs] LEVEL component(@window): message
```

- `LEVEL`: DEBUG, INFO, WARNING, ERROR (uppercase)
- `component`: value of `DEVLOGS_COMPONENT` (shell) or argument to `setup_logging` (Python)
- `(@window)`: tmux window index, included automatically when `TMUX_PANE` (shell) or `TARGET_WINDOW` (Python) is set

## Available levels

`debug`, `info`, `warning`, `error`
