git status &>/dev/null; and python -c 'import sys;from pathlib import Path;print(Path(sys.argv[2]).relative_to(Path(sys.argv[1])))' (git rev-parse --show-toplevel) (pwd)
