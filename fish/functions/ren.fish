function move --description "Rename a file in a specified path"
    if test (count $argv) -ne 2
        echo "Usage: move <path/old_name> <new_name>"
        return 1
    end

    set full_path $argv[1]
    set new_name $argv[2]
    set path (dirname "$full_path")
    set old_name (basename "$full_path")

    mv "$full_path" "$path/$new_name"
end
