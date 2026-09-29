# Compatibility

The runtime implements the original CHIP-8 instruction set with two selectable
profiles. `modern` is the default. `cosmac-vip` matches the behavior required by
the Timendus `5-quirks` CHIP-8 tests. The current conformance run reports all
six tested items as passing for `cosmac-vip`; `modern` passes CLIPPING and
JUMPING, while VF RESET, MEMORY, DISP.WAIT, and SHIFTING report errors.

| Quirk | `modern` | `cosmac-vip` | Meaning |
|---|---|---|---|
| `vf-behavior` | `:preserve` | `:reset` | Whether affected operations preserve or clear `VF`. |
| `memory-i` | `:preserve` | `:increment` | Whether `FX55` and `FX65` leave `I` unchanged or advance it. |
| `display-wait` | `:none` | `:wait` | Whether `DXYN` continues immediately or waits for a display tick. |
| `clipping` | `:clip` | `:clip` | Whether pixels beyond an edge are discarded or wrapped. |
| `shift-source` | `:vx` | `:vy` | Whether `8XY6` and `8XYE` shift `Vx` or use `Vy` as input. |
| `bnnn-register` | `:v0` | `:v0` | The register added to `NNN` by `BNNN`. |
| `fx0a-completion` | `:press` | `:release` | Whether `FX0A` completes on key press or release. |

Sprite start coordinates always wrap modulo the 64x32 display. The
`clipping` quirk only controls pixels that extend past an edge: `:clip`
discards them, while `:wrap` draws them on the opposite edge. It does not
change how the starting coordinate is normalized.

Select a profile with `--quirks modern` or `--quirks cosmac-vip`, or use
`make-chip8-quirks` from Lisp. Individual settings can be supplied through TOML.

The display is fixed at 64x32 pixels, memory is 4,096 bytes, ROMs load at
`0x200`, and the call stack has sixteen entries. SUPER-CHIP and XO-CHIP
extensions are outside the supported instruction set.
