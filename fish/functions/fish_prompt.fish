set -l fg_dim (set_color e0e0e0)
set -l accent (set_color a8d8ea)
set -l normal (set_color normal)

if set -q fish_prompt_prefix
    set -l prefix_parts
    for value in $fish_prompt_prefix
        set -a prefix_parts $value
    end
    echo -n (string join " / " $prefix_parts)" "
end

if git_is_repo
    if git_is_touched
        echo -n -s $accent "*" $normal
    end

    set -l git_ahead_symbol (git_ahead "↑" "↓" "⥄ " "")
    echo -n -s $accent $git_ahead_symbol $normal
    test -n $git_ahead_symbol || git_is_touched && echo -n " "
end

echo -n -s $fg_dim ">" $fg_dim ">" $accent ">"
echo -n -s " " $normal
