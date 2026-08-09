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
- `BNNN` is the original `JP V0, addr`: the jump target is `NNN + V0`. It is
  not the SUPER-CHIP `BXNN` reading, which would use `VX` selected by the
  high nibble of the address.

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
of the checkout. Clone the archive at the pinned commit, record a checksum
manifest, and point the suite at it:

```sh
git clone https://github.com/JohnEarnest/chip8Archive /tmp/chip8Archive
git -C /tmp/chip8Archive checkout --detach 0a41cc23ad5c9abbb764d041c11ea8c5b77b2bbf
find /tmp/chip8Archive/roms -type f -name '*.ch8' -exec shasum -a 256 {} + \
  | sort > /tmp/chip8-rom-sha256.txt
shasum -a 256 -c /tmp/chip8-rom-sha256.txt
CL_CHIP8_ROM_CORPUS=/tmp/chip8Archive/roms sbcl --script run-tests.lisp
```

The corpus run is a CPU smoke test. It initializes the machine, loads each ROM,
and executes a fixed number of instructions; it does not supply input, advance
timers, or render a terminal frame.

Results from the pinned corpus:

- All 48 `chip8` ROMs completed 2,000 instructions, and all 48 also completed
  an extended 10,000-instruction run.
- 23 of 25 `schip` ROMs completed 2,000 instructions; 2 stopped at an
  unsupported opcode.
- 1 of 28 `xochip` ROMs completed 2,000 instructions; 5 stopped at an
  unsupported opcode and 22 were rejected because they exceed the 3,584-byte
  ROM capacity.
- No memory-access or stack errors occurred in the 101-ROM run.

Read those numbers narrowly. "Completed N instructions without erroring" does
not distinguish a correctly executed ROM from one whose unsupported opcodes
were silently ignored -- the family-0 catch-all described above turns every
SUPER-CHIP display opcode into a no-op that a smoke test cannot see. The
`schip` and `xochip` figures are compatibility limits, not gameplay
compatibility claims.
