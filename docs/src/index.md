# cl-chip8

A [CHIP-8](https://en.wikipedia.org/wiki/CHIP-8) interpreter for the terminal.
CHIP-8 is not a real machine -- it's an interpreted bytecode designed in 1977
for the COSMAC VIP and other home computers of the era, so programs could be
typed in from magazine listings and run identically across very different
hardware. A CHIP-8 "ROM" is a stream of 2-byte opcodes acting on 16
general-purpose 8-bit registers (V0-VF), a 16-bit address register (I), a
64x32 monochrome display, a 16-key hexadecimal keypad, and two 60Hz countdown
timers (delay and sound). cl-chip8 implements all 35 of the original
instructions -- there is no SUPER-CHIP support, and no configurable
VIP-authentic quirks mode; see [Quirks](#quirks-and-fixed-behavior) below for
what "modern default" means here.

## Why the CPU core is a Prolog rulebase

Most CHIP-8 interpreters -- including the reference implementations this one
was written alongside -- decode an opcode into a family/sub-family pair and
dispatch on it with a Lisp `COND` or `CASE`. cl-chip8 does something
different: the entire CPU state (every register, I, the program counter, the
call stack, and both timers) lives as ordinary Prolog facts in a
[cl-prolog](https://github.com/nerima-lisp/cl-prolog) rulebase
(`*RULEBASE*`, built in `src/state.lisp`), asserted and retracted at runtime
via cl-prolog's `ASSERTZ`/`RETRACT`/`RETRACTALL` builtins. Executing one
instruction (`EXECUTE-INSTRUCTION!` in `src/opcodes.lisp`) fetches and decodes
a 16-bit opcode into six plain integers -- `(FAMILY X Y N KK NNN)` -- and
resolves exactly one `(step Family X Y N Kk Nnn)` goal against a roughly
35-clause `STEP/6` predicate. Which clause fires is decided by genuine
unification, not an `if`/`case` reading the decoded values in Lisp: `FAMILY`
gives cl-prolog's first-argument indexing its top-level split, and within a
family, `N` or `KK` (already bound to a concrete integer) unifies against a
literal in the clause head to pick the sub-opcode. `8XY6` and `8XY7`, for
example, are two different `STEP` clauses distinguished purely by `N`
unifying with 6 or 7.

This is a deliberate choice, not an accident of the tools at hand. It makes
the opcode table -- the part of a CHIP-8 interpreter most likely to be read,
extended, or gotten subtly wrong -- a literal, declarative list of clauses
that reads like the instruction set references it's transcribed from, rather
than a wall of Lisp control flow. The tradeoff is that a handful of concerns a
pure Prolog clause body cannot express -- signaling Lisp conditions on stack
overflow/underflow, iterating a sprite's rows and bits, masking a random byte,
bitwise OR/AND/XOR -- are bridged back to Lisp via
`cl-prolog:define-foreign-predicate`, small functions the rulebase calls into
and which read and write `*MEMORY*` and `*DISPLAY*` directly. Memory and the
display framebuffer are themselves plain Lisp arrays, not one Prolog fact per
byte or pixel -- at up to 4096 memory cells and 2048 pixels, a fact-per-cell
representation would make every `RETRACT`/`RETRACTALL` on a single write scan
thousands of clauses. Foreign predicates keep those two structures at O(1)
access while still letting Prolog goals read and write them as if they were
ordinary facts.

See [src/opcodes.lisp](https://github.com/nerima-lisp/cl-chip8/blob/main/src/opcodes.lisp)
for the full instruction semantics: every one of the 35 opcode families,
grouped and commented in the same order the file defines them (families 0
through 9, then A through F by their conventional hex names), including the
handful of foreign predicates each family's clause bodies call into.

## Quirks and fixed behavior

Real CHIP-8 programs disagree about a handful of instructions, because the
various interpreters that appeared after the original COSMAC VIP disagreed
about them first. cl-chip8 does not try to reproduce the VIP's exact
behavior, and does not offer a quirks-mode switch. It always runs the
"modern default" that most contemporary interpreters and test ROMs expect:

- **`8XY6` (SHR) and `8XYE` (SHL)** shift `Vx` in place and ignore `Vy`
  entirely, rather than shifting `Vy` and storing into `Vx` as the original
  VIP did.
- **`FX55` (store V0..Vx to memory) and `FX65` (load V0..Vx from memory)**
  leave the `I` register unchanged after the operation, rather than
  advancing it past the block as the VIP did.

If a ROM was written to depend on the VIP-authentic versions of these four
instructions, it will not behave as its author intended here -- there is no
per-ROM or command-line switch to select the other behavior.

## Sound

CHIP-8's sound timer counts down from whatever an `FX18` instruction loads
into it, at a fixed 60Hz, and the original hardware beeps for as long as it
is nonzero. cl-chip8 has **no audio output at all**. Instead, the terminal's
top-left border corner (the single cell that sits outside the 64x32
playfield) renders in reverse video for as long as the sound timer is
nonzero, and plain otherwise. This is a visual stand-in for the beep, not an
attempt to play one through the terminal bell or any other mechanism.

## Display

The CHIP-8 framebuffer is 64x32 monochrome pixels. A terminal cell is roughly
twice as tall as it is wide, so rendering it one pixel per cell would distort
the aspect ratio badly. cl-chip8 instead renders **two pixel rows per
terminal cell**, using the Unicode half-block glyphs U+2580 (▀ upper half
block), U+2584 (▄ lower half block), U+2588 (█ full block), and plain space
for a cell with neither pixel set. The result is a 64-column by 16-row
terminal playfield at close to the correct aspect ratio, inset by a 1-cell
border on every side -- the same border whose top-left corner carries the
sound indicator described above.

## Keypad mapping

CHIP-8 programs address a 16-key hexadecimal keypad (0-9 and A-F), originally
arranged as a 4x4 pad on the COSMAC VIP. cl-chip8 maps that onto the
standard 4x4 QWERTY block of a modern keyboard:

| CHIP-8 |     |     |     | | Keyboard |     |     |     |
|:---:|:---:|:---:|:---:|-|:---:|:---:|:---:|:---:|
| `1` | `2` | `3` | `C` | | `1` | `2` | `3` | `4` |
| `4` | `5` | `6` | `D` | | `Q` | `W` | `E` | `R` |
| `7` | `8` | `9` | `E` | | `A` | `S` | `D` | `F` |
| `A` | `0` | `B` | `F` | | `Z` | `X` | `C` | `V` |

The mapping is case-insensitive (`q` and `Q` both press key 4). A key is
treated as held down for a short countdown of ticks after its most recent
press event, to approximate a genuine key-release signal on terminals that
don't report one -- see `src/keypad.lisp` for the exact mechanism and why it
is necessary.

## Command-line usage

```sh
cl-chip8 path/to/rom.ch8              # run at the default clock speed
cl-chip8 path/to/rom.ch8 --clock-hz 700
cl-chip8 --help
cl-chip8 --version
```

The ROM path is a required positional argument. `--clock-hz` sets how many
CPU instructions execute per second (700 by default); the delay and sound
timers always step at a fixed 60Hz regardless of this setting. `--help`
prints the full option and positional list, and `--version` prints the
running build's version, read from `cl-chip8.asd` at runtime rather than
copied into the source as a literal, so it cannot drift from the `.asd`.
Press `q`, `Q`, or Ctrl-C at any time to quit and restore the terminal.

See the [README](https://github.com/nerima-lisp/cl-chip8#readme) for how to
build the `cl-chip8` executable and for the Lisp-level API
(`cl-chip8:run` and the lower-level `reset`/`load`/`execute` pieces it is
built from).
