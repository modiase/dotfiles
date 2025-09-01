if test (count $argv) -eq 0
    echo "Usage: gbrom <branch-name>"
    return 1
end

if not git diff-index --quiet HEAD
    echo "Error: You have uncommitted changes. Please commit or stash them first."
    return 1
end

set -l branch_name $argv[1]
set -l default_branch (get_default_branch)

if test $status -ne 0
    echo "Error: Could not determine default branch"
    return 1
end

echo "Switching to $default_branch and pulling latest changes..."
git checkout $default_branch
if test $status -ne 0
    echo "Error: Failed to checkout $default_branch"
    return 1
end

git pull origin $default_branch
if test $status -ne 0
    echo "Error: Failed to pull latest changes from $default_branch"
    return 1
end

echo "Creating and switching to new branch: $branch_name"
git checkout -b $branch_name
