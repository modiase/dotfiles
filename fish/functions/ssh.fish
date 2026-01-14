if contains -- -h $argv; or contains -- --help $argv
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo "SSH WRAPPER"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo ""
    echo "Smart SSH wrapper that uses Eternal Terminal (et) + tmux when available."
    echo "Falls back to plain SSH when et is unavailable or incompatible flags are used."
    echo ""
    echo "WRAPPER FLAGS:"
    echo "  -d, --debug    Show which command will be used"
    echo "  --no-et        Force plain SSH (or set NO_ET=1)"
    echo "  --no-tmux      Skip tmux auto-attach (auto when inside tmux, or NO_TMUX=1)"
    echo ""
    echo "AUTOMATIC FALLBACK TO SSH:"
    echo "  - et not installed or etserver missing on remote"
    echo "  - Port forwarding flags: -L, -R, -D"
    echo "  - X11 forwarding flags: -X, -Y"
    echo "  - Agent forwarding flag: -A"
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo "ETERNAL TERMINAL (et) HELP"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    command -q et; and et --help 2>&1; or echo "  (et not installed)"
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo "SSH HELP"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    command ssh --help 2>&1; or ssh 2>&1
    return
end

set -l debug 0
set -l no_et 0
set -l no_tmux 0
set -l args

test -n "$NO_ET"; and set no_et 1
test -n "$NO_TMUX"; and set no_tmux 1
test -n "$TMUX"; and set no_tmux 1

for arg in $argv
    switch $arg
        case -d --debug
            set debug 1
        case --no-et
            set no_et 1
        case --no-tmux
            set no_tmux 1
        case '*'
            set -a args $arg
    end
end

set -l ssh_only 0
string match -qr -- '-(L|R|D|X|Y|A)' "$args"; and set ssh_only 1

set -l use_et 0
test $no_et -eq 0; and command -q et; and test $ssh_only -eq 0; and set use_et 1

set -l skip_next 0
set -l host ""
set -l has_remote_cmd 0
set -l opts_taking_args l p i o F J c m O S W w b B D E e I L R
for arg in $args
    test $skip_next -eq 1; and set skip_next 0; and continue

    for opt in $opts_taking_args
        test "$arg" = "-$opt"; and set skip_next 1; and break
    end
    test $skip_next -eq 1; and continue

    string match -q -- '-*' "$arg"; and continue

    test -z "$host"; and set host "$arg"; and continue
    set has_remote_cmd 1
    break
end

set -l want_tmux 0
test $no_tmux -eq 0; and test $has_remote_cmd -eq 0; and test -n "$host"; and set want_tmux 1

function __ssh_run_ssh --no-scope-shadowing
    set -l ssh_opts
    test $want_tmux -eq 1; and set -a ssh_opts -q -t
    set -a ssh_opts $args
    test $want_tmux -eq 1; and set -a ssh_opts 'tmux new-session -A -s remote'
    test $debug -eq 1; and echo "Using: command ssh $ssh_opts"
    command ssh $ssh_opts
end

if test $use_et -eq 1
    set -l et_check (command ssh -o BatchMode=yes -o ConnectTimeout=2 $host "command -v etserver" 2>/dev/null)
    if string match -q '*etserver*' "$et_check"
        set -l et_status 0
        set -lx ET_NO_TELEMETRY YES
        if test $want_tmux -eq 1
            test $debug -eq 1; and echo "Using: et -c 'tmux new-session -A -s remote' $host"
            et -c 'tmux new-session -A -s remote; exit' $host 2>/dev/null; or set et_status $status
        else
            test $debug -eq 1; and echo "Using: et $host"
            et $host 2>/dev/null; or set et_status $status
        end
        test $et_status -ne 0; and __ssh_run_ssh
    else
        test $debug -eq 1; and echo "etserver not found on $host, using ssh"
        __ssh_run_ssh
    end
else
    __ssh_run_ssh
end

functions -e __ssh_run_ssh
