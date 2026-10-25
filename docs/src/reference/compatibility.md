# Compatibility

The runtime supports the original CHIP-8 instruction set, SUPER-CHIP, and
XO-CHIP. The selected platform controls machine defaults and supported
features; the quirk profile controls instruction behavior. `modern` is the
platform and quirk default when neither is specified. When only a platform is
selected, its default quirk profile is used. Use `--platform` and `--quirks`
independently, or select a platform for a Lisp machine with
`make-chip8-machine` and pass a `chip8-quirks` value when finer control is
needed.

## Platform profiles

| Platform | Default memory | Resolutions | Font sets | Default tickrate |
|---|---:|---|---|---:|
| `cosmac-vip` | 4 KiB | Low | CHIP-8 | 15 instructions per frame |
| `modern` | 4 KiB | Low | CHIP-8 | 12 instructions per frame |
| `schip` | 4 KiB | Low and high | CHIP-8, SUPER-CHIP large | 30 instructions per frame |
| `schip-legacy` | 4 KiB | Low and high | CHIP-8, SUPER-CHIP large | 30 instructions per frame |
| `xo-chip` | 64 KiB | Low and high | CHIP-8, SUPER-CHIP large | 100 instructions per frame |

Any platform can be constructed with an explicit memory size of 4 KiB or 64
KiB. All machines use a 128 by 64 physical two-plane display. Low resolution
uses 64 by 32 logical pixels; high resolution uses 128 by 64. The platform
profile ticks are converted to CPU instructions per second by multiplying by
60. Delay and sound timers always run at 60 Hz. An explicit CLI or TOML clock
overrides these defaults; see the [Terminal guide](../guide/terminal.md) for
the complete clock and configuration precedence.

## Quirk profiles

The built-in profile values are:

| Behavior | `modern` | `cosmac-vip` | `schip` | `schip-legacy` | `xo-chip` |
|---|---|---|---|---|---|
| `vf-behavior` | `preserve` | `reset` | `preserve` | `preserve` | `preserve` |
| `memory-i` | `preserve` | `increment` | `preserve` | `preserve` | `increment` |
| `display-wait` | `none` | `wait` | `none` | `lores-only` | `none` |
| `clipping` | `clip` | `clip` | `clip` | `clip` | `wrap` |
| `shift-source` | `vx` | `vy` | `vx` | `vx` | `vy` |
| `bnnn-register` | `v0` | `v0` | `vx` | `vx` | `v0` |
| `fx0a-completion` | `press` | `release` | `press` | `press` | `press` |
| `lores-sprite` | `16x16` | `16x16` | `16x16` | `8x16` | `16x16` |
| `collision` | `flag` | `flag` | `flag` | `row-count` | `flag` |
| `lores-scroll` | `full` | `full` | `full` | `half` | `full` |
| `mode-switch-clear` | `true` | `true` | `true` | `false` | `true` |

`vf-behavior` selects whether affected arithmetic and logic instructions
preserve or clear `VF`. `memory-i` controls how `FX55` and `FX65` update `I`:
`preserve` leaves it unchanged, `increment` advances it by `X + 1`, and
`increment-x` advances it by `X`. `display-wait` controls whether drawing
waits for a display tick, only in low resolution, or not at all.

`clipping` either discards sprite pixels beyond an edge or wraps them to the
opposite edge. Sprite start coordinates wrap in every profile. `shift-source`
chooses whether `8XY6` and `8XYE` read `Vx` or `Vy`; `bnnn-register` selects
the register added to `NNN`. `fx0a-completion` chooses key press or key
release. `lores-sprite` selects the width used by low-resolution `DXY0`.
`collision` normally sets `VF` to a collision flag; the legacy row-count mode
reports colliding rows and clipped rows for high-resolution drawing.
`lores-scroll` changes the low-resolution distance used by SCHIP scroll
instructions. `mode-switch-clear` controls whether changing resolution clears
the display.

The TOML key `vf_reset` maps to the API field `vf-behavior`; `true` selects
`:reset` and `false` selects `:preserve`.

The CLI selects a complete quirk profile with `--quirks`; TOML can also set
individual keys in `[chip8]`. From Lisp, pass profile and override keywords to
`make-chip8-quirks`. TOML keys use underscores, such as `vf_reset`,
`lores_sprite`, `lores_scroll`, and `mode_switch_clear`.

## ROM database

The bundled database matches ROM bytes by SHA-1. A matching record may supply
supported platform names, platform-specific compatibility quirks, a ROM
tickrate, and pixel colors. Recognized upstream platforms map as follows:

| Database platform | cl-chip8 profile |
|---|---|
| `originalChip8` | `cosmac-vip` |
| `modernChip8` | `modern` |
| `chip48`, `superchip1` | `schip-legacy` |
| `superchip` | `schip` |
| `xochip` | `xo-chip` |

Records identifying only `hybridVIP`, `megachip8`, or `chip8x` are known but
unsupported. cl-chip8 signals `chip8-unsupported-platform` before starting the
terminal session for such a matched ROM. Explicit CLI `--platform` or
`--quirks` bypasses this check so a user can choose how to run the ROM. TOML
platform or quirks settings do not bypass it. An unmatched ROM uses the
ordinary defaults.

## Conformance checks

The test suite includes the Timendus CHIP-8 test ROMs. It also has an optional
chip8Archive corpus compatibility check, configured through
`CL_CHIP8_ROM_CORPUS`; the Nix flake check supplies both corpora and verifies
the generated ROM database against its checked-in data. See the
[development guide](../project/development.md) for the commands.
