function jira-get -d "Make a get request to the jira api using httpie"
    argparse --name=jira-get h/help 'p/path=' -- $argv
    if not set -q _flag_p
        echo "jira-get -p/--path=<path> [additional-args]"
        return 1
    end
    set -l path (echo $_flag_p |  sed -e 's/^\/*\([^\/]\)/\/\1/g')
    https -a "{$JIRA_USER}:{$JIRA_API_TOKEN}" GET {$JIRA_BASE_URL}/rest/api/2{$path} {$argv}
end

function jira-post -d "Make a put request to the jira api using httpie"
    argparse --name=jira-get h/help 'p/path=' -- $argv
    if not set -q _flag_p
        echo "jira-get -p/--path=<path> [additional-args]"
        return 1
    end
    set -l path (echo $_flag_p |  sed -e 's/^\/*\([^\/]\)/\/\1/g')
    https -a "{$JIRA_USER}:{$JIRA_API_TOKEN}" POST {$JIRA_BASE_URL}/rest/api/2{$path} {$argv}
end
