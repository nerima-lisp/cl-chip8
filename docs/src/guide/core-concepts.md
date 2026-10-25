# Core Concepts

cl-chip8 models a CHIP-8 machine as a typed, mutable `chip8-machine` value.
The machine contains sixteen 8-bit registers, a 16-bit `I` register, a
sixteen-entry call stack, memory, timers, a keypad, display planes,
compatibility settings, and an instruction counter. A ROM loads at address
`0x200`.

## Platforms and state

The `:cosmac-vip` and `:modern` platforms default to 4 KiB of memory and
low-resolution display. `:schip` and `:schip-legacy` also default to 4 KiB,
and `:xo-chip` defaults to 64 KiB. The latter three platforms support both
low and high resolution. Pass `:platform` to `make-chip8-machine` to select a
platform; `:memory-size` can explicitly choose 4096 or 65536 bytes. Platform
profiles also provide font sets, default quirks, and a default tickrate.

The physical display stores 128 by 64 pixels, with a two-bit value per pixel
for its two planes. CHIP-8 and SUPER-CHIP low resolution expose 64 by 32
logical pixels; high resolution exposes the full 128 by 64. Machines begin in
low resolution with plane 1 selected. `chip8-machine-framebuffer` exposes the
physical array, while `chip8-framebuffer` and `chip8-framebuffer-snapshot`
return a copy sized to the current logical resolution. Pixel values use bit 0
for plane 1 and bit 1 for plane 2.

Create a machine with `make-chip8-machine`. The constructor initializes its
state; call `chip8-reset!` to reset an existing machine.

```lisp
(let ((machine (cl-chip8:make-chip8-machine :platform :xo-chip)))
  (cl-chip8:load-rom-file machine #p"path/to/rom.ch8")
  (cl-chip8:execute-instruction! machine))
```

Reset clears memory, registers, stack, timers, keypad, all display planes, and
execution state, then restores the fonts for the selected platform. `load-rom`
loads an octet vector, while `load-rom-file` loads a regular file and checks
its size and short-read conditions.

## State and execution

The low-level execution boundary is explicit:

1. `fetch-opcode` reads two bytes at the program counter.
2. `execute-instruction!` decodes and executes one instruction.
3. `step-timers!` decrements the delay and sound timers by one tick.

The terminal application advances timers at 60 Hz and schedules the configured
number of CPU instructions across those ticks. CPU and timer rates are
independent. The clock rate can come from an explicit CLI or TOML value, ROM
metadata, the selected platform, or the 700 instructions-per-second fallback.

## Headless execution

The headless helpers make waits observable without opening a terminal:

```lisp
(let ((machine (cl-chip8:make-chip8-machine)))
  (cl-chip8:load-rom-file machine #p"path/to/rom.ch8")
  (let ((result (cl-chip8:chip8-run-ticks machine 60
                                           :instructions-per-tick 12)))
    (cl-chip8:chip8-run-result-status result)))
```

`chip8-run-instructions` executes up to a requested instruction count.
`chip8-run-ticks` advances timers and executes instructions for a requested
number of ticks. Both return a `chip8-run-result` with a status, the number of
instructions executed, the machine, and a continuation when execution is
waiting. The status is `:completed`, `:waiting`, or `:halted`.

For example, this loads `LD V0, 1` and executes one instruction:

```lisp
(let* ((machine (cl-chip8:make-chip8-machine))
       (bytes (make-array 2 :element-type '(unsigned-byte 8)
                          :initial-contents '(#x60 #x01))))
  (cl-chip8:load-rom machine bytes)
  (let ((result (cl-chip8:chip8-run-instructions machine 1)))
    (list (cl-chip8:chip8-run-result-status result)
          (cl-chip8:chip8-machine-register machine 0))))
;; => (:COMPLETED 1)
```

An instruction can wait for a key or for a display tick. Resume a key wait by
calling `chip8-resume!` with `(:key-down key)` or `(:key-up key)`. Resume a
display wait with `:tick`.

Keypad state is managed directly on the machine:

```lisp
(let ((machine (cl-chip8:make-chip8-machine)))
  (cl-chip8:chip8-key-down! machine 5)
  (let ((state (list (cl-chip8:key-down-p machine 5)
                     (cl-chip8:pressed-keys machine))))
    (cl-chip8:chip8-key-up! machine 5)
    state))
```

## Compatibility profiles

`make-chip8-machine` defaults to the `:modern` platform, whose default quirk
profile is also `:modern`. The built-in profiles are `:modern`, `:cosmac-vip`,
`:schip`, `:schip-legacy`, and `:xo-chip`. Pass a `chip8-quirks` value to
override individual instruction behaviors. The
[Compatibility reference](../reference/compatibility.md) lists platform
capabilities and profile differences.

## Rendering

`chip8-framebuffer` returns a logical-size snapshot of the machine display.
The terminal application selects a low- or high-resolution renderer based on
terminal size. High resolution uses half-block, quarter-block, or braille
cells; if the terminal is too small, instruction stepping pauses until the
display fits again. The terminal application passes snapshots to
`render-chip8!` together with a terminal screen and render state. Applications
that need worker-based row conversion can use `render-chip8-concurrently!`
with a render pipeline. Display reads are snapshot-based, and terminal screen
mutations remain on the caller thread.
