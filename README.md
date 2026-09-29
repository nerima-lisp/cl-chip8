# cl-chip8

[![CI](https://github.com/nerima-lisp/cl-chip8/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/nerima-lisp/cl-chip8/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Documentation](https://img.shields.io/badge/docs-MkDocs%20Material-0a7a5a)](https://nerima-lisp.github.io/cl-chip8/)

`cl-chip8` is an SBCL-only [CHIP-8](https://en.wikipedia.org/wiki/CHIP-8)
interpreter for the terminal. Version 0.2.0 provides a typed machine-state
API, a terminal application, configurable compatibility profiles, TOML
configuration, logging, metrics, and headless execution helpers.

Full documentation is published at <https://nerima-lisp.github.io/cl-chip8/>.
The source for that site lives in [docs/src/](docs/src/).

## Quick Start

From a checkout with Nix installed:

```shell
nix run .#cl-chip8 -- path/to/rom.ch8
```

The emulator runs in the terminal until Escape or Ctrl-C. Use
`--clock-hz <positive-integer>` to choose the instruction rate. Delay and sound
timers continue at the CHIP-8 rate of 60 Hz. Use `--help` to list all command
line options, including `--quirks`, `--config`, and `--log`.

The flake provides packages for `x86_64-linux` and `aarch64-darwin`. On other
systems, build and run through SBCL and ASDF directly or use a Nix remote
builder.

## Install

Consume the released tag from another flake:

```nix
inputs.cl-chip8 = {
  url = "github:nerima-lisp/cl-chip8/v0.2.0";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

For development against an unreleased change, use
`path:../cl-chip8` and point it at a local checkout.

The library system is `cl-chip8`. Load it with ASDF and call `cl-chip8:run`:

```lisp
(asdf:load-system "cl-chip8")
(cl-chip8:run :rom-path #p"path/to/rom.ch8")
```

`run` accepts keyword arguments, including `:rom-path`, `:clock-hz`,
`:quirks`, and `:stream`. It creates and initializes a machine, loads the ROM,
then enters a raw-mode terminal session on the alternate screen. It returns a
`chip8-app` after the session ends. Runtime errors captured by the application
are available through `cl-chip8:chip8-app-error`; ROM loading errors occur
before the terminal session starts.

## Documentation

- [Getting Started](https://nerima-lisp.github.io/cl-chip8/getting-started/)
- [API Reference](https://nerima-lisp.github.io/cl-chip8/reference/api/)
- [Architecture](https://nerima-lisp.github.io/cl-chip8/reference/architecture/)
- [Compatibility](https://nerima-lisp.github.io/cl-chip8/reference/compatibility/)

## Development

```shell
nix develop
nix run .#test
nix build .#docs --print-build-logs
nix flake check --print-build-logs
nix fmt
git diff --check
```

The direct test runner is `sbcl --script run-tests.lisp`; the coverage
workflow is `sbcl --script tools/coverage.lisp`. See the
[development guide](docs/src/project/development.md) for source layout,
dependency setup, and verification details.

## Contributing

Keep implementation, public API documentation, and compatibility behavior in
sync. Run the relevant test and documentation checks before opening a change.
See the org-wide [contributing guide](https://github.com/nerima-lisp/.github/blob/main/CONTRIBUTING.md)
and [package standard](https://github.com/nerima-lisp/.github/blob/main/PACKAGE_STANDARD.md).

## Support

See the org-wide [support guide](https://github.com/nerima-lisp/.github/blob/main/SUPPORT.md).

## License

MIT. See [LICENSE](LICENSE).
