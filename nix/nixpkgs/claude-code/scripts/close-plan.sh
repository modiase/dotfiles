# shellcheck shell=bash
_wrapper_id=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --wrapper-id)
            _wrapper_id="$2"
            shift 2
            ;;
        *) shift ;;
    esac
done
cat >/dev/null
exit 0
