function mkc --description "Create a C project with Meson, Ninja, and Nix flake"
    set -l created_items

    function cleanup_on_failure
        if test (count $created_items) -gt 0
            echo "Cleaning up created files and directories..."
            for item in $created_items[-1..1]
                if test -d $item
                    rmdir $item 2>/dev/null
                else if test -f $item
                    rm $item 2>/dev/null
                end
            end
        end
    end

    set -l target_files flake.nix meson.build src test build
    for file in $target_files
        if test -e $file
            echo "Error: $file already exists. Aborting to avoid overwriting existing files."
            return 1
        end
    end

    echo "Creating flake.nix..."
    printf '{
  description = "C project development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Choose compiler based on system
        compiler = if pkgs.stdenv.isDarwin then pkgs.clang else pkgs.gcc;

        setup = pkgs.writeShellScriptBin "setup" "meson setup build";
        run = pkgs.writeShellScriptBin "run" \'\'
          if [ ! -f build/build.ninja ]; then
            echo "Build directory not set up, running setup first..."
            meson setup build
          fi
          meson compile -C build run
        \'\';
        run_test = pkgs.writeShellScriptBin "run_test" \'\'
          if [ ! -f build/build.ninja ]; then
            echo "Build directory not set up, running setup first..."
            meson setup build
          fi
          meson test -C build
        \'\';
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # tools
            compiler
            meson
            ninja
            pkg-config

            # commands
            setup
            run
            run_test
          ];
        };
      });
}
' >flake.nix
    if test $status -ne 0
        cleanup_on_failure
        return 1
    end
    set -a created_items flake.nix

    echo "Creating src directory..."
    if not mkdir src
        cleanup_on_failure
        return 1
    end
    set -a created_items src

    echo "Creating src/main.c..."
    printf '#include <stdio.h>
#include <stdlib.h>

int main(void) {
    printf("Hello, World!\\\\n");
    return EXIT_SUCCESS;
}
' >src/main.c
    if test $status -ne 0
        cleanup_on_failure
        return 1
    end
    set -a created_items src/main.c

    echo "Creating test directory..."
    if not mkdir test
        cleanup_on_failure
        return 1
    end
    set -a created_items test

    echo "Creating build directory..."
    if not mkdir build
        cleanup_on_failure
        return 1
    end
    set -a created_items build

    echo "Creating test/test_main.c..."
    printf '#include <stdio.h>
#include <stdlib.h>
#include <assert.h>

// Simple test function
int test_basic_functionality(void) {
    // Basic assertion test
    assert(1 == 1);
    printf("test_basic_functionality: PASSED\\\\n");
    return 0;
}

int main(void) {
    printf("Running tests...\\\\n");

    test_basic_functionality();

    printf("All tests passed!\\\\n");
    return EXIT_SUCCESS;
}
' >test/test_main.c
    if test $status -ne 0
        cleanup_on_failure
        return 1
    end
    set -a created_items test/test_main.c

    # Create meson.build
    echo "Creating meson.build..."
    printf 'project(\'c_project\', \'c\',
  version: \'0.1.0\',
  default_options: [
    \'warning_level=3\',
    \'werror=false\'
  ])

cc = meson.get_compiler(\'c\')

c_flags = []

if cc.get_id() == \'gcc\'
  c_flags += [
    \'-Wall\',
    \'-Wextra\',
    \'-Wpedantic\',
    \'-Wformat=2\',
    \'-Wno-unused-parameter\',
    \'-Wshadow\',
    \'-Wwrite-strings\',
    \'-Wstrict-prototypes\',
    \'-Wold-style-definition\',
    \'-Wredundant-decls\',
    \'-Wnested-externs\',
    \'-Wmissing-include-dirs\',
    \'-Wjump-misses-init\'
  ]
elif cc.get_id() == \'clang\'
  c_flags += [
    \'-Wall\',
    \'-Wextra\',
    \'-Wpedantic\',
    \'-Wformat=2\',
    \'-Wno-unused-parameter\',
    \'-Wshadow\',
    \'-Wwrite-strings\',
    \'-Wstrict-prototypes\',
    \'-Wold-style-definition\',
    \'-Wredundant-decls\',
    \'-Wnested-externs\',
    \'-Wmissing-include-dirs\',
    \'-Wconditional-uninitialized\'
  ]
else
  error(\'Unsupported compiler: \' + cc.get_id() + \'. Only GCC and Clang are supported.\')
endif

add_project_arguments(c_flags, language: \'c\')

main_exe = executable(\'main\',
  \'src/main.c\',
  install: false)

test_exe = executable(\'test_main\',
  \'test/test_main.c\',
  install: false)

test(\'basic_test\', test_exe)

run_target(\'run\',
  command: main_exe)
' >meson.build
    if test $status -ne 0
        cleanup_on_failure
        return 1
    end
    set -a created_items meson.build

    echo ""
    echo "✅ C project scaffolded successfully!"
    echo ""
    echo "Next steps:"
    echo "1. nix develop                    # Enter the development environment"
    echo "2. meson setup build              # Setup build directory"
    echo "3. meson compile -C build         # Build the project"
    echo "4. meson compile -C build run     # Run the main executable"
    echo "5. meson test -C build            # Run tests"
    echo ""
    echo "Files created:"
    echo "- flake.nix (Nix development environment)"
    echo "- meson.build (Build configuration)"
    echo "- src/main.c (Main source file)"
    echo "- test/test_main.c (Test file)"

    return 0
end
mkc
