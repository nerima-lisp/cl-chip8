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

The Timendus ROM directory is supplied through `CHIP8_TIMENDUS_DIR`. When
dependencies are outside the Nix shell, set `CL_SOURCE_REGISTRY` to the parent
tree containing the checkout and its sibling systems:

```sh
CHIP8_TIMENDUS_DIR=/path/to/timendus timeout 900 sbcl --script run-tests.lisp
```

Run coverage with a time limit:

```sh
timeout 1800 sbcl --script tools/coverage.lisp
```

Coverage currently reports 78.02% expression coverage and 65.00% branch
coverage, with stable integer floors of 78% and 65%. The current run reports
439 tracked executable gaps across 28 measured source reports. The detailed
per-form gap classification and the opcode macro-expansion evidence are
maintained in `tools/coverage.lisp`; the coverage log prints every tracked gap.
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
