# Terminal Guide

The `cl-chip8` executable accepts one required ROM path:

```sh
cl-chip8 path/to/rom.ch8
cl-chip8 path/to/rom.ch8 --clock-hz 700
```

`--clock-hz` controls the instruction rate and defaults to 700. Delay and
sound timers continue at 60 Hz. The `--quirks` option accepts `modern` or
`cosmac-vip`. `--config` loads a TOML configuration file and `--log` writes
JSON log records to the specified file. `--help` prints the command-line interface and
`--version` reads the version from the ASDF system definition.

Press Escape or Ctrl-C to leave the program.

## Exit codes

| Code | Meaning |
|---:|---|
| `0` | The ROM ran and the program left the terminal normally. `--help` and `--version` also exit `0`. |
| `1` | The ROM could not be loaded, or the run ended with an error. The diagnostic goes to standard error with the `cl-chip8: ` prefix. |
| `64` | Usage error, such as a missing ROM path, an unknown option, or an invalid `--clock-hz` value. Usage text goes to standard error. |

## Keyboard layout

The sixteen CHIP-8 keys use this case-insensitive keyboard layout:

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

The terminal also provides application controls:

| Key | Action |
|---|---|
| `P` | Pause or resume execution. |
| `O` | Resume execution when paused. |
| `N` | Execute one instruction when paused, then remain paused. |
| Backspace | Reset machine state and resume the control loop. |
| Escape or Ctrl-C | Quit the application. |

## Display and sound

The 64x32 framebuffer is rendered as a 64-column by 16-row playfield. Each
terminal cell represents two vertical pixels with a Unicode half-block
character. A one-cell border surrounds the playfield. While the sound timer is
active, the upper-left border cell is shown in reverse video and the terminal
bell may be emitted periodically.

Rendering can use the serial renderer or the exported concurrent render
pipeline. The concurrent path converts immutable framebuffer row snapshots in
worker tasks and commits terminal changes on the caller thread.

## Configuration

The command line accepts a ROM path and optional overrides:

```sh
cl-chip8 path/to/rom.ch8 --quirks cosmac-vip --clock-hz 500 --log /tmp/cl-chip8.log
```

The configuration file uses TOML. The `chip8` table supports `quirks`,
`clock_hz`, `display_wait`, `clipping`, `shift_source`, `bnnn_register`,
`fx0a_completion`, `memory_i`, and `vf_reset`. The `logging` table supports
`path`. Explicit command-line values take precedence over TOML values, and
TOML values take precedence over defaults.
