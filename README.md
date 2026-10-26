# cl-chip8

[![CI](https://github.com/nerima-lisp/cl-chip8/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/nerima-lisp/cl-chip8/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Documentation](https://img.shields.io/badge/docs-MkDocs%20Material-0a7a5a)](https://nerima-lisp.github.io/cl-chip8/)

`cl-chip8` is an SBCL-only [CHIP-8](https://en.wikipedia.org/wiki/CHIP-8)
interpreter for the terminal. The current development tree supports CHIP-8,
SUPER-CHIP, and XO-CHIP platform profiles, ROM-specific compatibility data,
TOML configuration, structured logging, metrics, PCM or terminal-bell audio,
and headless execution helpers.

Full documentation is published at <https://nerima-lisp.github.io/cl-chip8/>.
The source for that site lives in [docs/src/](docs/src/).

## Quick Start

From a checkout with Nix installed:

```shell
nix run .#cl-chip8 -- path/to/rom.ch8
```

The emulator runs in the terminal until Escape or Ctrl-C. Use `--platform` to
select a machine profile, `--quirks` to select compatibility behavior, and
`--clock-hz` to set the instruction rate. Delay and sound timers continue at
60 Hz. `--audio` selects PCM, terminal-bell, automatic fallback, or no audio;
`--colors-pixels` overrides the pixel palette. Use `--config` for TOML settings
and `--help` to list every command-line option.

The flake provides packages for `x86_64-linux` and `aarch64-darwin`. On other
systems, build and run through SBCL and ASDF directly or use a Nix remote
builder.

The Nix flake is the official distribution path for released versions; GitHub
Releases publish the corresponding changelog entry and do not contain a
separate binary archive.

## Install

Consume the latest released tag from another flake:

```nix
inputs.cl-chip8 = {
  url = "github:nerima-lisp/cl-chip8/v0.3.0";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Expose the package from a consuming flake and run it with Nix:

```nix
outputs = { nixpkgs, cl-chip8, ... }: {
  packages.x86_64-linux.cl-chip8 =
    cl-chip8.packages.x86_64-linux.cl-chip8;
  packages.aarch64-darwin.cl-chip8 =
    cl-chip8.packages.aarch64-darwin.cl-chip8;
};
```

Then run `nix run .#cl-chip8 -- path/to/rom.ch8`. For an unreleased local
checkout, replace the URL with `path:../cl-chip8`, relative to the consuming
flake.

The library system is `cl-chip8`. Load it with ASDF and call `cl-chip8:run`:

```lisp
(require :asdf)
(asdf:load-system "cl-chip8")
(cl-chip8:run :rom-path #p"path/to/rom.ch8")
```

`run` accepts keyword arguments including `:rom-path`, `:clock-hz`, `:platform`,
`:quirks`, `:audio-mode`, and `:stream`. It creates and initializes a machine,
loads the ROM, then enters a raw-mode terminal session on the alternate screen.
The Lisp API defaults audio to `:off`; the CLI defaults to `auto`. It returns a
`chip8-app` after the session ends. For ASDF source registry and dependency
setup, see [Getting Started](https://nerima-lisp.github.io/cl-chip8/getting-started/).

## Documentation

- [Getting Started](https://nerima-lisp.github.io/cl-chip8/getting-started/)
- [Core Concepts](https://nerima-lisp.github.io/cl-chip8/guide/core-concepts/)
- [Terminal Guide](https://nerima-lisp.github.io/cl-chip8/guide/terminal/)
- [API Reference](https://nerima-lisp.github.io/cl-chip8/reference/api/)
- [Architecture](https://nerima-lisp.github.io/cl-chip8/reference/architecture/)
- [Compatibility](https://nerima-lisp.github.io/cl-chip8/reference/compatibility/)
- [Changelog](CHANGELOG.md)

## Development

```shell
nix flake check
nix build .#docs
nix fmt
```

The suite includes Timendus conformance checks and optional chip8Archive ROM
corpus compatibility checks. See the
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
