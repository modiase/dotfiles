function fish_right_prompt -d "Write out the right prompt"
    set -l color_dim (set_color -o 2c2c2c)
    set -l color_off (set_color -o normal)
    set -l timestamp (date '+%H:%M:%S %d/%m/%y')

    echo -n -s $color_dim $timestamp $color_off
end
