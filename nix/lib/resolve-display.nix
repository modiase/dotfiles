{ pkgs }:
pkgs.writeShellScript "hm-resolve-display" ''
  if [ "$(uname -s)" != "Darwin" ]; then
    exit 0
  fi

  if ! command -v launchctl >/dev/null 2>&1; then
    exit 0
  fi

  display="$(launchctl getenv DISPLAY 2>/dev/null)"
  if [ -z "$display" ]; then
    display="$(launchctl print gui/$(id -u) 2>/dev/null | sed -n 's/.*DISPLAY => //p' | tail -n 1)"
  fi

  if [ -n "$display" ]; then
    printf '%s\n' "$display"
  fi
''
