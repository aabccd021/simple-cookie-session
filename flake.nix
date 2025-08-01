{

  nixConfig.allow-import-from-derivation = false;

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  inputs.treefmt-nix.url = "github:numtide/treefmt-nix";
  inputs.bun2nix.url = "github:baileyluTCD/bun2nix";
  inputs.netero-test.url = "github:aabccd021/netero-test";

  outputs =
    { self, ... }@inputs:
    let
      lib = inputs.nixpkgs.lib;

      collectInputs =
        is:
        pkgs.linkFarm "inputs" (
          builtins.mapAttrs (
            name: i:
            pkgs.linkFarm name {
              self = i.outPath;
              deps = collectInputs (lib.attrByPath [ "inputs" ] { } i);
            }
          ) is
        );

      pkgs = import inputs.nixpkgs {
        system = "x86_64-linux";
        overlays = [
          inputs.netero-test.overlays.default
        ];
      };

      bunNix = import ./bun.nix;

      nodeModules = inputs.bun2nix.lib.x86_64-linux.mkBunNodeModules {
        packages = bunNix;
      };

      treefmtEval = inputs.treefmt-nix.lib.evalModule pkgs {
        projectRootFile = "flake.nix";
        programs.prettier.enable = true;
        programs.nixfmt.enable = true;
        programs.biome.enable = true;
        programs.shfmt.enable = true;
        settings.formatter.prettier.priority = 1;
        settings.formatter.biome.priority = 2;
        settings.global.excludes = [
          "LICENSE"
          "*.ico"
        ];
      };

      formatter = treefmtEval.config.build.wrapper;

      check-tsc = pkgs.runCommand "tsc" { } ''
        cp -L ${./index.ts} ./index.ts
        cp -L ${./tsconfig.json} ./tsconfig.json
        cp -Lr ${./test} ./test
        cp -Lr ${nodeModules}/node_modules ./node_modules
        ${lib.getExe pkgs.typescript}
        touch $out
      '';

      check-biome = pkgs.runCommand "biome" { } ''
        cp -L ${./biome.jsonc} ./biome.jsonc
        cp -L ${./index.ts} ./index.ts
        cp -Lr ${./test} ./test
        cp -L ${./package.json} ./package.json
        cp -L ${./tsconfig.json} ./tsconfig.json
        cp -Lr ${nodeModules}/node_modules ./node_modules
        ${lib.getExe pkgs.biome} check --error-on-warnings
        touch $out
      '';

      tests = import ./test {
        pkgs = pkgs;
        nodeModules = nodeModules;
      };

      publish = pkgs.writeShellApplication {
        name = "publish";
        runtimeInputs = [ pkgs.bun ];
        text = ''
          repo_root=$(git rev-parse --show-toplevel)
          export NPM_CONFIG_USERCONFIG="$repo_root/.npmrc"
          if [ ! -f "$NPM_CONFIG_USERCONFIG" ]; then
            bunx npm login
          fi
          nix flake check
          bun publish
        '';
      };

      devShells.default = pkgs.mkShellNoCC {
        buildInputs = [
          pkgs.bun
          pkgs.biome
          pkgs.typescript
          pkgs.vscode-langservers-extracted
          pkgs.nixd
          pkgs.typescript-language-server
        ];
      };

      packages =
        tests
        // devShells
        // {
          publish = publish;
          tests = pkgs.linkFarm "tests" tests;
          formatting = treefmtEval.config.build.check self;
          formatter = formatter;
          allInputs = collectInputs inputs;
          check-tsc = check-tsc;
          check-biome = check-biome;
          nodeModules = nodeModules;
          bun2nix = inputs.bun2nix.packages.x86_64-linux.default;
        };

    in
    {

      packages.x86_64-linux = packages // {
        gcroot = pkgs.linkFarm "gcroot" packages;
      };

      checks.x86_64-linux = packages;
      formatter.x86_64-linux = formatter;
      devShells.x86_64-linux = devShells;

    };
}
