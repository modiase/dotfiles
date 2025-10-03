function ping-me --description "Send a notification via ntfy"
    if test (count $argv) -eq 0
        echo "Usage: ping-me <message>"
        return 1
    end

    set message (string join " " $argv)
    ntfy publish lbppXXBeZsGRsrj8 "$message"
end
