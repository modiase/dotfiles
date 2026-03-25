{
  lib,
  pkgs,
  ...
}:
let
  obsidian-minimal-theme = pkgs.callPackage ./nixpkgs/obsidian-minimal-theme { };
  obsidian-livesync = pkgs.callPackage ./nixpkgs/obsidian-livesync { };

  gcloud = "${pkgs.google-cloud-sdk}/bin/gcloud";
  jq = "${pkgs.jq}/bin/jq";
  gcpProject = "modiase-infra";
  dataJson = "$HOME/Documents/notes/.obsidian/plugins/obsidian-livesync/data.json";
in
{
  programs.obsidian = {
    enable = true;

    defaultSettings = {
      themes = [ obsidian-minimal-theme ];
      communityPlugins = [ obsidian-livesync ];
    };

    vaults.notes = {
      target = "Documents/notes";
    };
  };

  home.activation.obsidian-app-link = lib.hm.dag.entryAfter [ "installPackages" ] ''
    $DRY_RUN_CMD ln -sfn "$HOME/.nix-profile/Applications/Obsidian.app" "/Applications/Obsidian.app"
  '';

  home.activation.obsidian-livesync-secret = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    PLUGIN_DIR="$(dirname "${dataJson}")"
    if [ ! -d "$PLUGIN_DIR" ]; then
      $DRY_RUN_CMD mkdir -p "$PLUGIN_DIR"
    fi

    EXISTING="{}"
    if [ -f "${dataJson}" ]; then
      EXISTING=$(cat "${dataJson}")
    fi

    if $DRY_RUN_CMD ${gcloud} auth print-access-token >/dev/null 2>&1; then
      SETTINGS=$($DRY_RUN_CMD ${gcloud} secrets versions access latest \
        --secret=obsidian-livesync-settings --project=${gcpProject})

      echo "$EXISTING" | $DRY_RUN_CMD ${jq} \
        --argjson settings "$SETTINGS" \
        '. * $settings * {
          liveSync: true,
          periodicReplication: true,
          periodicReplicationInterval: 60,
          syncOnStart: true,
          syncOnSave: true,
          syncOnEditorSave: true,
          syncOnFileOpen: true,
          syncAfterMerge: true,
          resolveConflictsByNewerFile: true,
          showStatusOnEditor: false,
          hideFileWarningNotice: true,
          batchSave: true
        }' \
        > "${dataJson}.tmp"
      $DRY_RUN_CMD mv "${dataJson}.tmp" "${dataJson}"
    else
      echo "obsidian-livesync: gcloud not authenticated, secrets not injected"
    fi
  '';
}
