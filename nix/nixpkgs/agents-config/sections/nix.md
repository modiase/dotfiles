## Missing Tools

This system uses Nix. If a tool is not available in the current environment, use `nix run nixpkgs#<package>` to run it ad-hoc. In exceptional circumstances where a package isn't in nixpkgs or needs customisation, build it from source using `nix-build -E` or a temporary flake.
