set -l root_dir (pwd)

set -l current_dir (pwd)
while test "$current_dir" != /
    if test -d "$current_dir/.vscode"
        set root_dir "$current_dir"
        break
    end
    set current_dir (dirname "$current_dir")
end

if test "$root_dir" = (pwd)
    set -l git_root (git rev-parse --show-toplevel 2>/dev/null)
    if test $status -eq 0
        set root_dir "$git_root"
    end
end

tmux -S /tmp/tmux-vscode -f ~/.config/tmux/tmux-vscode.conf new-session -A -s "cursor-$(echo $root_dir | md5sum | cut -c1-8)"
