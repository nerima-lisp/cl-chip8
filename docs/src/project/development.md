# Development

The project uses Nix for dependencies, tests, the executable, documentation,
and CI. The implementation targets SBCL on `x86_64-linux` and
`aarch64-darwin`.

## Layout

- `src/` contains machine state, CPU execution, state transitions, terminal I/O, and rendering.
- `t/` contains the test system.
- `run-tests.lisp` is the direct test entry point.
- `tools/coverage.lisp` runs coverage.
- `bench/` contains the rendering benchmark.
- `docs/` contains the MkDocs site.

## Tests and checks

Run the direct suite with an explicit time limit:

```sh
timeout 900 sbcl --script run-tests.lisp
```

The Timendus ROM directory is supplied through `CHIP8_TIMENDUS_DIR`, and the
chip8Archive checkout root (including `programs.json`) through
`CL_CHIP8_ROM_CORPUS`. The corpus is required by the test suite; only local
development may explicitly skip it with `CL_CHIP8_ROM_CORPUS_SKIP=1`. When
dependencies are outside the Nix shell, set `CL_SOURCE_REGISTRY` to the parent
tree containing the checkout and its sibling systems:

CI sets `CL_CHIP8_ROM_CORPUS_BUDGET=200` so the complete corpus stays within
the six-minute test timeout. Local runs may override that budget when a longer
smoke run is useful.

```sh
CHIP8_TIMENDUS_DIR=/path/to/timendus \
CL_CHIP8_ROM_CORPUS=/path/to/chip8Archive \
timeout 900 sbcl --script run-tests.lisp
```

To run local tests without downloading the corpus, opt out explicitly:

```sh
CL_CHIP8_ROM_CORPUS_SKIP=1 timeout 900 sbcl --script run-tests.lisp
```

Run coverage with a time limit:

```sh
timeout 1800 sbcl --script tools/coverage.lisp
```

Coverage currently reports 78.02% expression coverage and 65.00% branch
coverage, with stable integer floors of 78% and 65%. The current run reports
439 tracked executable gaps across 28 measured source reports. The runtime
terminal loop is outside the automated test scope; key handling is verified by
in-process tests. The detailed per-form gap classification and the opcode
macro-expansion evidence are maintained in `tools/coverage.lisp`; the coverage
log prints every tracked gap.
The aggregate floors are the CI gate.

Run the flake checks and documentation build with:

```sh
timeout 1800 nix flake check
timeout 900 nix build .#docs
```

The documentation build uses MkDocs strict mode, so broken links and missing
navigation entries fail the build.

## Benchmark

The renderer benchmark compares serial and concurrent output as well as timing:

```sh
timeout 900 sbcl --script bench/render.lisp
```

Treat timings as host-specific measurements. A useful change must preserve the
renderer output comparison as well as the measured performance.
