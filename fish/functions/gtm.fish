set -l default_branch (get_default_branch)
if test $status -ne 0
    return $status
end
git checkout $default_branch
