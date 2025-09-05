argparse 'r/repo=' 'l/limit=' 'a/after=' 's/search=' v/verbose -- $argv; or return

set -q _flag_repo; and set -f repo $_flag_repo; or set -f repo origin
set -q _flag_limit; and set -f limit $_flag_limit
set -q _flag_after; and set -f after $_flag_after
set -q _flag_search; and set -f search $_flag_search
set -q _flag_verbose; and set -f verbose 1; or set -f verbose 0

function _log
    switch $argv[1]
        case error
            printf "\033[31mError: %s\033[0m\n" $argv[2..] >&2
        case warn
            printf "\033[33mWarning: %s\033[0m\n" $argv[2..] >&2
        case info
            if test (count $argv) -gt 1; and test $verbose -eq 1 2>/dev/null
                printf "Info: %s\n" $argv[2..] >&2
            end
    end
end

test -z (git rev-parse --git-dir 2>/dev/null); and _log error "Not in a git repository"; and return 1
set -f remote_url (git remote get-url $repo 2>/dev/null); or begin
    _log error "Remote '$repo' not found"
    return 1
end

if string match -q "*github.com*" $remote_url; and command -v gh >/dev/null
    _log info "Fetching branches from GitHub API"
    if test -n "$after"
        if string match -qr '^[0-9]+[dhms]$' $after
            set -l mult 1
            string match -q "*d" $after; and set mult 86400
            string match -q "*h" $after; and set mult 3600
            string match -q "*m" $after; and set mult 60
            set -l num (string sub -e -1 $after)
            set -l seconds (math $num \* $mult)
            set -f after_date (date -u -v-{$seconds}S '+%Y-%m-%d' 2>/dev/null; or date -u -d "@"(math (date +%s) - $seconds) '+%Y-%m-%d' 2>/dev/null)
        else
            set -f after_date $after
        end
        _log info "Filtering branches with commits after" "$after_date"
        set -l first_count (test -n "$limit"; and echo $limit; or echo 100)
        set -l owner_repo (string replace 'https://github.com/' '' $remote_url | string replace '.git' '')
        set -l owner (string split '/' $owner_repo)[1]
        set -l repo_name (string split '/' $owner_repo)[2]
        _log info "Server-side filtering commits after" "$after_date"
        set -f recent_commits (gh search commits "repo:$owner/$repo_name" --author-date ">$after_date" --limit 100 --json sha | jq -r '.[].sha' 2>&1)
        if test $status -ne 0
            _log error "Failed to search commits"
            echo "$recent_commits" >&2
            return 1
        end
        set -f all_branches (gh api repos/$owner/$repo_name/branches --jq ".[].name" 2>&1)
        if test $status -ne 0
            _log error "Failed to fetch branches"
            echo "$all_branches" >&2
            return 1
        end
        set -f gh_output
        for branch in $all_branches
            set -f branch_commit (gh api repos/$owner/$repo_name/branches/$branch --jq ".commit.sha" 2>/dev/null)
            if contains -- $branch_commit $recent_commits
                set -f gh_output $gh_output $branch
            end
        end
    else
        set -l owner_repo (string replace 'https://github.com/' '' $remote_url | string replace '.git' '')
        set -l owner (string split '/' $owner_repo)[1]
        set -l repo_name (string split '/' $owner_repo)[2]
        if test -n "$limit"
            _log info "Limiting results to $limit branches"
            set -f gh_output (gh api repos/$owner/$repo_name/branches --jq ".[:$limit][].name" 2>&1)
        else
            set -f gh_output (gh api repos/$owner/$repo_name/branches --jq ".[].name" 2>&1)
        end
    end
    if test $status -ne 0
        _log error "Failed to fetch branches from GitHub API"
        echo "$gh_output" >&2
        return 1
    end
    for branch in $gh_output
        if test -n "$search"
            echo $branch | grep -E "$search"
        else
            echo $branch
        end
    end
else
    _log info "Fetching branches using git (non-GitHub repository)"
    git fetch $repo --quiet
    set -f branches (git branch -r | grep "^[[:space:]]*$repo/" | sed "s|^[[:space:]]*$repo/||" | grep -v HEAD)
    test -n "$search"; and set branches (printf '%s\n' $branches | grep -E "$search")
    test -n "$limit"; and set branches (printf '%s\n' $branches | head -n $limit)
    test -n "$after"; and _log warn "Time-based filtering (--after) not supported for non-GitHub repositories"
    printf '%s\n' $branches
end | begin
    read -z branches
    test -z "$branches"; and _log error "No branches found"; and return 1
    set -f selected (printf '%s\n' $branches | fzf --prompt="Select branch: " --height=40% --reverse --preview="git log --oneline --format='%C(yellow)%h%C(reset) %C(blue)%ar%C(reset) %s' --color=always $repo/{} -10 2>/dev/null || echo 'No commits found'")
    test -z "$selected"; and _log error "No branch selected"; and return 1
    _log info "Stashing changes before branch switch"
    git stash push -m "Auto-stash before branch switch" --quiet 2>/dev/null
    if test (git branch --list $selected | wc -l | string trim) -eq 0
        _log info "Fetching and creating local branch '$selected'"
        git fetch $repo $selected:$selected; and git checkout $selected
    else
        _log info "Switching to existing branch '$selected'"
        git checkout $selected; and git pull $repo $selected
    end
end
