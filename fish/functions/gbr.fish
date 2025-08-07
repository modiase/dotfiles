argparse d/delete -- $argv
if test -z "$argv"
    set target (git branch | fzf | sed -e 's/^ *[\*\+]* *//')
    if test -n "$target"; and [ "$target" != "$(git branch --show)" ]
        if test -n "$_flag_d"
            read -l -P "Delete branch '$target' [y/N]: " confirm
            if [ "$confirm" = y ]
                git branch -d "$target"
                if test $status -ne 0
                    read -l -P "Delete failed. Force delete branch '$target' [y/N]: " force_confirm
                    if [ "$force_confirm" = y ]
                        git branch -D "$target"
                    end
                end
            end
        else
            git checkout $target
        end
    end
else
    git branch $_flag_d $argv
end
