# Core Concepts

cl-chip8 models a CHIP-8 machine as a typed, mutable `chip8-machine` value.
The machine contains 4,096 bytes of memory, sixteen 8-bit registers, a 16-bit
`I` register, a sixteen-entry call stack, a 64x32 monochrome framebuffer, a
sixteen-key keypad, delay and sound timers, compatibility settings, and an
instruction counter. A ROM loads at address `0x200`.

## State and execution

Create and reset a machine with `make-chip8-machine`:

```lisp
(let ((machine (cl-chip8:make-chip8-machine)))
  (cl-chip8:load-rom-file machine #p"path/to/rom.ch8")
  (cl-chip8:execute-instruction! machine))
```

Reset clears memory, registers, stack, timers, keypad, framebuffer, and
execution state, then restores the built-in fontset. `load-rom` loads an octet
vector, while `load-rom-file` loads a regular file and checks its size and
short-read conditions.

The low-level execution boundary is explicit:

1. `fetch-opcode` reads two bytes at the program counter.
2. `execute-instruction!` decodes and executes one instruction.
3. `step-timers!` decrements the delay and sound timers by one tick.

The terminal application calls `step-timers!` at 60 Hz and schedules the
configured number of CPU instructions across those ticks. The CPU rate and
timer rate are therefore independent.

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
waiting.

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

An instruction can wait for a key or for a display tick. Resume a waiting
machine with `chip8-resume!`:

```lisp
(cl-chip8:chip8-resume! machine '(:key-down 5))
;; For a display wait:
(cl-chip8:chip8-resume! machine :tick)
```

Keypad state is managed directly on the machine:

```lisp
(cl-chip8:chip8-key-down! machine 5)
(cl-chip8:key-down-p machine 5)
(cl-chip8:pressed-keys machine)
(cl-chip8:chip8-key-up! machine 5)
```

## Compatibility profiles

`make-chip8-machine` defaults to the `modern` profile. Pass a
`chip8-quirks` value to choose another profile or override individual
behaviors. The built-in `cosmac-vip` profile changes the documented shift,
load/store, display-wait, clipping, jump-register, and key-wait behavior.
The [Compatibility reference](../reference/compatibility.md) lists each
instruction-level difference.

## Rendering

`chip8-framebuffer` returns a snapshot of the machine framebuffer. The
terminal application passes that snapshot to `render-chip8!` together with a
terminal screen and render state. Applications that need worker-based row
conversion can use `render-chip8-concurrently!` with a render pipeline.
Display reads are snapshot-based, and terminal screen mutations remain on the
caller thread.
