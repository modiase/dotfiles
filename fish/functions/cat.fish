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
        nvim -M -c "set nonumber norelativenumber" -c "nnoremap <buffer> q :q<CR>" $file
    case '*'
        bat $file
end
