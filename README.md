# cl-chip8

[![CI](https://github.com/nerima-lisp/cl-chip8/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/nerima-lisp/cl-chip8/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Documentation](https://img.shields.io/badge/docs-MkDocs%20Material-0a7a5a)](https://nerima-lisp.github.io/cl-chip8/)

A [CHIP-8](https://en.wikipedia.org/wiki/CHIP-8) interpreter for the terminal,
using a fixed modern-CHIP-8 compatibility profile. This emulator's CPU
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
(raw mode, alternate screen) until you press Escape or Ctrl-C. The delivered
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
CPU-state rulebase (see [src/opcode-runtime.lisp](src/opcode-runtime.lisp) for
fetch/decode/execute and [src/opcodes.lisp](src/opcodes.lisp) for the full
instruction rule table), not a conventional interpreter loop. Quirks are fixed
at the modern-default behavior (not VIP-authentic, not configurable, and
there is no SUPER-CHIP support): `8XY6`/`8XYE` shift Vx only, ignoring Vy, and
`FX55`/`FX65` do not change I. While the sound timer is nonzero, the emulator
emits a terminal-bell control character at most ten times per second and also
renders the terminal's top-left corner in reverse video. Terminals may mute
the bell, so the visual indicator remains available. The 64x32 monochrome display renders two pixel rows per terminal cell
using Unicode half-block glyphs, so the playfield fills 64 columns by 16
terminal rows, inset in a 1-cell border.

The realtime renderer tracks dirty terminal rows and owns one persistent,
bounded [cl-concurrent-kit](https://github.com/nerima-lisp/cl-concurrent-kit)
executor. Worker tasks receive copied bit-vector snapshots and return terminal
characters; Prolog facts, the framebuffer, and `cl-tty-kit` screen mutations
remain on the caller thread. Tiny updates use serial fast paths when executor
scheduling would cost more than the row conversion. On the fixed 16-row terminal
display, partial batches with 1-8 dirty rows stay serial, while batches with
9-15 rows can use persistent CCK when the configured threshold allows it. The
production default is 13: measured scheduling overhead keeps 1-12 row batches
on the direct path, while 13-15 row batches remain eligible for CCK. Full
16-row frames remain serial because scheduling a complete frame costs more than
direct rendering.

## Install

As a command, from a checkout:

```sh
nix develop          # SBCL with CL_SOURCE_REGISTRY already set
sbcl --non-interactive \
     --eval '(require :asdf)' \
     --eval '(asdf:operate (quote asdf:program-op) "cl-chip8")'
./src/cl-chip8 path/to/rom.ch8   # :build-pathname is relative to :pathname "src"
```

`nix build` builds the delivered `cl-chip8` executable package. Run it with
`nix run .#cl-chip8 -- path/to/rom.ch8`; the explicit `program-op` command
above is useful when building directly with SBCL outside Nix.

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
nix build            # build the delivered cl-chip8 executable package
nix run .#cl-chip8 -- path/to/rom.ch8
nix run .#test       # run the test suite
nix flake check      # tests + formatting + docs + paredit lint, the same gate CI uses
nix fmt              # format Nix sources (treefmt)
CL_CHIP8_BENCH_WARMUP=5 CL_CHIP8_BENCH_ITERATIONS=2000 \
  sbcl --script bench/render.lisp
sbcl --script tools/coverage.lisp
```

Tests live in `t/` and run under [cl-weave](https://github.com/nerima-lisp/cl-weave),
the org's test framework. `nix flake check` additionally runs
[paredit-cli](https://github.com/nerima-lisp/paredit-cli)'s structural lint
over every Lisp source file. The renderer benchmark compares serial and
concurrent output for `SPARSE`, `MEDIUM`, `LARGE-PARTIAL`, and `DENSE`
dirty-row workloads, checks every screen cell and style for equality, and
reports executor counters for the measured window only. The fixed display's
public fixtures contain at most 12 dirty rows: 1-8 stay serial, while the
12-row `LARGE-PARTIAL` fixture crosses the public CCK lower bound and exercises
persistent submission with `CL_CHIP8_BENCH_PARALLEL_THRESHOLD=9`. The
production default of 13 keeps that small workload on the direct path because
repeated measurements show CCK scheduling overhead; `DENSE` stays serial
because full-frame scheduling is slower than direct rendering. Output equality
and the worker lifecycle are covered by dedicated regression tests.
The coverage script writes an HTML report to `coverage/cover-index.html` and
fails unless the selected runtime source set reaches 99% expression and
100% branch coverage. It explicitly excludes the interactive/bootstrap files,
static `*-types` modules, the ordered declarative rulebase `src/opcodes.lisp`,
and `src/package.lisp`; the complete list is maintained in
`tools/coverage.lisp`. The latest local run passed 176 tests and measured
1362/1375 selected expressions (99.05%) and 66/66 measured branches (100.00%).
The remaining expression misses are SB-COVER load-time `in-package`/constant
forms and optional constructor keyword-default forms; relevant no-argument
paths are tested, but SB-COVER does not mark every default form as selected at
that instrumentation boundary. All measured branches are covered.

This flake declares `systems = [ "x86_64-linux" ]` only (see flake.nix's own
comment on why aarch64-darwin was dropped org-wide). On any other host --
including a Mac -- `nix flake check` omits the incompatible Linux checks and
can exit 0 without running them. `nix build .#cl-chip8` has no native
`aarch64-darwin` package attribute and fails before building. To verify
changes on such a host without a Linux builder, clone this repository's
pinned sibling dependencies (see flake.nix's `inputs`) into a local
`CL_SOURCE_REGISTRY` tree and run `sbcl --script run-tests.lisp` directly --
also run `sbcl --script tools/coverage.lisp` for the coverage gate. SBCL itself
is not Linux-only, only this org's Nix packaging policy is.

## Contributing

See the org-wide [CONTRIBUTING](https://github.com/nerima-lisp/.github/blob/main/CONTRIBUTING.md)
guide and the [package standard](https://github.com/nerima-lisp/.github/blob/main/PACKAGE_STANDARD.md).

## Support

See [SUPPORT](https://github.com/nerima-lisp/.github/blob/main/SUPPORT.md).

## License

MIT. See [LICENSE](LICENSE).
