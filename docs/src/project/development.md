# Development

The repository uses its Nix flake for dependencies, tests, the executable,
documentation, and CI checks. The implementation is SBCL-only.

## Repository layout

- `src/` contains the interpreter and terminal runtime.
- `t/` contains the `cl-weave` test system.
- `run-tests.lisp` is the direct test entry point.
- `tools/coverage.lisp` runs the coverage workflow.
- `bench/` contains the render benchmark script.
- `docs/` contains this MkDocs site.

The ASDF file defines the `cl-chip8` system and its `cl-chip8/test` test
system. Runtime dependencies and pinned development inputs are declared in
`flake.nix`.

## Reproducible workflow

From the repository root, the standard Nix workflow is:

```shell
nix develop
nix run .#test
nix run .#cl-chip8 -- path/to/rom.ch8
nix build .#docs --print-build-logs
nix flake check --print-build-logs
nix fmt
```

The flake currently declares `x86_64-linux` outputs. On another host, make the
pinned sibling dependencies available in the expected `CL_SOURCE_REGISTRY`
tree and use the direct SBCL commands below.

## Updating pinned inputs

`flake.lock` records the exact revisions used by the Nix workflow. Update only
the inputs intended for the change, then review the lock diff and rerun the
repository checks:

```shell
nix flake update nixpkgs treefmt-nix
git diff -- flake.lock
nix flake check --print-build-logs
nix build .#docs --print-build-logs
git diff --check
```

Keep the lock diff limited to the requested inputs. The Nix checks and docs
build use the `x86_64-linux` outputs described above.

## Tests and coverage

Run the test system directly with:

```shell
sbcl --script run-tests.lisp
```

The coverage workflow is:

```shell
sbcl --script tools/coverage.lisp
```

It writes the generated report under `coverage/`. The source selection and
coverage thresholds are defined in `tools/coverage.lisp`; keep those rules
explicit when interpreting a result.

## Render benchmark

`bench/render.lisp` times the baseline, partial-serial, and concurrent render
paths across four fixed fixtures of increasing dirty-row count:

```shell
sbcl --script bench/render.lisp
```

Four environment variables tune the run. Each falls back to its default when
unset or unparseable, and any value below 1 is clamped to 1:

| Variable | Default | Effect |
|---|---|---|
| `CL_CHIP8_BENCH_WARMUP` | 5 | Warm-up iterations discarded before timing. |
| `CL_CHIP8_BENCH_ITERATIONS` | 2000 | Timed iterations per path. |
| `CL_CHIP8_BENCH_PARALLEL_THRESHOLD` | 13 | Dirty-row count at which the concurrent path becomes eligible. |
| `CL_CHIP8_BENCH_PARALLELISM` | 4 | Worker count for the pipeline under test. |

Treat the output as a local measurement, not a published figure. The result
depends on the host, its core count, and the load on it at the time, so a
number from one machine does not carry to another. Run the benchmark before and
after a change on the same machine and compare those two runs.

The benchmark also compares every selected renderer's screen with the
baseline, so a timing improvement is useful only when the output comparison
passes. `submitted=0` is a valid result: full dirty frames and partial frames
below the eligibility gates intentionally use the serial path. For a change
to display or rendering code, inspect both the equality checks and the
`submitted`/`completed`/`serial` counters instead of treating a reported
speedup as universal.

When run from a linked Git worktree, the benchmark resolves that checkout
first and searches nearby sibling checkout roots for the pinned Lisp
dependencies. Set `CL_SOURCE_REGISTRY` explicitly when the dependencies live
elsewhere.

## Documentation checks

Build the site through the flake with:

```shell
nix build .#docs --print-build-logs
```

The MkDocs configuration uses strict mode. Keep all public symbols, examples,
compatibility decisions, and navigation entries synchronized with the source.
Use `--print-build-logs` (or its `-L` shorthand) to stream build logs while
diagnosing a documentation failure.
Use `git diff --check` to catch whitespace errors before submitting a change.
