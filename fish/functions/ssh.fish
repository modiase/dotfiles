if contains -- -h $argv; or contains -- --help $argv
    echo "ssh wrapper: uses mosh + tmux when available"
    echo ""
    echo "Wrapper flags:"
    echo "  -d, --debug    Show which command will be used"
    echo "  --no-mosh      Force ssh (or set NO_MOSH=1)"
    echo "  --no-tmux      Skip tmux auto-attach (or set NO_TMUX=1)"
    echo ""
    echo "Falls back to ssh when:"
    echo "  - mosh is not installed or mosh-server missing on remote"
    echo "  - Using -L, -R, -D (port forwarding)"
    echo "  - Using -X, -Y (X11 forwarding)"
    echo "  - Using -A (agent forwarding)"
    echo ""
    echo "Passes directly to mosh when:"
    echo "  - Using --ssh, --server, --predict, --bind-server, --local, --no-init"
    return
end

set -l debug 0
set -l no_mosh 0
set -l no_tmux 0
set -l args

test -n "$NO_MOSH"; and set no_mosh 1
test -n "$NO_TMUX"; and set no_tmux 1

for arg in $argv
    switch $arg
        case -d --debug
            set debug 1
        case --no-mosh
            set no_mosh 1
        case --no-tmux
            set no_tmux 1
        case '*'
            set -a args $arg
    end
end

set -l mosh_flags 0
string match -qr -- '--(ssh|server|predict|bind-server|local|no-init)(=|$)' "$args"; and set mosh_flags 1

set -l ssh_only 0
string match -qr -- '-(L|R|D|X|Y|A)' "$args"; and set ssh_only 1

set -l use_mosh 0
test $no_mosh -eq 0; and command -q mosh; and test $ssh_only -eq 0; and set use_mosh 1

test $mosh_flags -eq 1; and test $use_mosh -eq 0; and echo "Error: mosh flags used but mosh unavailable or --no-mosh set" >&2; and return 1

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
    set -l cmd command ssh
    test $want_tmux -eq 1; and set -a cmd -t
    set -a cmd $args
    set -l tmux_suffix
    test $want_tmux -eq 1; and set tmux_suffix '"tmux attach 2>/dev/null || tmux new"'
    test $debug -eq 1; and echo "Using: $cmd $tmux_suffix"
    eval $cmd $tmux_suffix
end

if test $use_mosh -eq 1
    set -l mosh_check (command ssh -o BatchMode=yes -o ConnectTimeout=2 $host "command -v mosh-server" 2>/dev/null)
    if string match -q '*mosh-server*' "$mosh_check"
        set -l cmd mosh $args
        set -l tmux_suffix
        test $want_tmux -eq 1; and set tmux_suffix '-- sh -c "tmux attach 2>/dev/null || tmux new"'
        test $debug -eq 1; and echo "Using: $cmd $tmux_suffix"
        eval $cmd $tmux_suffix
        test $status -ne 0; and __ssh_run_ssh
    else
        test $debug -eq 1; and echo "mosh-server not found on $host, using ssh"
        __ssh_run_ssh
    end
else
    __ssh_run_ssh
end

functions -e __ssh_run_ssh
