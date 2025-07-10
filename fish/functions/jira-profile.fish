function jira-profile
    set -l JIRA_CONFIG_FILE ~/.jira-config.json
    if not test -f $JIRA_CONFIG_FILE
        echo "No jira config file found at: {$JIRA_CONFIG_FILE}"
        return 1
    end
    set -gx JIRA_PROFILE (jq 'keys | @csv ' $JIRA_CONFIG_FILE | tr ',' '\n' | tr -d '[\\\"]' | fzf)
    set -gx JIRA_USER (jq ".$JIRA_PROFILE.user" $JIRA_CONFIG_FILE | tr -d '"')
    set -gx JIRA_API_TOKEN (jq ".$JIRA_PROFILE.apiToken" $JIRA_CONFIG_FILE | tr -d '"')
    set -gx JIRA_BASE_URL (jq ".$JIRA_PROFILE.baseUrl" $JIRA_CONFIG_FILE | tr -d '"' | sed -e 's/\/\+$//g')
    set -gx JIRA_API_BASE_URL "{$JIRA_BASE_URL}/rest/api/2"
end
