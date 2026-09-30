{
  description = "A CHIP-8 (1977 COSMAC VIP instruction set) interpreter for the terminal.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    cl-nix-forge = {
      url = "github:nerima-lisp/cl-nix-forge/v0.6.1";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    cl-tty-kit = {
      url = "github:nerima-lisp/cl-tty-kit/v1.6.1";
      flake = false;
    };

    cl-cli = {
      url = "github:nerima-lisp/cl-cli/v1.4.0";
      flake = false;
    };

    cl-concurrent-kit = {
      url = "github:nerima-lisp/cl-concurrent-kit/v0.6.1";
      flake = false;
    };

    cl-boundary-kit = {
      url = "github:nerima-lisp/cl-boundary-kit/v2.3.0";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.cl-weave.follows = "cl-weave";
      inputs.cl-nix-forge.follows = "cl-nix-forge";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    cl-date-kit = {
      url = "github:nerima-lisp/cl-date-kit/v1.1.1";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.cl-nix-forge.follows = "cl-nix-forge";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    cl-codec-kit = {
      url = "github:nerima-lisp/cl-codec-kit/v0.6.0";
      flake = false;
    };

    cl-host-kit = {
      url = "github:nerima-lisp/cl-host-kit/v0.3.1";
      flake = false;
    };

    cl-json-kit = {
      url = "github:nerima-lisp/cl-json-kit/v1.2.0";
      flake = false;
    };

    cl-weave = {
      url = "github:nerima-lisp/cl-weave/v1.3.0";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.cl-nix-forge.follows = "cl-nix-forge";
      inputs.paredit-cli.follows = "paredit-cli";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    paredit-cli = {
      url = "github:nerima-lisp/paredit-cli/v1.6.3";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    cl-parser-kit = {
      url = "github:nerima-lisp/cl-parser-kit/v1.1.1";
      flake = false;
    };

    cl-log-kit = {
      url = "github:nerima-lisp/cl-log-kit/v2.2.0";
      flake = false;
    };

    cl-toml-kit = {
      url = "github:nerima-lisp/cl-toml-kit/v0.1.0";
      flake = false;
    };

    cl-observability-kit = {
      url = "github:nerima-lisp/cl-observability-kit/v1.0.0";
      flake = false;
    };

    cl-prolog-kit = {
      url = "github:nerima-lisp/cl-prolog-kit/v1.5.0";
      flake = false;
    };

    cl-dataflow-kit = {
      url = "github:nerima-lisp/cl-dataflow-kit/v1.2.0";
      flake = false;
    };

    timendus-chip8-test-suite = {
      url = "github:Timendus/chip8-test-suite/v4.2";
      flake = false;
    };

    chip8-archive = {
      url = "github:JohnEarnest/chip8Archive";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      cl-nix-forge,
      cl-tty-kit,
      cl-cli,
      cl-concurrent-kit,
      cl-boundary-kit,
      cl-date-kit,
      cl-codec-kit,
      cl-host-kit,
      cl-json-kit,
      cl-weave,
      paredit-cli,
      treefmt-nix,
      cl-parser-kit,
      cl-log-kit,
      cl-toml-kit,
      cl-observability-kit,
      cl-dataflow-kit,
      cl-prolog-kit,
      timendus-chip8-test-suite,
      chip8-archive,
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];
    in
    cl-nix-forge.lib.${builtins.head systems}.mkPackageFlake {
      inherit self systems nixpkgs;

      pname = "cl-chip8";

      asd = ./cl-chip8.asd;

      root = ./.;

      sourceInclude = [ ./t/timendus.snapshots ];

      meta = {
        description = "A CHIP-8 (1977 COSMAC VIP instruction set) interpreter for the terminal.";
        homepage = "https://github.com/nerima-lisp/cl-chip8";
        license = nixpkgs.lib.licenses.mit;
        platforms = nixpkgs.lib.platforms.unix;
      };

      lispDependencies =
        ctx:
        let
          codecKit = ctx.cl.lispDerivation {
            pname = "cl-codec-kit";
            version = ctx.cl.fromAsdSystem "${cl-codec-kit}/cl-codec-kit.asd";
            src = cl-codec-kit;
            lispSystem = "cl-codec-kit";
          };
          hostKit = ctx.cl.lispDerivation {
            pname = "cl-host-kit";
            version = ctx.cl.fromAsdSystem "${cl-host-kit}/cl-host-kit.asd";
            src = cl-host-kit;
            lispSystem = "cl-host-kit";
          };
          jsonKit = ctx.cl.lispDerivation {
            pname = "cl-json-kit";
            version = ctx.cl.fromAsdSystem "${cl-json-kit}/cl-json-kit.asd";
            src = cl-json-kit;
            lispSystem = "cl-json-kit";
          };
          boundaryKit = ctx.cl.lispDerivation {
            pname = "cl-boundary-kit";
            version = ctx.cl.fromAsdSystem "${cl-boundary-kit}/cl-boundary-kit.asd";
            src = cl-boundary-kit;
            lispSystem = "cl-boundary-kit";
            lispDependencies = [ hostKit ];
          };
          dateKit = ctx.cl.lispDerivation {
            pname = "cl-date-kit";
            version = ctx.cl.fromAsdSystem "${cl-date-kit}/cl-date-kit.asd";
            src = cl-date-kit;
            lispSystem = "cl-date-kit";
          };
          concurrentKit = ctx.cl.lispDerivation {
            pname = "cl-concurrent-kit";
            version = ctx.cl.fromAsdSystem "${cl-concurrent-kit}/cl-concurrent-kit.asd";
            src = cl-concurrent-kit;
            lispSystem = "cl-concurrent-kit";
            lispDependencies = [
              boundaryKit
              dateKit
            ];
          };
          parserKit = ctx.cl.lispDerivation {
            pname = "cl-parser-kit";
            version = ctx.cl.fromAsdSystem "${cl-parser-kit}/cl-parser-kit.asd";
            src = cl-parser-kit;
            lispSystem = "cl-parser-kit";
          };
          logKit = ctx.cl.lispDerivation {
            pname = "cl-log-kit";
            version = ctx.cl.fromAsdSystem "${cl-log-kit}/cl-log-kit.asd";
            src = cl-log-kit;
            lispSystem = "cl-log-kit";
            lispDependencies = [
              dateKit
              concurrentKit
              hostKit
            ];
          };
          tomlKit = ctx.cl.lispDerivation {
            pname = "cl-toml-kit";
            version = ctx.cl.fromAsdSystem "${cl-toml-kit}/cl-toml-kit.asd";
            src = cl-toml-kit;
            lispSystem = "cl-toml-kit";
            lispDependencies = [
              parserKit
              dateKit
            ];
          };
          observabilityKit = ctx.cl.lispDerivation {
            pname = "cl-observability-kit";
            version = ctx.cl.fromAsdSystem "${cl-observability-kit}/cl-observability-kit.asd";
            src = cl-observability-kit;
            lispSystem = "cl-observability-kit";
            lispDependencies = [
              concurrentKit
              boundaryKit
            ];
          };
          prologKit = ctx.cl.lispDerivation {
            pname = "cl-prolog-kit";
            version = ctx.cl.fromAsdSystem "${cl-prolog-kit}/cl-prolog-kit.asd";
            src = cl-prolog-kit;
            lispSystem = "cl-prolog-kit";
          };
          dataflowKit = ctx.cl.lispDerivation {
            pname = "cl-dataflow-kit";
            version = ctx.cl.fromAsdSystem "${cl-dataflow-kit}/cl-dataflow-kit.asd";
            src = cl-dataflow-kit;
            lispSystem = "cl-dataflow-kit";
            lispDependencies = [
              prologKit
              concurrentKit
            ];
          };
        in
        [
          prologKit
          dataflowKit
          (ctx.cl.lispDerivation {
            pname = "cl-tty-kit";
            version = ctx.cl.fromAsdSystem "${cl-tty-kit}/cl-tty-kit.asd";
            src = cl-tty-kit;
            lispSystem = "cl-tty-kit";
            lispDependencies = [
              codecKit
              concurrentKit
            ];
          })
          (ctx.cl.lispDerivation {
            pname = "cl-cli";
            version = ctx.cl.fromAsdSystem "${cl-cli}/cl-cli.asd";
            src = cl-cli;
            lispSystem = "cl-cli";
            lispDependencies = [ hostKit ];
          })
          dateKit
          concurrentKit
          hostKit
          jsonKit
          logKit
          tomlKit
          observabilityKit
          parserKit
        ];

      lispCheckDependencies = ctx: [
        (ctx.cl.lispDerivation {
          pname = "cl-weave";
          version = ctx.cl.fromAsdSystem "${cl-weave}/cl-weave.asd";
          src = cl-weave;
          lispSystem = "cl-weave";
        })
      ];

      executable = {
        installSource = true;
        programPath = "src/cl-chip8";
      };

      timeoutSeconds = 1200;
      killAfterSeconds = 30;

      docs.root = ./docs;

      treefmt.evalModule = treefmt-nix.lib.evalModule;

      extraOutputs = ctx: {
        packages.timendus = ctx.pkgs.runCommand "timendus-chip8-test-suite" { } ''
          cp -r ${timendus-chip8-test-suite} "$out"
        '';
        packages.chip8-archive = ctx.pkgs.runCommand "chip8-archive" { } ''
          cp -r ${chip8-archive} "$out"
        '';
        checks = {
          paredit-lint = paredit-cli.lib.${ctx.system}.mkLintCheck {
            inherit (ctx) src;
            name = "cl-chip8-paredit-lint";
          };

          build = ctx.executable;
        };
      };

      overrideOutputs = ctx: {
        checks.default = ctx.generated.checks.default.overrideAttrs (old: {
          preCheck = (old.preCheck or "") + ''
            export CHIP8_TIMENDUS_DIR=${timendus-chip8-test-suite}/bin
            export CL_CHIP8_ROM_CORPUS=${chip8-archive}
            export CL_CHIP8_ROM_CORPUS_BUDGET=200
          '';
        });
      };
    };
}
