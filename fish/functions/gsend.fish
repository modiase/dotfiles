if contains -- -h $argv; or contains -- --help $argv
    echo "gsend - Transfer uncommitted dotfiles changes to a remote host"
    echo ""
    echo "Usage: gsend <host> [options]"
    echo ""
    echo "Options:"
    echo "  -f, --force   Stash remote changes before applying"
    echo "  -d, --debug   Show commands being executed"
    echo "  -h, --help    Show this help"
    echo ""
    echo "Pre-requisites:"
    echo "  - Both local and remote must be on 'main' branch"
    echo "  - Remote must have ~/Dotfiles git repo"
    echo "  - Remote must be clean (or use --force)"
    return 0
end

set -l host ""
set -l force 0
set -l debug 0

for arg in $argv
    switch $arg
        case -f --force
            set force 1
        case -d --debug
            set debug 1
        case '-*'
            echo "Unknown option: $arg" >&2
            return 1
        case '*'
            test -z "$host"; and set host $arg
    end
end

test -z "$host"; and echo "Error: host required" >&2; and return 1

set -l local_branch (git branch --show-current)
test "$local_branch" != main; and echo "Error: local must be on main (currently: $local_branch)" >&2; and return 1

ssh -o BatchMode=yes -o ConnectTimeout=5 $host true 2>/dev/null
or begin
    echo "Error: cannot connect to $host" >&2
    return 1
end

set -l remote_check (ssh $host "cd ~/Dotfiles 2>/dev/null && git branch --show-current && git status --porcelain" 2>/dev/null)
or begin
    echo "Error: ~/Dotfiles not found on $host" >&2
    return 1
end

set -l remote_branch (echo $remote_check | head -1)
test "$remote_branch" != main; and echo "Error: $host must be on main (currently: $remote_branch)" >&2; and return 1

set -l remote_dirty (echo $remote_check | tail -n +2)
if test -n "$remote_dirty"
    if test $force -eq 1
        test $debug -eq 1; and echo "Stashing changes on $host..."
        ssh $host "cd ~/Dotfiles && git stash push -u -m 'gsend-stash'"
    else
        echo "Error: $host has uncommitted changes (use --force to stash)" >&2
        return 1
    end
end

test $debug -eq 1; and echo "Creating temp commit..."
git add -A
git commit --no-verify -m "WIP: gsend transfer to $host" >/dev/null 2>&1
or begin
    echo "No changes to send"
    return 0
end

test $debug -eq 1; and echo "Pushing to temp branch..."
git push origin HEAD:refs/heads/gsend-temp >/dev/null 2>&1

test $debug -eq 1; and echo "Applying on $host..."
ssh $host "cd ~/Dotfiles && git fetch origin gsend-temp && git reset --hard origin/gsend-temp && git reset --soft origin/main" >/dev/null 2>&1

test $debug -eq 1; and echo "Cleaning up..."
git reset --soft HEAD~1
git push origin --delete gsend-temp >/dev/null 2>&1

echo "Changes sent to $host"
