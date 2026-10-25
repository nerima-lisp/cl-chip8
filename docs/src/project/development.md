# Development

The project uses Nix for dependencies, tests, the executable, documentation,
and CI. The implementation targets SBCL on `x86_64-linux` and
`aarch64-darwin`.

## Layout

- `src/` contains machine state, platform profiles, CPU execution, ROM metadata, state transitions, terminal I/O, audio, and rendering.
- `t/` contains the test system, including Timendus checks and chip8Archive corpus compatibility checks.
- `run-tests.lisp` is the direct test entry point.
- `tools/coverage.lisp` runs coverage.
- `tools/generate-rom-database.lisp` regenerates the checked-in ROM database data.
- `bench/` contains the rendering benchmark.
- `docs/` contains the MkDocs site.

## Tests and checks

Enter the development shell to load the project dependencies and tools:

```sh
nix develop
```

The direct test runner is:

```sh
sbcl --script run-tests.lisp
```

The Timendus conformance specs require `CHIP8_TIMENDUS_DIR` to point at the
suite's `bin` directory. The Nix flake pins the
[Timendus v4.2 suite](https://github.com/Timendus/chip8-test-suite/tree/v4.2).
For a direct run, set the suite and optional chip8Archive paths:

```sh
CHIP8_TIMENDUS_DIR=/path/to/timendus/bin \
CL_CHIP8_ROM_CORPUS=/path/to/chip8Archive \
sbcl --script run-tests.lisp
```

`CHIP8_TIMENDUS_SKIP=1` explicitly skips the conformance specs for local runs
that are not checking conformance. The chip8Archive compatibility spec is
optional for a direct run. When enabled, it runs each discovered `.ch8` ROM
for 600 frames and reports compatibility faults. The test suite also runs
synthetic corpus discovery and fault-classification checks without an external
corpus.

The Nix flake check supplies both ROM collections, runs the test suite,
regenerates the database from its pinned source, and compares the result with
`src/rom-database-data.lisp`. It also runs the source parser check and package
build:

```sh
nix flake check
```

Run coverage with:

```sh
sbcl --script tools/coverage.lisp
```

The coverage gate uses expression and branch floors defined by the coverage
script. The realtime loop and key handling are exercised in-process. Tests do
not enter an actual terminal raw-mode session; that setup is outside the
automated test scope. The script's report describes the measured forms and
tracked gaps.

Build the documentation with:

```sh
nix build .#docs
```

The documentation build uses MkDocs strict mode, so broken links and missing
navigation entries fail the build.

## Benchmark

The renderer benchmark compares serial and concurrent output and records
host-specific timings:

```sh
sbcl --script bench/render.lisp
```

This guide documents the command, not benchmark results. Keep measurements
with the host and revision used to produce them before making comparisons.
