# Development

The repository uses its Nix flake for dependencies, tests, the executable,
documentation, and CI checks. The implementation is SBCL-only.

## Repository layout

- `src/` contains the interpreter and terminal runtime.
- `t/` contains the `cl-weave` test system.
- `run-tests.lisp` is the direct test entry point.
- `tools/coverage.lisp` runs the coverage workflow.
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

## Documentation checks

Build the site through the flake with:

```shell
nix build .#docs --print-build-logs
```

The MkDocs configuration uses strict mode. Keep all public symbols, examples,
compatibility decisions, and navigation entries synchronized with the source.
Use `git diff --check` to catch whitespace errors before submitting a change.
