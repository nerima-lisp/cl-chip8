# cl-chip8

[![CI](https://github.com/nerima-lisp/cl-chip8/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/nerima-lisp/cl-chip8/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Documentation](https://img.shields.io/badge/docs-MkDocs%20Material-0a7a5a)](https://nerima-lisp.github.io/cl-chip8/)

A [CHIP-8](https://en.wikipedia.org/wiki/CHIP-8) interpreter for the terminal,
targeting the original 1977 COSMAC VIP instruction set. This emulator's CPU
core is not a conventional big-COND interpreter loop: registers, program
counter, call stack, and timers are expressed as a
[cl-prolog](https://github.com/nerima-lisp/cl-prolog) rulebase of dynamic
facts (asserted and retracted at runtime), and instruction dispatch is driven
by Prolog goal resolution over that rulebase. Memory and the display
framebuffer are plain Lisp arrays for O(1) access, wrapped by
`cl-prolog:define-foreign-predicate` so Prolog goals can still read and write
them. Targets SBCL only.

Full documentation is published at <https://nerima-lisp.github.io/cl-chip8/>.
The source for that site lives in [docs/src/](docs/src/).

## Quick Start

```lisp
(asdf:load-system "cl-chip8")

(cl-chip8:run :rom-path #p"/path/to/rom.ch8")
```

`RUN` resets the machine, loads the ROM, and plays it live in the terminal
(raw mode, alternate screen) until you press q, Q, or Ctrl-C. The delivered
`cl-chip8` executable does the same from the command line:

```sh
cl-chip8 path/to/rom.ch8 --clock-hz 700
cl-chip8 --help       # full option/positional list
cl-chip8 --version    # prints cl-chip8.asd's :version, never hand-copied
```

Lower-level pieces are available too, for embedding or experimentation:

```lisp
(cl-chip8:reset-cpu-state!)   ; zero every register, PC = 0x200, empty call stack
(cl-chip8:memory-reset!)
(cl-chip8:display-reset!)
(cl-chip8:load-fontset-into-memory!)
(cl-chip8:execute-instruction!)  ; fetch, decode, and run exactly one instruction
```

Instruction dispatch is driven by genuine Prolog goal resolution over the
CPU-state rulebase (see [src/opcodes.lisp](src/opcodes.lisp) for the full
instruction semantics), not a conventional interpreter loop. Quirks are fixed
at the modern-default behavior (not VIP-authentic, not configurable, and
there is no SUPER-CHIP support): `8XY6`/`8XYE` shift Vx only, ignoring Vy, and
`FX55`/`FX65` do not change I. There is no audio; while the sound timer is
nonzero, the terminal's top-left corner renders in reverse video instead of a
beep. The 64x32 monochrome display renders two pixel rows per terminal cell
using Unicode half-block glyphs, so the playfield fills 64 columns by 16
terminal rows, inset in a 1-cell border.

## Install

As a command, from a checkout:

```sh
nix develop          # SBCL with CL_SOURCE_REGISTRY already set
sbcl --non-interactive \
     --eval '(require :asdf)' \
     --eval '(asdf:operate (quote asdf:program-op) "cl-chip8")'
./src/cl-chip8 path/to/rom.ch8   # :build-pathname is relative to :pathname "src"
```

`nix build` currently produces only the `cl-chip8` library derivation (see
Development below), not this binary; the standalone executable is built via
ASDF's `program-op`, driven by the `:build-operation`/`:build-pathname`/
`:entry-point` trio in `cl-chip8.asd`.

As a library, from another flake:

```nix
# flake.nix
inputs.cl-chip8 = {
  url = "github:nerima-lisp/cl-chip8/v0.1.0";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Note the pinned tag. Consumers inside this org must pin a release tag rather
than follow the default branch.

## Keypad mapping

CHIP-8 programs address a 16-key hexadecimal keypad. This maps onto a modern
keyboard as follows:

| CHIP-8 |     |     |     | | Keyboard |     |     |     |
|:---:|:---:|:---:|:---:|-|:---:|:---:|:---:|:---:|
| `1` | `2` | `3` | `C` | | `1` | `2` | `3` | `4` |
| `4` | `5` | `6` | `D` | | `Q` | `W` | `E` | `R` |
| `7` | `8` | `9` | `E` | | `A` | `S` | `D` | `F` |
| `A` | `0` | `B` | `F` | | `Z` | `X` | `C` | `V` |

See `src/keypad.lisp` for the decoder and its wiring into the terminal's raw
input.

## Documentation

See [docs/src/](docs/src/) for the full guide -- what CHIP-8 is, why the CPU
core is a Prolog rulebase, and every quirk/sound/display decision -- published
at <https://nerima-lisp.github.io/cl-chip8/>.

## Development

```sh
nix develop          # SBCL with CL_SOURCE_REGISTRY already set
nix build            # build the cl-chip8 library derivation
nix run .#test       # run the test suite
nix flake check      # tests + formatting + docs + paredit lint, the same gate CI uses
nix fmt              # format Nix sources (treefmt)
```

Tests live in `t/` and run under [cl-weave](https://github.com/nerima-lisp/cl-weave),
the org's test framework. `nix flake check` additionally runs
[paredit-cli](https://github.com/nerima-lisp/paredit-cli)'s structural lint
over every Lisp source file.

## Contributing

See the org-wide [CONTRIBUTING](https://github.com/nerima-lisp/.github/blob/main/CONTRIBUTING.md)
guide and the [package standard](https://github.com/nerima-lisp/.github/blob/main/PACKAGE_STANDARD.md).

## Support

See [SUPPORT](https://github.com/nerima-lisp/.github/blob/main/SUPPORT.md).

## License

MIT. See [LICENSE](LICENSE).
