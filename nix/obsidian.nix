{
  pkgs,
  lib,
  isDev ? false,
  ...
}:
let
  obsidian-minimal-theme = pkgs.callPackage ./nixpkgs/obsidian-minimal-theme { };
  obsidian-livesync = pkgs.callPackage ./nixpkgs/obsidian-livesync { };

  gcloud = "${pkgs.google-cloud-sdk}/bin/gcloud";
  node = "${pkgs.nodejs}/bin/node";
  jq = "${pkgs.jq}/bin/jq";
  python = "${pkgs.python3}/bin/python3";
  gcpProject = "modiase-infra";
  dataJson = "$HOME/Documents/notes/.obsidian/plugins/obsidian-livesync/data.json";
  decryptScript = ./nixpkgs/obsidian-livesync/decrypt-setup-uri.mjs;
in
lib.mkIf (isDev && pkgs.stdenv.isDarwin) {
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
      SETUP_URI_RAW=$($DRY_RUN_CMD ${gcloud} secrets versions access latest \
        --secret=obsidian-livesync-uri --project=${gcpProject})
      URI_PASSPHRASE=$($DRY_RUN_CMD ${gcloud} secrets versions access latest \
        --secret=obsidian-livesync-passphrase --project=${gcpProject})

      ENCODED=$(echo "$SETUP_URI_RAW" | $DRY_RUN_CMD sed 's|obsidian://setuplivesync?settings=||')
      DECODED=$($DRY_RUN_CMD ${python} -c "import urllib.parse,sys; print(urllib.parse.unquote(sys.argv[1]))" "$ENCODED")
      URI_SETTINGS=$($DRY_RUN_CMD ${node} ${decryptScript} "$DECODED" "$URI_PASSPHRASE")

      echo "$EXISTING" | $DRY_RUN_CMD ${jq} \
        --argjson uri "$URI_SETTINGS" \
        '. * $uri | .encryptedCouchDBConnection = "" | .encryptedPassphrase = ""' \
        > "${dataJson}.tmp"
      $DRY_RUN_CMD mv "${dataJson}.tmp" "${dataJson}"
    else
      echo "obsidian-livesync: gcloud not authenticated, secrets not injected"
    fi
  '';
}
