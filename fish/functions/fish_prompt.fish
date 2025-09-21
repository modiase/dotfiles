function fish_prompt
    set -l nord4 (set_color d8dee9)
    set -l text_contrast (set_color 88c0d0)
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
            echo -n -s $text_contrast "*" $normal
        end

        set -l git_ahead_symbol (git_ahead "↑" "↓" "⥄ " "")
        echo -n -s $text_contrast $git_ahead_symbol $normal
        test -n $git_ahead_symbol || git_is_touched && echo -n " "
    end

    echo -n -s $nord4 ">" $nord4 ">" $text_contrast ">"
    echo -n -s " " $normal
end
