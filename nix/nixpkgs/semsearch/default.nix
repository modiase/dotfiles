{ pkgs, lib, ... }:

pkgs.buildGoModule {
  pname = "semsearch";
  version = "1.0.0";

  src = ./.;

  vendorHash = "sha256-ieCKKsZ0YDcEKsbLutC/avyt9i9KG4S9hyTvlLj/hyI=";

  meta = with lib; {
    description = "Semantic search using Google Custom Search with embedding-based filtering";
    mainProgram = "semsearch";
  };
}
