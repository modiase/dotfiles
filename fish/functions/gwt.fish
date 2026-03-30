argparse h/help f/from= F/force K/kill-window no-code 'c/code-args=' -- $argv; or return

set -g _gwt_code_args_val "$_flag_code_args"
if set -q _flag_no_code
    set -g _gwt_no_code 1
end

if set -q _flag_help
    echo "Usage: gwt [COMMAND] [OPTIONS]"
    echo ""
    echo "Interactive git worktree manager."
    echo ""
    echo "Commands:"
    echo "  (none)        Fuzzy-pick a worktree to cd into, or create a new one"
    echo "  new [NAME]    Create a new worktree (prompts if NAME omitted)"
    echo "  rm NAME       Remove a worktree and delete its branch"
    echo "  tidy          Interactively remove merged/stale worktrees"
    echo "  merge [BRANCH] Rebase, fast-forward merge, and remove a worktree"
    echo "  detect        List cleanup candidates (merged or stale >7d)"
    echo "  *             Passthrough to git worktree"
    echo ""
    echo "Options:"
    echo "  --no-code            Don't open code layout after create/select (default: opens code)"
    echo "  -c, --code-args=ARGS Extra args for code as key:value pairs (comma-separated)"
    echo "                       e.g. 'agent:claude,no-debug:' → --agent claude --no-debug"
    echo "  -f, --from=REF       Base ref for new worktree (default: default branch)"
    echo "  -F, --force          Force removal of unmerged branches (rm)"
    echo "  -K, --kill-window    Kill tmux window after successful merge"
    echo "  -h, --help           Show this help"
    echo ""
    echo "Settings stored in .git/gwt/settings:"
    echo "  checks=true|false    Enable/disable health checks (default: true)"
    echo "  crypt_key=NAME       git-crypt key name (auto-detected if only one)"
    return 0
end

set -g _gwt_git_dir (git rev-parse --git-dir 2>/dev/null); or begin
    echo "Error: not in a git repository" >&2
    return 1
end
function _gwt_cleanup
    set -eg _gwt_git_dir _gwt_toplevel _gwt_default_branch _gwt_code_args_val _gwt_no_code 2>/dev/null
end

set -l common_dir (realpath (git rev-parse --git-common-dir 2>/dev/null))
set -l actual_git_dir (realpath "$_gwt_git_dir")
if test "$common_dir" != "$actual_git_dir"
    set -l main_toplevel (git -C "$common_dir/.." rev-parse --show-toplevel 2>/dev/null)
    set -l reinvoke_argv $argv
    if test "$argv[1]" = merge -a (count $argv) -le 1
        set -a reinvoke_argv (git branch --show-current)
    end
    set -q _flag_kill_window; and set -a reinvoke_argv -K
    _gwt_cleanup
    env -C "$main_toplevel" fish -c 'gwt $argv' -- $reinvoke_argv
    return $status
end
set -g _gwt_toplevel (git rev-parse --show-toplevel 2>/dev/null)
set -g _gwt_default_branch (get_default_branch)

function _gwt_setting -a key default
    set -l file $_gwt_git_dir/gwt/settings
    test -f "$file"; or begin
        echo $default
        return
    end
    set -l val (string match -r "^$key=(.*)" <"$file")
    test (count $val) -ge 2; and echo $val[2]; or echo $default
end

function _gwt_set -a key value
    mkdir -p "$_gwt_git_dir/gwt"
    set -l file $_gwt_git_dir/gwt/settings
    if test -f "$file"
        set -l tmp (mktemp)
        string match -rv "^$key=" <"$file" >"$tmp"
        echo "$key=$value" >>"$tmp"
        mv "$tmp" "$file"
    else
        echo "$key=$value" >"$file"
    end
end

function _gwt_check_candidate -a wt_path wt_branch
    test -z "$wt_branch"; and return
    test "$wt_path" = "$_gwt_toplevel"; and return
    set -l merged_branches (git branch --merged $_gwt_default_branch --format='%(refname:short)' 2>/dev/null)
    set -l reasons
    contains -- $wt_branch $merged_branches; and set -a reasons merged
    set -l stale_threshold (math (date +%s)" - 604800")
    set -l commit_ts (git log -1 --format=%ct $wt_branch 2>/dev/null)
    test -n "$commit_ts" -a "$commit_ts" -lt "$stale_threshold"; and set -a reasons stale
    test (count $reasons) -gt 0; and printf "%s\t%s\n" $wt_branch (string join , $reasons)
end

function _gwt_detect
    set -l wt_paths
    set -l wt_branches
    set -l cur_path ""
    set -l cur_branch ""
    for line in (git worktree list --porcelain 2>/dev/null)
        if string match -qr '^worktree (.+)' $line
            if test -n "$cur_path"
                set -a wt_paths $cur_path
                set -a wt_branches (test -n "$cur_branch"; and echo $cur_branch; or echo "")
            end
            set cur_path (string match -r '^worktree (.+)' $line)[2]
            set cur_branch ""
        else if string match -qr '^branch refs/heads/(.+)' $line
            set cur_branch (string match -r '^branch refs/heads/(.+)' $line)[2]
        end
    end
    if test -n "$cur_path"
        set -a wt_paths $cur_path
        set -a wt_branches (test -n "$cur_branch"; and echo $cur_branch; or echo "")
    end

    for i in (seq (count $wt_paths))
        _gwt_check_candidate $wt_paths[$i] $wt_branches[$i]
    end
end

function _gwt_health
    mkdir -p "$_gwt_git_dir/gwt"
    test (_gwt_setting checks true) = false; and return

    set -l exclude_file $_gwt_git_dir/info/exclude
    if test -f "$exclude_file"
        string match -q worktrees/ <"$exclude_file"; or echo worktrees/ >>"$exclude_file"
    else
        mkdir -p "$_gwt_git_dir/info"
        echo worktrees/ >"$exclude_file"
    end

    set -l last (string trim -- (_gwt_setting last_warned 0))
    set -l now (date +%s)
    test (math "$now - $last") -lt 86400; and return

    set -l candidates (_gwt_detect)
    if test (count $candidates) -gt 0
        printf "\033[33mgwt: %d worktree(s) may need cleanup (run `gwt tidy`)\033[0m\n" (count $candidates) >&2
    end
    _gwt_set last_warned $now
end

function _gwt_crypt_key
    set -l key_dir "$_gwt_git_dir/git-crypt/keys"
    test -d "$key_dir"; or return

    set -l keys (find "$key_dir" -type f -not -name '.*')
    test (count $keys) -eq 0; and return

    if test (count $keys) -eq 1
        realpath "$keys[1]"
        return
    end

    set -l saved (_gwt_setting crypt_key)
    if test -n "$saved" -a -f "$key_dir/$saved"
        realpath "$key_dir/$saved"
        return
    end

    set -l names
    for k in $keys
        set -a names (string replace "$key_dir/" "" "$k")
    end
    set -l chosen (printf '%s\n' $names | fzf --prompt="Git-crypt key> " --height=40% --reverse)
    test -z "$chosen"; and return 1
    _gwt_set crypt_key "$chosen"
    realpath "$key_dir/$chosen"
end

function _gwt_code_args -a branch path
    set -l repo (basename $_gwt_toplevel)
    set -l code_cmd code --name "$repo""[$branch]"

    if test -n "$_gwt_code_args_val"
        for pair in (string split , $_gwt_code_args_val)
            set -l kv (string split -m1 : $pair)
            if test "$kv[1]" = name
                test (count $kv) -ge 2 -a -n "$kv[2]"; and set code_cmd[3] $kv[2]
                continue
            end
            set -a code_cmd --$kv[1]
            test (count $kv) -ge 2 -a -n "$kv[2]"; and set -a code_cmd $kv[2]
        end
    end

    $code_cmd $path
end

function _gwt_new
    argparse from= -- $argv; or return
    set -l name $argv[1]
    if test -z "$name"
        command -v gum >/dev/null; or begin
            echo "Error: gum required for interactive input" >&2
            return 1
        end
        set name (gum input --placeholder "Worktree name")
        test -z "$name"; and return 0
    end

    set name (string lower -- $name | string replace -ra '\s+' '-' | string replace -ra '[^a-z0-9-]' '' | string replace -ra -- '-+' '-' | string trim -c '-')

    if not test -d $_gwt_toplevel/worktrees/$name
        set -l key_file (_gwt_crypt_key)
        set -l no_checkout
        test -n "$key_file"; and set no_checkout --no-checkout

        if git show-ref --verify --quiet refs/heads/$name 2>/dev/null
            git -C $_gwt_toplevel worktree add $no_checkout worktrees/$name $name
        else
            set -l base $_gwt_default_branch
            test -n "$_flag_from"; and set base $_flag_from
            git -C $_gwt_toplevel worktree add $no_checkout -b $name worktrees/$name $base
        end; or return 1

        if set -q no_checkout[1]
            set -l wt_git_dir (git rev-parse --git-common-dir)/worktrees/$name
            ln -s ../../git-crypt "$wt_git_dir/git-crypt"
            git -C $_gwt_toplevel/worktrees/$name checkout HEAD -- .; or return 1
        end
    end

    if not set -q _gwt_no_code
        _gwt_code_args $name "$_gwt_toplevel/worktrees/$name"
    end
end

function _gwt_select
    set -l entries
    set -l paths
    for line in (git worktree list --porcelain 2>/dev/null)
        if string match -qr '^worktree (.+)' $line
            set -l p (string match -r '^worktree (.+)' $line)[2]
            set -a paths $p
            if test "$p" = "$_gwt_toplevel"
                set -a entries (printf "%-40s %s" (basename $p) "[main worktree]")
            else
                set -a entries (basename $p)
            end
        end
    end
    set -a entries "[new]"

    set -l selected (printf '%s\n' $entries | fzf --prompt="Worktree> " --height=40% --reverse)
    test -z "$selected"; and return 0

    if test "$selected" = "[new]"
        _gwt_new
        return
    end

    set -l clean (string trim -- $selected)
    for i in (seq (count $entries))
        if test (string trim -- $entries[$i]) = "$clean"
            if not set -q _gwt_no_code
                _gwt_code_args (basename $paths[$i]) $paths[$i]
            end
            return
        end
    end
end

function _gwt_remove
    argparse force -- $argv; or return
    set -l name $argv[1]
    if test -z "$name"
        set -l wt_names
        for line in (git worktree list --porcelain 2>/dev/null)
            if string match -qr '^worktree (.+)' $line
                set -l p (string match -r '^worktree (.+)' $line)[2]
                test "$p" = "$_gwt_toplevel"; and continue
                set -a wt_names (basename $p)
            end
        end
        test (count $wt_names) -eq 0; and echo "No worktrees to remove." >&2; and return 0
        set name (printf '%s\n' $wt_names | fzf --prompt="Remove worktree> " --height=40% --reverse)
        test -z "$name"; and return 0
    end

    set -l wt_path $_gwt_toplevel/worktrees/$name
    git worktree list --porcelain | string match -q "worktree $wt_path"; or begin
        echo "Error: worktree '$name' not found" >&2
        return 1
    end

    if not set -q _flag_force
        git branch --merged $_gwt_default_branch | string match -q "*$name"; or begin
            echo "Branch '$name' is not fully merged. Use -F to force delete." >&2
            return 1
        end
        git worktree remove $wt_path; or return 1
        git branch -d $name 2>/dev/null
    else
        git worktree remove --force $wt_path; or return 1
        git branch -D $name 2>/dev/null
    end
end

function _gwt_tidy
    set -l candidates (_gwt_detect)
    test (count $candidates) -eq 0; and echo "No cleanup candidates found."; and return

    set -l labels
    for c in $candidates
        set -l parts (string split \t $c)
        set -a labels "$parts[1] ($parts[2])"
    end

    set -l chosen (printf '%s\n' $labels | fzf --multi --prompt="Tidy worktrees> " --height=40% --reverse --header "enter: toggle select | c: confirm" --bind 'enter:toggle+down,c:accept')
    test (count $chosen) -eq 0; and return 0

    for pick in $chosen
        set -l branch (string match -r '^(\S+)' $pick)[2]
        git worktree remove $_gwt_toplevel/worktrees/$branch
    end
end

function _gwt_merge
    set -l name $argv[1]
    if test -z "$name"
        set -l wt_names
        for line in (git worktree list --porcelain 2>/dev/null)
            if string match -qr '^worktree (.+)' $line
                set -l p (string match -r '^worktree (.+)' $line)[2]
                test "$p" = "$_gwt_toplevel"; and continue
                set -a wt_names (basename $p)
            end
        end
        test (count $wt_names) -eq 0; and echo "No worktrees to merge." >&2; and return 0
        set name (printf '%s\n' $wt_names | fzf --prompt="Merge worktree> " --height=40% --reverse)
        test -z "$name"; and return 0
    end

    set -l wt_path $_gwt_toplevel/worktrees/$name
    if not test -d "$wt_path"; or not git -C "$wt_path" rev-parse --is-inside-work-tree &>/dev/null
        echo "Error: worktree '$name' not found" >&2
        return 1
    end

    set -l branch (git -C "$wt_path" branch --show-current)
    if test -z "$branch"
        echo "Error: worktree '$name' is in detached HEAD state" >&2
        return 1
    end

    if test -n "$(git -C $wt_path status --porcelain | string collect)"
        echo "Error: worktree '$name' has uncommitted changes" >&2
        return 1
    end

    if test -n "$(git -C $_gwt_toplevel status --porcelain | string collect)"
        echo "Error: main worktree has uncommitted changes" >&2
        return 1
    end

    if not git -C "$wt_path" rebase $_gwt_default_branch
        echo "Error: rebase failed — aborting" >&2
        git -C "$wt_path" rebase --abort 2>/dev/null
        return 1
    end

    set -l orig_branch (git -C $_gwt_toplevel branch --show-current)
    git -C $_gwt_toplevel checkout $_gwt_default_branch; or return 1

    if not git -C $_gwt_toplevel merge --ff-only "$branch"
        echo "Error: fast-forward merge of '$branch' into $_gwt_default_branch failed" >&2
        if not git -C $_gwt_toplevel checkout "$orig_branch" 2>/dev/null
            echo "Warning: could not restore branch '$orig_branch'" >&2
        end
        return 1
    end

    git worktree remove "$wt_path"; or return 1
    git branch -d "$branch"
end

switch "$argv[1]"
    case detect
        _gwt_detect
    case rm remove
        set -l _gwt_rm_args $argv[2]
        set -q _flag_force; and set -a _gwt_rm_args --force
        _gwt_remove $_gwt_rm_args
    case tidy
        _gwt_health
        _gwt_tidy
    case merge
        _gwt_merge $argv[2]
        set -l merge_status $status
        set -q _flag_kill_window; and test $merge_status -eq 0; and tmux kill-window
    case new
        _gwt_health
        set -l _gwt_new_args $argv[2..]
        set -q _flag_from; and set -a _gwt_new_args --from=$_flag_from
        _gwt_new $_gwt_new_args
    case ''
        _gwt_health
        _gwt_select
    case '*'
        git -C $_gwt_toplevel worktree $argv
end

set -l _gwt_status $status
_gwt_cleanup
return $_gwt_status
