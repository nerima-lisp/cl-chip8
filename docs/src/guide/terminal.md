# Terminal Guide

See [Getting Started](../getting-started.md) for Nix and ASDF launch
instructions. Use `cl-chip8` from `PATH` for these commands. From a checkout,
replace the leading `cl-chip8` with `nix run .#cl-chip8 --`.

```sh
cl-chip8 path/to/rom.ch8
cl-chip8 path/to/rom.ch8 --platform xo-chip --audio off
```

`--platform` selects one of `cosmac-vip`, `modern`, `schip`, `schip-legacy`,
or `xo-chip`. `--quirks` accepts the same names and selects a compatibility
profile. Both can be used together: platform selects machine defaults and
capabilities, while quirks selects instruction behavior. See the
[Compatibility reference](../reference/compatibility.md) for details.
`--config` loads TOML, `--log` writes JSON log records to a file,
`--colors-pixels` overrides the pixel palette, `--help` prints usage, and
`--version` prints the version from the ASDF system definition.

## Configuration priority

For machine platform selection, values are resolved in this order: CLI
`--platform`, TOML `chip8.platform`, the first supported platform identified
for the ROM by the bundled ROM database, a supplied application default, then
`modern`. The quirk profile follows CLI `--quirks`, TOML `chip8.quirks`,
application defaults, then the selected platform's default. For a database
record, its profile-specific quirk overrides are applied before individual
TOML settings.

If a recognized ROM lists only upstream platforms that cl-chip8 does not
implement, startup signals `chip8-unsupported-platform` before opening the
terminal. An explicit CLI `--platform` or `--quirks` bypasses that check. TOML
settings do not bypass it.

`--clock-hz` controls CPU instructions per second. The value is selected from
CLI, TOML `chip8.clock_hz`, a ROM-specific database tickrate multiplied by 60,
the database platform tickrate multiplied by 60, the selected platform's
default tickrate multiplied by 60, then the 700 instructions-per-second
fallback. Delay and sound timers always continue at 60 Hz.

The pixel palette priority is CLI `--colors-pixels`, TOML `colors.pixels`, a
matched ROM database palette, then built-in colors. CLI values are two or four
comma-separated `#RRGGBB` colors. The TOML form uses two or four strings.

## Audio

`--audio` selects audio output and defaults to `auto`. PCM output is provided
through `cl-audio-kit`; the TOML configuration has no audio setting.

Audio synthesis uses the selected platform's default sound. Platforms other
than XO-CHIP use the built-in 500 Hz square wave until the ROM executes `F002`
or `FX3A`; then the machine's XO-CHIP pattern and pitch control its sound, even
if ROM database lookup selected another platform. Pass `--platform xo-chip`
when an unrecognized ROM also needs XO-CHIP memory and platform defaults.

| `--audio` value | Behavior |
|---|---|
| `auto` | Try PCM on the system's default output device. If opening the device reports an audio error, fall back to the terminal bell and write a WARN message to standard error. With a log path, also write one structured `audio-fallback` entry. |
| `pcm` | Require PCM on the system's default output device. Exit with an error if the device cannot be opened. |
| `bell` | Use the terminal bell while the sound timer is active. |
| `off` | Disable sound output. The on-screen sound-timer indicator remains visible. |

The Common Lisp `run` function uses the keyword `:audio-mode` and defaults to
`:off`. Its accepted values are `:auto`, `:pcm`, `:bell`, and `:off`.

## Check audio output

Before testing PCM output, verify that the system's default output device can
play audio. Select that device in the operating system's sound settings and
follow the [cl-audio-kit manual audio check](https://nerima-lisp.github.io/cl-audio-kit/guide/manual-audio-check/)
to play a one-second tone. Skip this step if the output device has already
been verified.

Download the [Timendus `7-beep.ch8` ROM](https://github.com/Timendus/chip8-test-suite/raw/v4.2/bin/7-beep.ch8)
and run it with PCM enabled:

```sh
cl-chip8 path/to/7-beep.ch8 --audio pcm
```

Listen for the SOS sequence. The ROM's speaker icon and the upper-left
reverse-video border cell indicate ROM and sound-timer activity, but neither
confirms that sound reached the output device. If the tone test succeeds and
the indicators appear but the SOS is silent, report it as an emulator audio
output issue with the ROM and command used.

## Exit codes

| Code | Meaning |
|---:|---|
| `0` | The ROM ran and the emulator exited normally. `--help` and `--version` also exit `0`. |
| `1` | The ROM could not be loaded, required PCM output could not be opened, or the run ended with an error. The diagnostic goes to standard error with the `cl-chip8: ` prefix. |
| `64` | Usage error, such as a missing ROM path, an unknown option, or an invalid `--clock-hz` or `--audio` value. Usage text goes to standard error. |

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

Letter controls accept either case:

| Key | Action |
|---|---|
| `P` | Toggle pause or resume. |
| `O` | Resume execution when paused. |
| `N` | Execute one instruction when paused, then remain paused. |
| Backspace | Reset machine state and resume execution. |
| Escape or Ctrl-C | Quit the application. |

## Adaptive display

The application selects a renderer from the machine resolution and terminal
size. A one-cell border surrounds the playfield. Low-resolution mode requires
at least 66 columns by 18 rows. XO-CHIP low-resolution output uses half-block
cells and the configured palette; other low-resolution profiles use
monochrome half-block characters.

For a high-resolution display, the application chooses the first mode whose
minimum size fits:

| Renderer | Minimum terminal size | Pixel representation | Colors |
|---|---:|---|---|
| Half-block | 130 columns × 34 rows | One column and two rows per cell | All four palette colors |
| Quarter-block | 66 columns × 34 rows | Two columns and two rows per cell | On and off only |
| Braille | 66 columns × 18 rows | Two columns and four rows per cell | On and off only |

Below the minimum for the current resolution, the application displays a
terminal-size message and pauses instruction stepping. Execution resumes when
the terminal is resized to a supported size. The upper-left border cell
indicates an active sound timer in every audio mode.

## Configuration

Pass a TOML file with `--config`:

```sh
cl-chip8 path/to/rom.ch8 --config config.toml
```

You can override the pixel palette on the command line with two or four
comma-separated `#RRGGBB` colors:

```sh
cl-chip8 path/to/rom.ch8 --colors-pixels "#000000,#00FF00,#FFFF00,#FFFFFF"
```

For example, `config.toml` can contain:

```toml
[chip8]
platform = "xo-chip"
quirks = "xo-chip"
clock_hz = 6000
lores_sprite = "16x16"
collision = "flag"

[logging]
path = "/tmp/cl-chip8.log"

[colors]
pixels = ["#000000", "#00FF00", "#FFFF00", "#FFFFFF"]
```

The `[chip8]` table supports `platform`, `quirks`, `clock_hz`, `display_wait`,
`clipping`, `shift_source`, `bnnn_register`, `fx0a_completion`, `memory_i`,
`vf_reset`, `lores_sprite`, `collision`, `lores_scroll`, and
`mode_switch_clear`. `display_wait` accepts a boolean or `"lores-only"`;
`mode_switch_clear` accepts a boolean. `[logging]` supports `path`.
`[colors]` supports `pixels` as two or four `#RRGGBB` strings. Palette indices
follow framebuffer values 0 through 3. With two colors, the second color
fills indices 1 through 3. The renderer maps each color to a terminal
256-color entry. Only half-block mode uses all four colors; quarter-block and
braille use the on/off colors.
