# Compatibility

cl-chip8 implements the original CHIP-8 instruction set and terminal model.
It does not implement SUPER-CHIP or XO-CHIP extensions.

This page is the behavioral contract for the release. Where the CHIP-8
ecosystem disagrees about an instruction, the choice made here is fixed: there
is no quirks mode and no runtime switch.

## Extension opcodes

An extension opcode does not always announce itself. Some signal
`chip8-invalid-opcode`; others are absorbed by the decoder's family-0 catch-all
and become silent no-ops, which means a SUPER-CHIP ROM can run to completion
while doing the wrong thing.

Silently ignored -- the program counter advances and nothing else happens:

| Opcode | Intended meaning |
|---|---|
| `00Cn` | SCD: scroll display down n lines |
| `00FB` | SCR: scroll display right |
| `00FC` | SCL: scroll display left |
| `00FD` | EXIT: halt the interpreter |
| `00FE` | LOW: select 64x32 low-resolution mode |
| `00FF` | HIGH: select 128x64 high-resolution mode |

These all match the `0NNN` SYS catch-all, which the original CHIP-8 treats as
an ignored machine-code call.

`DXY0` is a second silent case with a different cause: SUPER-CHIP reads it as
a 16x16 sprite, while this decoder reads the `N` nibble literally as a row
count. `DXY0` therefore draws zero rows and sets `VF` to 0.

Signaled as `chip8-invalid-opcode`:

| Opcode | Intended meaning |
|---|---|
| `FX30` | Load the address of a 10-byte high-resolution digit sprite |
| `FX75` | Store `V0`..`VX` in HP-48 RPL user flags |
| `FX85` | Read `V0`..`VX` back from HP-48 RPL user flags |
| `5XY2` | XO-CHIP: store a register range in memory |
| `5XY3` | XO-CHIP: load a register range from memory |

An extension ROM may also be rejected before it runs at all, because it
exceeds the 3,584-byte ROM capacity.

## Fixed instruction behavior

The runtime does not follow one ecosystem profile end to end. It takes the
modern CHIP-48 behavior for the shift and load/store quirks and the original
COSMAC VIP behavior for `BNNN`, so describing the whole runtime as either
"modern" or "VIP-authentic" would be wrong. The decisions are listed
individually below and are not configurable.

- `8XY6` and `8XYE` shift `Vx` in place and ignore `Vy`. The COSMAC VIP loads
  `Vy` into `Vx` first.
- `FX55` and `FX65` leave `I` unchanged after copying registers. The COSMAC
  VIP advances `I` past the copied block.
- `8XY1`, `8XY2`, and `8XY3` do not reset `VF`. The COSMAC VIP clears `VF` as
  a side effect of the logical operation; this runtime leaves it alone, which
  is the CHIP-48 and modern-emulator choice.
- `DXYN` wraps the sprite origin modulo the display and clips the sprite body
  at the edges. An origin of `Vx = 70` draws at column 6; a sprite whose
  wrapped origin sits at column 60 draws columns 60 through 63 and drops the
  rest rather than folding it back to column 0.
- `FX1E` wraps `I` modulo 65536 and never sets `VF`. Sixteen bits rather than
  twelve is deliberate: some ROMs rely on `I` temporarily exceeding `0xFFF`.
  Memory accesses through `I` are still range-checked, so an out-of-range `I`
  signals `chip8-memory-access-out-of-bounds` at the point of access.
- `FX0A` completes when a key is pressed. The COSMAC VIP completes on key
  release.
- `BNNN` is the original `JP V0, addr`: the jump target is `NNN + V0` taken
  modulo 4096. It is not the SUPER-CHIP `BXNN` reading, which would use `VX`
  selected by the high nibble of the address. The mask is load-bearing rather
  than cosmetic: `NNN` reaches `0xFFF` and `V0` is a full byte, so the raw sum
  reaches 4350 -- past the address space. Unmasked, the program counter would
  simply go out of range and the *next* fetch would signal
  `chip8-memory-access-out-of-bounds`, blaming an instruction that never ran.
  Wrapping matches the original interpreter's 12-bit program counter. It
  bounds `PC` but does not make the next fetch infallible: `PC = 4095` is in
  range and still signals, because a fetch reads two bytes.
- `FX29` masks `Vx` to its low nibble before selecting a digit sprite, so the
  address is `+fontset-address+ + 5 * (Vx mod 16)`. The fontset holds exactly
  sixteen five-byte glyphs; without the mask, `Vx = 255` would point `I` at
  arbitrary RAM that a following `DXYN` would render as a glyph.

ROMs that require VIP-authentic behavior for the instructions above need to be
adapted or run on an emulator with a selectable quirks profile.

## Runtime limits

- ROM bytes load at `0x200` and must fit in the remaining 3,584 bytes of the
  4,096-byte memory.
- The call stack limit is sixteen entries.
- The display is fixed at 64x32 pixels.
- The keypad has sixteen keys and uses the mapping in the [Terminal
  guide](../guide/terminal.md).
- The implementation targets SBCL. The Nix flake currently declares
  `x86_64-linux` as its build and check system.

These are implementation boundaries, not claims about every historical
CHIP-8 interpreter or ROM convention.

## ROM corpus smoke test

The repository does not vendor ROM files. For a broad external smoke test, the
test suite can exercise [John Earnest's
chip8Archive](https://github.com/JohnEarnest/chip8Archive/tree/0a41cc23ad5c9abbb764d041c11ea8c5b77b2bbf)
at commit `0a41cc23ad5c9abbb764d041c11ea8c5b77b2bbf`. The archive contains 101
compiled `.ch8` files and metadata for 48 `chip8`, 25 `schip`, and 28 `xochip`
programs. Its
[README](https://github.com/JohnEarnest/chip8Archive/blob/0a41cc23ad5c9abbb764d041c11ea8c5b77b2bbf/README.md)
documents the repository's CC0 policy and attribution caveat; do not add the
ROMs to this repository or redistribute individual programs without checking
their provenance.

The corpus run is opt-in and skipped by default, because the ROMs are not part
of the checkout. Clone the archive at the pinned commit and point the suite at
it:

```sh
git clone https://github.com/JohnEarnest/chip8Archive /tmp/chip8Archive
git -C /tmp/chip8Archive checkout --detach 0a41cc23ad5c9abbb764d041c11ea8c5b77b2bbf
CL_CHIP8_ROM_CORPUS=/tmp/chip8Archive/roms sbcl --script run-tests.lisp
```

Two environment variables configure the run:

| Variable | Effect |
|---|---|
| `CL_CHIP8_ROM_CORPUS` | Root of a directory tree of `.ch8` files, searched recursively. Unset or blank means the corpus spec skips; set to a path that is not an existing directory, it errors rather than skipping. |
| `CL_CHIP8_ROM_CORPUS_BUDGET` | Instructions executed per ROM. Defaults to 2000. Must parse in full as a positive decimal integer; a zero, a negative, or a trailing-junk value is an error rather than a silent fall back to the default. |

To reproduce a deeper run, raise the budget:

```sh
CL_CHIP8_ROM_CORPUS=/tmp/chip8Archive/roms \
CL_CHIP8_ROM_CORPUS_BUDGET=10000 \
  sbcl --script run-tests.lisp
```

If you want the ROM bytes pinned as well as the commit, record a checksum
manifest on one machine and verify it on another, or after a later re-clone.
Generating a manifest and immediately checking it against the same files
verifies nothing at that moment.

The corpus run is a CPU smoke test. It initializes the machine, loads each
ROM, and executes the budget in a loop; it does not supply input, advance
timers, or render a terminal frame.

### What the run reports

The suite prints the corpus root, the budget, one count per outcome class, and
a total. The outcome classes are `completed`, `unsupported-opcode`,
`too-large`, `memory-access-out-of-bounds`, `stack-overflow`,
`stack-underflow`, and `error`.

Four of them fail the run: `memory-access-out-of-bounds`, `stack-overflow`,
`stack-underflow`, and `error`. `unsupported-opcode` and `too-large` are
counted but do not fail it, because refusing a SUPER-CHIP or XO-CHIP
instruction and refusing an oversized ROM are both correct behavior. A run
against a configured root holding no `.ch8` file fails rather than passing
over an empty set.

There is no per-ROM-class breakdown. Discovery walks every `.ch8` file under
the root and never reads chip8Archive's metadata, so the run cannot tell a
`chip8` program from an `schip` or `xochip` one. Any figure split that way came
from reading the archive's metadata by hand, not from this command.

### A recorded past run

The following was observed once against the pinned commit, by cross-referencing
the archive's own metadata with per-ROM outcomes. It is a historical record,
not output this procedure reproduces, and it is not re-measured on each
release:

- All 48 `chip8` ROMs completed 2,000 instructions, and all 48 also completed
  a 10,000-instruction run.
- 23 of 25 `schip` ROMs completed 2,000 instructions; 2 stopped at an
  unsupported opcode.
- 1 of 28 `xochip` ROMs completed 2,000 instructions; 5 stopped at an
  unsupported opcode and 22 were rejected for exceeding the 3,584-byte ROM
  capacity.
- No memory-access or stack errors occurred across the 101 ROMs.

Whether those counts predate the `BNNN` mask-to-4096 change described above is
unresolved. That change converts an out-of-range jump from a fault into a wrap,
so the corpus no longer sees that particular fault at all: a rerun could differ
from the figures above without anything having regressed.

Read the numbers narrowly in any case. "Completed N instructions without
erroring" does not distinguish a correctly executed ROM from one whose
unsupported opcodes were silently ignored -- the family-0 catch-all described
above turns every SUPER-CHIP display opcode into a no-op that a smoke test
cannot see. The `schip` and `xochip` figures are compatibility limits, not
gameplay compatibility claims.
