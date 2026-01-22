argparse h/help 'm/mode=' -- $argv
or return

if set -q _flag_help
    echo "Usage: slugify [OPTIONS] [TEXT]"
    echo ""
    echo "Options:"
    echo "  -m, --mode=MODE  Output mode: kebab (default), ikebab, camel, pascal"
    echo ""
    echo "Examples:"
    echo "  slugify 'Hello World'              # hello-world"
    echo "  slugify -m ikebab 'Hello World'    # Hello-World"
    echo "  slugify -m camel 'Hello World'     # helloWorld"
    return 0
end

set -l mode kebab
set -q _flag_mode; and set mode $_flag_mode

set -l input
if test (count $argv) -gt 0
    set input (string join " " $argv)
else if not isatty stdin
    read -z input
    set input (string trim $input)
else
    echo "Error: no input provided" >&2
    return 1
end

echo "$input" | python3 -c '
import sys, re
mode = sys.argv[1] if len(sys.argv) > 1 else "kebab"
text = sys.stdin.read().strip()
words = [w for w in re.split(r"[^a-zA-Z0-9]+", text) if w]
if not words:
    print("")
elif mode == "kebab":
    print("-".join(w.lower() for w in words))
elif mode == "ikebab":
    print("-".join(words))
elif mode == "camel":
    print(words[0].lower() + "".join(w.capitalize() for w in words[1:]))
elif mode == "pascal":
    print("".join(w.capitalize() for w in words))
else:
    print("-".join(w.lower() for w in words))
' "$mode"
