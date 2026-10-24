# Terminal Guide

See [Getting Started](../getting-started.md) for Nix and ASDF launch
instructions.
Use `cl-chip8` from `PATH` for these commands. From a checkout, replace the
leading `cl-chip8` with `nix run .#cl-chip8 --`.

```sh
cl-chip8 path/to/rom.ch8
cl-chip8 path/to/rom.ch8 --audio pcm
```

`--clock-hz` controls the instruction rate and defaults to 700. Delay and
sound timers continue at 60 Hz. The `--quirks` option accepts `modern`,
`cosmac-vip`, `schip`, `schip-legacy`, and `xo-chip`. `--audio` selects audio
output and defaults to `auto`.
`--config` loads a TOML configuration file and `--log` writes JSON log records
to the specified file. `--help` prints the command-line interface and
`--version` prints the version recorded in the ASDF system definition. If ASDF
cannot find that definition, it prints `0.0.0`.

| `--audio` value | Behavior |
|---|---|
| `auto` | Use PCM output from the system default device. If it cannot be opened, fall back to the terminal bell and emit a WARN message on standard error. When a log path is configured, also record one structured `audio-fallback` entry. |
| `pcm` | Require PCM output from the system default device. The program exits with an error if it cannot open the device. |
| `bell` | Use the terminal bell. |
| `off` | Disable audio output. |

The TOML configuration file does not provide an audio setting.

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

## Display and sound

The 64x32 framebuffer is rendered as a 64-column by 16-row playfield. Each
terminal cell represents two vertical pixels with a Unicode half-block
character. A one-cell border surrounds the playfield. While the sound timer is
active, the upper-left border cell is shown in reverse video. The terminal bell
sounds periodically in `bell` mode and when `auto` falls back because the PCM
device could not be opened.
The upper-left timer indicator remains visible in every mode, including `off`.

## Check audio output

Before testing PCM output from `cl-chip8`, verify that the system's default
output device can play audio. Select that device in your operating system's
sound settings and follow the [cl-audio-kit manual audio
check](https://nerima-lisp.github.io/cl-audio-kit/guide/manual-audio-check/) to
play a one-second tone. Skip this step if you have already verified the device.

Download the [Timendus `7-beep.ch8` ROM](https://github.com/Timendus/chip8-test-suite/raw/v4.2/bin/7-beep.ch8)
and run it with PCM enabled:

```sh
cl-chip8 path/to/7-beep.ch8 --audio pcm
```

Listen for the SOS beep sequence. The ROM flashes a speaker icon, and the
upper-left reverse-video border cell indicates that the sound timer is active.
Neither confirms that audio reached the output device. If the SOS is silent,
repeat the one-second tone check above. If that tone is silent too, select or
check the system's default output device, then repeat the tone check and rerun
the ROM. If the ROM's speaker icon or border indicator does not appear, verify
that the command above names the downloaded `7-beep.ch8` and that the emulator
display has started, then rerun the test. If the tone is audible and both
indicators appear but the SOS remains silent, treat it as an emulator
audio-output issue and include the ROM and command when reporting it.

## Configuration

Pass a TOML file with `--config`:

```sh
cl-chip8 path/to/rom.ch8 --config config.toml
```

For example, `config.toml` can contain:

```toml
[chip8]
quirks = "cosmac-vip"
clock_hz = 500

[logging]
path = "/tmp/cl-chip8.log"
```

The `chip8` table supports `quirks`,
`clock_hz`, `display_wait`, `clipping`, `shift_source`, `bnnn_register`,
`fx0a_completion`, `memory_i`, and `vf_reset`. The `logging` table supports
`path`. Explicit command-line values take precedence over TOML values, and
TOML values take precedence over defaults.
