# cl-chip8

[![CI](https://github.com/nerima-lisp/cl-chip8/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/nerima-lisp/cl-chip8/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Documentation](https://img.shields.io/badge/docs-MkDocs%20Material-0a7a5a)](https://nerima-lisp.github.io/cl-chip8/)

`cl-chip8` is an SBCL-only [CHIP-8](https://en.wikipedia.org/wiki/CHIP-8)
interpreter for the terminal. It implements the original instruction set with
a fixed modern compatibility profile and uses a `cl-prolog` rulebase for CPU
state and instruction dispatch.

Full documentation is published at <https://nerima-lisp.github.io/cl-chip8/>.
The source for that site lives in [docs/src/](docs/src/).

## Quick Start

From a checkout with Nix installed. The flake declares outputs for
`x86_64-linux` only, so every `nix` command in this README fails on any other
system -- on macOS with `does not provide attribute
'packages.aarch64-darwin.<name>'`. On those hosts, build and run through SBCL
and ASDF directly, or use a `x86_64-linux` remote builder.

```shell
nix run .#cl-chip8 -- path/to/rom.ch8
```

The emulator runs in the terminal until Escape or Ctrl-C. Use
`--clock-hz <positive-integer>` to select the instruction rate; timers remain
at the CHIP-8 rate of 60 Hz.

## Install

Consume the released tag, following the consumer's own `nixpkgs` input:

```nix
inputs.cl-chip8 = {
  url = "github:nerima-lisp/cl-chip8/v0.1.0";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

For development against an unreleased change, swap the `url` for
`path:../cl-chip8` and point it at a local checkout.

The library system is `cl-chip8`. Load it with ASDF and call `cl-chip8:run`,
whose arguments are all keywords:

```lisp
(asdf:load-system "cl-chip8")
(cl-chip8:run :rom-path #p"path/to/rom.ch8")
```

Three things to know before calling it. `run` needs a live terminal: it enters
raw mode on the alternate screen, so it is not usable from a script with
redirected I/O. It resets all global machine state -- CPU, memory, display,
fontset, keypad -- on entry, so it is not re-entrant. It returns the
`chip8-app` struct rather than signaling execution errors; an error raised by
a ROM is stored on that struct and read back with `cl-chip8:chip8-app-error`.

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
workflow is `sbcl --script tools/coverage.lisp`. See the [development
guide](docs/src/project/development.md) for source layout, dependency setup,
and verification details.

## Contributing

Keep implementation, public API documentation, and compatibility behavior in
sync. Run the relevant test and documentation checks before opening a change.
See the org-wide [contributing guide](https://github.com/nerima-lisp/.github/blob/main/CONTRIBUTING.md)
and [package standard](https://github.com/nerima-lisp/.github/blob/main/PACKAGE_STANDARD.md).

## Support

See the org-wide [support guide](https://github.com/nerima-lisp/.github/blob/main/SUPPORT.md).

## License

MIT. See [LICENSE](LICENSE).
