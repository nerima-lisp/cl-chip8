# Terminal Guide

The delivered executable accepts one required ROM path:

```sh
cl-chip8 path/to/rom.ch8
cl-chip8 path/to/rom.ch8 --clock-hz 700
```

`--clock-hz` controls the instruction rate and defaults to 700. The delay and
sound timers continue to tick at 60 Hz. `--help` prints the command-line
interface and `--version` reads the version from the ASDF system definition.
Press <kbd>Escape</kbd> or <kbd>Ctrl</kbd>+<kbd>C</kbd> to leave the program.

## Exit codes

| Code | Meaning |
|---:|---|
| `0` | The ROM ran and the program left the terminal normally. `--help` and `--version` also exit `0`. |
| `1` | The ROM could not be loaded, or the run ended with an error. The diagnostic goes to standard error, prefixed `cl-chip8: `. |
| `64` | Usage error -- a missing ROM path, an unknown option, or an invalid `--clock-hz` value. Usage text goes to standard error. |
| `70` | Any other unhandled error. |

`64` and `70` are the BSD `sysexits` values `EX_USAGE` and `EX_SOFTWARE`, which
the command inherits from `cl-cli` rather than setting itself. In practice `70`
is close to unreachable: the run handler catches `error` broadly and converts
it to a diagnostic and `1`, so a failure has to escape that handler entirely to
reach `70`.

## Keyboard

The sixteen CHIP-8 keys use the following case-insensitive keyboard layout:

| CHIP-8 | Keyboard | CHIP-8 | Keyboard |
|:---:|:---:|:---:|:---:|
| `1` | `1` | `2` | `2` |
| `3` | `3` | `C` | `4` |
| `4` | `Q` | `5` | `W` |
| `6` | `E` | `D` | `R` |
| `7` | `A` | `8` | `S` |
| `9` | `D` | `E` | `F` |
| `A` | `Z` | `0` | `X` |
| `B` | `C` | `F` | `V` |

Each key remains logically held for a short number of timer ticks after its
latest press event. This gives ROMs a stable key state on terminals that only
report key presses.

## Display and sound

The 64x32 framebuffer is rendered as a 64-column by 16-row playfield. Each
terminal cell represents two vertical pixels with a Unicode half-block
character. A one-cell border surrounds the playfield. While the sound timer
is active, the upper-left border cell is shown in reverse video and the
terminal bell may be emitted periodically.

The renderer takes immutable row snapshots before doing any concurrent work;
live Prolog state, the framebuffer, and terminal screen mutations stay on the
caller thread. See [Architecture](../reference/architecture.md) for the
embedding and pipeline contract.
