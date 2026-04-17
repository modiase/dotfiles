# shellcheck shell=bash
input=$(cat)

session_id=$(printf '%s' "$input" | jq -r '.session_id // empty')
if [[ -z "$session_id" ]]; then
    exit 0
fi

edits_file="/tmp/claude-edits-${session_id}"
if [[ ! -f "$edits_file" ]]; then
    clog debug "no edits recorded, skipping"
    exit 0
fi

trap 'rm -f "$edits_file"' EXIT

mapfile -t files < <(sort -u "$edits_file")
clog debug "formatting ${#files[@]} file(s)"

for file_path in "${files[@]}"; do
    format_file "$file_path"
done

rm -f "$edits_file"
