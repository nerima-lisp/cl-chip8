{
  description = "A CHIP-8 (1977 COSMAC VIP instruction set) interpreter for the terminal.";

  inputs = {
    # nixos-unstable, not nixpkgs-unstable: it advances only after the NixOS
    # release tests pass, so it is less likely to land a broken build.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # The org flake preset. The single `mkPackageFlake` call below generates
    # this repository's entire required-output table, so none of it is spelled
    # out here and none of it can drift from the other repositories.
    cl-nix-forge = {
      url = "github:nerima-lisp/cl-nix-forge/v0.5.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Sibling packages are ALWAYS pinned to a release tag; a bare
    # `github:nerima-lisp/<pkg>` follows that repo's default branch, which
    # would break this repo's CI without warning the moment upstream pushes to
    # main. `flake = false`: only the source tree is needed (to build a
    # `lispDerivation` below), never these repos' own flake outputs -- see
    # DEPENDENCY_POLICY.md "姉妹パッケージは flake = false で引きます".
    cl-prolog = {
      url = "github:nerima-lisp/cl-prolog/v1.4.3";
      flake = false;
    };

    cl-tty-kit = {
      url = "github:nerima-lisp/cl-tty-kit/v1.5.0";
      flake = false;
    };

    cl-cli = {
      url = "github:nerima-lisp/cl-cli/v1.3.0";
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
      url = "github:nerima-lisp/cl-date-kit/v1.0.0";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.cl-nix-forge.follows = "cl-nix-forge";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    # Transitive sibling dependencies of cl-tty-kit, cl-cli, and
    # cl-concurrent-kit above. Nix builds each lispDerivation as its own
    # sandboxed derivation, so every nested ASDF :depends-on must be satisfied
    # by the owning lispDerivation's lispDependencies list -- flattening every
    # sibling into this repository's own list would not reach a nested build.
    cl-codec-kit = {
      url = "github:nerima-lisp/cl-codec-kit/v0.5.0";
      flake = false;
    };

    cl-host-kit = {
      url = "github:nerima-lisp/cl-host-kit/v0.3.1";
      flake = false;
    };

    cl-weave = {
      url = "github:nerima-lisp/cl-weave/v1.3.0";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.cl-nix-forge.follows = "cl-nix-forge";
      inputs.paredit-cli.follows = "paredit-cli";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    # Unlike the sibling *packages* above, this is consumed for its `lib`
    # output (`mkLintCheck`), which a `flake = false` source tree cannot
    # provide -- the same reason cl-nix-forge stays a real flake input.
    paredit-cli = {
      url = "github:nerima-lisp/paredit-cli/v1.6.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      cl-nix-forge,
      cl-prolog,
      cl-tty-kit,
      cl-cli,
      cl-concurrent-kit,
      cl-boundary-kit,
      cl-date-kit,
      cl-codec-kit,
      cl-host-kit,
      cl-weave,
      paredit-cli,
      treefmt-nix,
    }:
    let
      # x86_64-linux only, full stop. PACKAGE_STANDARD.md's "systems" section
      # (2026-08-01 revision) retracted the earlier two-system list org-wide:
      # declaring aarch64-darwin promises a platform whose only verification
      # was a developer remembering to run `nix flake check` by hand, which is
      # not a gate. Every per-system output -- packages, checks, apps AND
      # devShells -- comes from this one list (mkPackageFlake's
      # `lib.genAttrs systems`), so this also removes `nix build` and
      # `nix develop` on macOS; that is the accepted cost, not an oversight.
      # aarch64-linux and x86_64-darwin were never declared at all.
      systems = [ "x86_64-linux" ];
    in
    cl-nix-forge.lib.${builtins.head systems}.mkPackageFlake {
      inherit self systems nixpkgs;

      pname = "cl-chip8";

      # Single source of truth for the version: the `:version` form in
      # cl-chip8.asd.
      asd = ./cl-chip8.asd;

      root = ./.;

      meta = {
        description = "A CHIP-8 (1977 COSMAC VIP instruction set) interpreter for the terminal.";
        homepage = "https://github.com/nerima-lisp/cl-chip8";
        license = nixpkgs.lib.licenses.mit;
        platforms = nixpkgs.lib.platforms.unix;
      };

      # Runtime dependencies: cl-chip8's own :DEPENDS-ON. These are BUILT
      # DERIVATIONS, not CL_SOURCE_REGISTRY strings -- cl-nix-forge assembles
      # the registry transitively from them. Each nested ASDF dependency is
      # represented by a local derivation so the same source/version is shared
      # across the graph rather than importing a sibling flake's prebuilt
      # output (which can introduce duplicate source identities).
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
        in
        [
          (ctx.cl.lispDerivation {
            pname = "cl-prolog";
            version = ctx.cl.fromAsdSystem "${cl-prolog}/cl-prolog.asd";
            src = cl-prolog;
            lispSystem = "cl-prolog";
          })
          (ctx.cl.lispDerivation {
            pname = "cl-tty-kit";
            version = ctx.cl.fromAsdSystem "${cl-tty-kit}/cl-tty-kit.asd";
            src = cl-tty-kit;
            lispSystem = "cl-tty-kit";
            # cl-tty-kit v1.5.0 declares :depends-on ("cl-codec-kit"
            # "cl-concurrent-kit"); the concurrent-kit entry is newer than the
            # pin this list was written against. Each lispDerivation builds in
            # its own sandbox, so a nested :depends-on that is missing here is
            # simply absent at build time -- and the local
            # `sbcl --script run-tests.lisp` cannot catch it, because that
            # registers a flat (:tree ../) registry in which every sibling
            # resolves regardless of what this list says.
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
          # cl-chip8.asd names "cl-host-kit" in its own :depends-on, so it
          # belongs at THIS level and not only nested inside cl-cli's
          # derivation above. A nested entry satisfies cl-cli's sandbox, not
          # cl-chip8's, and run-tests.lisp additionally loads the system by
          # name before it runs the suite.
          hostKit
        ];

      # Test-only: cl-weave, the org's test framework.
      lispCheckDependencies = ctx: [
        (ctx.cl.lispDerivation {
          pname = "cl-weave";
          version = ctx.cl.fromAsdSystem "${cl-weave}/cl-weave.asd";
          src = cl-weave;
          lispSystem = "cl-weave";
        })
      ];

      # The delivered `cl-chip8` binary: `packages.default`, `apps.default`
      # and `apps.cl-chip8`, all built from the `:build-operation` /
      # `:build-pathname` / `:entry-point` already declared in cl-chip8.asd --
      # nothing here repeats them. `programPath` is left at its default (the
      # ASDF system name): cl-chip8.asd combines `:pathname "src"` with
      # `:build-pathname "cl-chip8"` exactly the way cl-nyancat.asd does, and
      # cl-nyancat's own flake.nix needs no explicit `programPath` either, so
      # this repository does not need one spelled out here -- see
      # cl-nix-forge's lib/batteries/app.nix, whose `mkExecutable` places the
      # built program directly under `$out/<lispSystem>` regardless of the
      # system's own `:pathname`. installSource lets the delivered binary
      # find its own installed ASDF sources when it needs to re-resolve
      # itself, which is what makes `cl-chip8 --version` report the .asd's
      # :version rather than the 0.0.0 fallback in src/cli.lisp.
      executable = {
        installSource = true;
      };

      docs.root = ./docs;

      # ONE treefmt evaluation drives both `nix fmt` and `checks.formatting`.
      # Scope stays the preset's default of Nix only.
      treefmt.evalModule = treefmt-nix.lib.evalModule;

      # Granularity lives here, not in an extra GitHub Actions job: `nix flake
      # check` evaluates each attribute as its own derivation, in parallel,
      # with build caching -- see cl-nyancat's flake.nix, which this follows.
      extraOutputs = ctx: {
        checks = {
          # Structural parse gate over every Lisp source in the filtered tree:
          # fails if any .lisp/.asd file is not a balanced S-expression
          # document. The test suite would not catch it -- an unbalanced file
          # makes ASDF fail to load the system, which reads like any other
          # build error and points at the wrong cause.
          paredit-lint = paredit-cli.lib.${ctx.system}.mkLintCheck {
            inherit (ctx) src;
            name = "cl-chip8-paredit-lint";
          };

          # PACKAGE_STANDARD.md requires the delivered binary itself to be
          # part of `nix flake check`'s gate, not just the library derivation
          # `checks.default`'s run-tests.lisp already exercises -- see
          # nshell's flake.nix, whose `checks.build = delivery;` this
          # mirrors. `ctx.executable` is exactly the `executable` block above,
          # built.
          build = ctx.executable;
        };
      };
    };
}
