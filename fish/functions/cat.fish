if not command -q bat
    command cat $argv
    return
end

# Pass through to bat if: piping, no args, or multiple files
if not isatty stdout; or test (count $argv) -ne 1
    bat $argv
    return
end

set -l file $argv[1]

switch (string lower (path extension $file))
    case .json
        jq . $file 2>/dev/null; or bat $file
    case .md .markdown
        nvim -M --cmd "let g:pager_mode=1" -c "set nonumber norelativenumber wrap linebreak" -c "nnoremap <buffer> q :q<CR>" $file
    case .png .jpg .jpeg .gif .bmp .webp .tiff .tif .svg .ico
        if test -n "$TMUX"
            chafa --format kitty --passthrough tmux $file
        else
            chafa --format kitty $file
        end
    case '*'
        bat $file
end
