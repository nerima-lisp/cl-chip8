# API reference

The public package is `cl-chip8`. The API is grouped by the state it owns and
the boundary where it is used.

This page documents the exported surface, and only that. A symbol is exported
if and only if it is one of:

- an entry point that runs the emulator;
- a condition, or a reader on one, that a caller must handle;
- a machine-state primitive needed to drive the interpreter headlessly --
  reset, load, step, read a pixel, read a fact;
- a whole-frame render operator, a render-pipeline lifecycle operator, or a
  type named by a kept operator's `check-type` or returned by one.

Everything else is internal: `cl-prolog` foreign-predicate goal functors,
`defstruct` accessors, telemetry counters, tuning knobs, sub-step renderers,
internal bounds checks, and helpers with no CHIP-8 semantics. Internal symbols
are reachable only through the double-colon `cl-chip8::` syntax, carry no
compatibility promise, and may be renamed or removed in any release. Do not
build against them.

A few exported symbols still look like Prolog goals rather than ordinary Lisp
functions: `v`, `i-register`, `pc`, `call-stack`, `delay-timer`, `sound-timer`,
and `key-down` are *fact* functors, the shapes of the dynamic facts a headless
driver asserts, retracts, and queries against `*rulebase*`. They are not
callable functions.

Callable entries use the same order throughout: summary, returns, signals, and
example. Examples are omitted only for condition classes, constants, variables,
fact functors, accessors, and predicates whose call shape is self-explanatory.

## Conditions

### `chip8-error`

```lisp
cl-chip8:chip8-error
```

Base condition for every error signaled by the package.

**Returns**: A condition class designator, not a callable function.

**Signals**: Not applicable; this entry names the base condition class.

**Example**:

```lisp
(handler-bind ((cl-chip8:chip8-error #'invoke-debugger))
  (cl-chip8:execute-instruction!))
```

See also: [Conditions](conditions.md).

### `chip8-rom-too-large`

```lisp
cl-chip8:chip8-rom-too-large
```

Signals when a ROM or byte span exceeds the available memory.

**Returns**: A condition class designator.

**Signals**: Not applicable; this entry names a condition class. The class is
signaled by ROM and memory loading operations when the requested span is too
large.

See also: [`load-rom-file!`](#load-rom-file), [`load-bytes-into-memory`](#load-bytes-into-memory), [Conditions](conditions.md).

### `chip8-rom-too-large-size`

```lisp
(cl-chip8:chip8-rom-too-large-size condition) => integer
```

Reads the attempted ROM or byte-span size from a `chip8-rom-too-large`
condition.

**Returns**: The requested size in bytes.

**Signals**: `none` for a `chip8-rom-too-large` condition.

**Example**:

```lisp
(handler-case (cl-chip8:load-rom-file! path)
  (cl-chip8:chip8-rom-too-large (condition)
    (format t "~D bytes requested~%"
            (cl-chip8:chip8-rom-too-large-size condition))))
```

### `chip8-rom-too-large-available`

```lisp
(cl-chip8:chip8-rom-too-large-available condition) => integer
```

Reads the remaining capacity reported by a `chip8-rom-too-large` condition.

**Returns**: Available bytes from the requested load address.

**Signals**: `none` for a `chip8-rom-too-large` condition.

### `chip8-rom-short-read`

```lisp
cl-chip8:chip8-rom-short-read
```

Signals when a ROM file ends before the byte count `file-length` reported has
been read. This keeps a truncated read from returning a byte vector whose tail
is still the initial zero fill.

**Returns**: A condition class designator.

**Signals**: Not applicable; this entry names a condition class. The class is
signaled by the internal ROM file read and propagates out of `load-rom-file!`.

See also: [`load-rom-file!`](#load-rom-file), [Conditions](conditions.md).

### `chip8-rom-short-read-actual-size`

```lisp
(cl-chip8:chip8-rom-short-read-actual-size condition) => integer
```

Reads the number of bytes that were actually available before end of file.

**Returns**: The byte count read before the stream ended.

**Signals**: `none` for a `chip8-rom-short-read` condition.

**Example**:

```lisp
(handler-case (cl-chip8:load-rom-file! path)
  (cl-chip8:chip8-rom-short-read (condition)
    (format t "~D of ~D bytes~%"
            (cl-chip8:chip8-rom-short-read-actual-size condition)
            (cl-chip8:chip8-rom-short-read-expected-size condition))))
```

### `chip8-rom-short-read-expected-size`

```lisp
(cl-chip8:chip8-rom-short-read-expected-size condition) => integer
```

Reads the byte count the read expected, taken from `file-length`.

**Returns**: The expected size in bytes.

**Signals**: `none` for a `chip8-rom-short-read` condition.

### `chip8-invalid-opcode`

```lisp
cl-chip8:chip8-invalid-opcode
```

Signals when an opcode does not match an implemented CHIP-8 instruction.

**Returns**: A condition class designator.

**Signals**: Not applicable; this entry names a condition class. The class is
signaled by opcode execution for an unimplemented instruction.

### `chip8-invalid-opcode-opcode`

```lisp
(cl-chip8:chip8-invalid-opcode-opcode condition) => (unsigned-byte 16)
```

Reads the rejected opcode from a `chip8-invalid-opcode` condition.

**Returns**: The invalid 16-bit opcode.

**Signals**: `none` for a `chip8-invalid-opcode` condition.

### `chip8-stack-overflow`

```lisp
cl-chip8:chip8-stack-overflow
```

Signals when `CALL` would exceed the 16-entry call stack.

**Returns**: A condition class designator.

**Signals**: Not applicable; this entry names a condition class. The class is
signaled when a call would exceed the configured stack limit.

### `chip8-stack-overflow-depth`

```lisp
(cl-chip8:chip8-stack-overflow-depth condition) => integer
```

Reads the stack depth at the failed `CALL`.

**Returns**: The number of entries already on the stack.

**Signals**: `none` for a `chip8-stack-overflow` condition.

### `chip8-stack-underflow`

```lisp
cl-chip8:chip8-stack-underflow
```

Signals when `RET` is executed with an empty call stack.

**Returns**: A condition class designator.

**Signals**: Not applicable; this entry names a condition class. The class is
signaled when a return is attempted with an empty stack.

### `chip8-memory-access-out-of-bounds`

```lisp
cl-chip8:chip8-memory-access-out-of-bounds
```

Signals when a memory span is outside the 4096-byte address space.

**Returns**: A condition class designator.

**Signals**: Not applicable; this entry names a condition class. The class is
signaled when a memory span falls outside the address space.

### `chip8-memory-access-out-of-bounds-address`

```lisp
(cl-chip8:chip8-memory-access-out-of-bounds-address condition) => integer
```

Reads the first address of a failed memory access.

**Returns**: The requested zero-based address.

**Signals**: `none` for a `chip8-memory-access-out-of-bounds` condition.

### `chip8-memory-access-out-of-bounds-span`

```lisp
(cl-chip8:chip8-memory-access-out-of-bounds-span condition) => integer
```

Reads the requested byte span of a failed memory access.

**Returns**: The requested number of bytes.

**Signals**: `none` for a `chip8-memory-access-out-of-bounds` condition.

### `chip8-rom-not-regular-file`

```lisp
cl-chip8:chip8-rom-not-regular-file
```

Signals when an existing ROM path is not a regular file.

**Returns**: A condition class designator.

**Signals**: Not applicable; this entry names a condition class. The class is
signaled when an existing ROM path is not a regular file.

### `chip8-rom-not-regular-file-path`

```lisp
(cl-chip8:chip8-rom-not-regular-file-path condition) => pathname
```

Reads the path rejected by the regular-file check that `load-rom-file!` runs
before opening a ROM.

**Returns**: The offending pathname designator.

**Signals**: `none` for a `chip8-rom-not-regular-file` condition.

## Memory

The exported memory interface is the array itself plus the two operations a
headless driver needs: clear it, and copy bytes into it. Byte-level reads and
writes go through the Prolog rulebase during instruction execution, and the
range check that guards them is internal -- `load-bytes-into-memory` applies it
on the caller's behalf, so unexported does not mean unchecked.

### `+memory-size+`

```lisp
cl-chip8:+memory-size+ => 4096
```

The size of the CHIP-8 address space in bytes.

**Returns**: The constant integer `4096`.

### `+rom-load-address+`

```lisp
cl-chip8:+rom-load-address+ => #x200
```

The first address at which a ROM is loaded.

**Returns**: The constant integer `512`.

### `*memory*` { #var-memory }

```lisp
cl-chip8:*memory* => (simple-array (unsigned-byte 8) (4096))
```

The mutable 4096-byte memory array.

**Returns**: The global memory array when read as a variable.

### `memory-reset!`

```lisp
(cl-chip8:memory-reset!) => memory-array
```

Fill `*memory*` with zero bytes.

**Returns**: `cl-chip8:*memory*`.

**Signals**: `none` for a valid memory binding.

**Example**:

```lisp
(cl-chip8:memory-reset!)
```

### `load-bytes-into-memory`

```lisp
(cl-chip8:load-bytes-into-memory bytes address) => bytes
```

Copy an octet sequence into memory beginning at `address`.

**Returns**: The supplied octet sequence.

**Signals**: `chip8-memory-access-out-of-bounds` for a negative address and
`chip8-rom-too-large` when the sequence does not fit.

**Example**:

```lisp
(cl-chip8:load-bytes-into-memory #(#x60 #x00) #x200)
```

## Display

The exported display interface covers the framebuffer array, its dimensions,
and the three operations a headless driver needs: reset it, read a pixel, and
XOR a pixel. Dirty-row bookkeeping is internal; `display-reset!` and
`display-xor-pixel!` maintain it themselves, so a caller never marks rows by
hand. Pixel access from inside instruction execution goes through the Prolog
rulebase rather than through these functions.

### `+display-width+`

```lisp
cl-chip8:+display-width+ => 64
```

The framebuffer width in pixels.

**Returns**: The constant integer `64`.

### `+display-height+`

```lisp
cl-chip8:+display-height+ => 32
```

The framebuffer height in pixels.

**Returns**: The constant integer `32`.

### `display-reset!`

```lisp
(cl-chip8:display-reset!) => display-array
```

Clear the framebuffer and mark every terminal row dirty.

**Returns**: The internal framebuffer array. It is returned for convenience
only; the array itself is not part of the public API, because its dirty-row
and locking invariants live outside it. Read pixels with
`display-pixel-value` and write them with `display-xor-pixel!`, which
maintains those invariants.

**Signals**: `none` for a valid display binding.

**Example**:

```lisp
(cl-chip8:display-reset!)
```

### `display-pixel-value`

```lisp
(cl-chip8:display-pixel-value x y) => bit
```

Read one pixel from the framebuffer. Note the argument order is `x` then `y`,
the reverse of the underlying `(aref *display* y x)` indexing.

**Returns**: `0` or `1`.

**Signals**: No `chip8-error`. Coordinates are not range-checked, so an `x`
outside `[0, 64)` or a `y` outside `[0, 32)` reaches `aref` directly and
signals the implementation's own `type-error`. Callers are responsible for
supplying in-range coordinates.

**Example**:

```lisp
(cl-chip8:display-pixel-value 0 0)
```

### `display-xor-pixel!`

```lisp
(cl-chip8:display-xor-pixel! x y) => boolean
```

XOR one pixel and mark its terminal row dirty.

**Returns**: True when a set pixel was erased, which is the CHIP-8 collision
flag.

**Signals**: No `chip8-error`. As with `display-pixel-value`, coordinates are
not range-checked; an out-of-range `x` or `y` signals the implementation's own
`type-error` from `aref`. `DXYN`'s own implementation wraps the sprite origin
and clips the sprite body before calling this, so it never passes an
out-of-range coordinate.

**Example**:

```lisp
(cl-chip8:display-xor-pixel! 0 0)
```

## Fontset

### `+fontset-address+`

```lisp
cl-chip8:+fontset-address+ => #x50
```

The memory address reserved for the built-in fontset.

**Returns**: The constant integer `80`.

### `+chip8-fontset+`

```lisp
cl-chip8:+chip8-fontset+ => 80-byte-vector
```

The 80-byte glyph table for hexadecimal digits `0` through `F`.

**Returns**: The fontset octet vector.

**Mutability**: Defined with `defparameter`, not `defconstant`. Despite the
`+name+` spelling it is a mutable special variable: it can be rebound with
`let` or assigned with `setf`, and the vector it holds can be written in
place. Treat it as read-only unless you intend to change the glyphs.

### `load-fontset-into-memory!`

```lisp
(cl-chip8:load-fontset-into-memory!) => fontset
```

Copy the built-in fontset into memory at `+fontset-address+`.

**Returns**: `cl-chip8:+chip8-fontset+`.

**Signals**: `none` for the initialized CHIP-8 memory.

**Example**:

```lisp
(cl-chip8:load-fontset-into-memory!)
```

## CPU state

### `*rulebase*`

```lisp
cl-chip8:*rulebase* => rulebase
```

The mutable `cl-prolog` rulebase holding registers, timers, keys, and control
state as dynamic facts.

**Returns**: The current rulebase when read as a variable.

### `+register-count+`

```lisp
cl-chip8:+register-count+ => 16
```

The number of general-purpose registers `V0` through `VF`.

### `+initial-pc+`

```lisp
cl-chip8:+initial-pc+ => #x200
```

The program counter used after reset.

### `+call-stack-limit+`

```lisp
cl-chip8:+call-stack-limit+ => 16
```

The maximum number of return addresses on the call stack.

### `reset-cpu-state!`

```lisp
(cl-chip8:reset-cpu-state!) => rulebase
```

Reset registers, `I`, `PC`, timers, keys, and the call stack to the initial
state.

**Returns**: `cl-chip8:*rulebase*`.

**Signals**: `none` for the initialized rulebase.

**Example**:

```lisp
(cl-chip8:reset-cpu-state!)
```

### `key-down-p`

```lisp
(cl-chip8:key-down-p key) => boolean
```

Test whether a hexadecimal CHIP-8 key is currently pressed.

**Returns**: True when `key` has a `key-down` fact.

**Signals**: `none` for a hexadecimal key value.

### `pressed-keys`

```lisp
(cl-chip8:pressed-keys) => list
```

Return all currently pressed hexadecimal keys.

**Returns**: A list of key numbers.

**Signals**: `none`.

**Example**:

```lisp
(cl-chip8:pressed-keys)
```

### `v`

```lisp
(v index value)
```

The exported Prolog fact functor for general register `Vindex`.

**Returns**: A Prolog goal when used in a query.

**Signals**: `none` for a well-formed goal.

### `i-register`

```lisp
(i-register value)
```

The exported Prolog fact functor for the `I` register.

**Returns**: A Prolog goal when used in a query.

**Signals**: `none` for a well-formed goal.

### `pc`

```lisp
(pc value)
```

The exported Prolog fact functor for the program counter.

**Returns**: A Prolog goal when used in a query.

**Signals**: `none` for a well-formed goal.

### `call-stack`

```lisp
(call-stack list)
```

The exported Prolog fact functor for the return-address stack.

**Returns**: A Prolog goal when used in a query.

**Signals**: `none` for a well-formed goal.

### `delay-timer`

```lisp
(delay-timer value)
```

The exported Prolog fact functor for the delay timer.

**Returns**: A Prolog goal when used in a query.

**Signals**: `none` for a well-formed goal.

### `sound-timer`

```lisp
(sound-timer value)
```

The exported Prolog fact functor for the sound timer.

**Returns**: A Prolog goal when used in a query.

**Signals**: `none` for a well-formed goal.

### `key-down`

```lisp
(key-down hex-key)
```

The exported Prolog fact functor for a currently pressed hexadecimal key.

**Returns**: A Prolog goal when used in a query.

**Signals**: `none` for a well-formed goal.

## Opcodes

`execute-instruction!` is the whole exported instruction interface. Fetch and
decode are sub-steps of it rather than separate entry points, and the goal
functors that the instruction rulebase dispatches on -- sprite drawing, the
ALU operations, the register store and load pair, the stack-error raisers --
are internal, because the rulebase's shape is not something this system has
committed to. For the observable behavior of individual instructions,
including the `FX55`/`FX65` and `DXYN` quirks this interpreter implements, see
[Compatibility](compatibility.md).

### `execute-instruction!`

```lisp
(cl-chip8:execute-instruction!) => no values
```

Fetch, decode, and execute exactly one instruction against `*rulebase*`,
`*memory*`, and the framebuffer.

**Returns**: No values.

**Signals**: `chip8-invalid-opcode`, `chip8-stack-overflow`,
`chip8-stack-underflow`, or `chip8-memory-access-out-of-bounds` when the
instruction requires them.

**Example**:

```lisp
(cl-chip8:reset-cpu-state!)
(cl-chip8:load-bytes-into-memory #(#x00 #xE0) cl-chip8:+rom-load-address+)
(cl-chip8:execute-instruction!)
```

## Keypad

The exported keypad interface is the pair a headless driver needs: clear the
pending hold countdowns, and advance them one tick. Everything that translates
a `cl-tty-kit` key event into a CHIP-8 key belongs to the terminal layer and is
internal, along with the host-key mapping table and the hold duration.

A headless driver does not synthesize key events. It presses a key by
asserting a `key-down` fact against `*rulebase*` and releases it by retracting
that fact, which is the same state the terminal layer ultimately produces. For
the host keyboard layout and the key-hold behavior as a user experiences them,
see the [Terminal Guide](../guide/terminal.md).

### `keypad-reset!`

```lisp
(cl-chip8:keypad-reset!) => hash-table
```

Clear pending key-hold countdowns.

**Returns**: The internal countdown table.

**Signals**: `none`.

**Example**:

```lisp
(cl-chip8:keypad-reset!)
```

## Timers

### `step-timers!`

```lisp
(cl-chip8:step-timers!) => no values
```

Decrement the delay and sound timers by one, flooring both at zero. The app
calls this once per 60 Hz tick, independently of the CPU clock.

**Returns**: No values.

**Signals**: `none`.

**Example**:

```lisp
(cl-chip8:step-timers!)
```

## ROM loading

`load-rom-file!` is the whole exported ROM interface. The regular-file check
and the size-bounded file read it performs are internal steps, applied
unconditionally on every call: unexporting them removed two names, not two
guards. The conditions they signal stay public, so a caller still handles every
failure they can produce.

### `load-rom-file!`

```lisp
(cl-chip8:load-rom-file! path) => octet-vector
```

Validate and load a ROM at `+rom-load-address+`; the maximum ROM size is 3584
bytes.

**Returns**: The loaded ROM octet vector.

**Signals**: `chip8-rom-not-regular-file` for an existing directory, device,
FIFO, or other non-regular path; `chip8-rom-too-large` when the file exceeds
the 3584-byte limit, checked against `file-length` before any byte is read;
`chip8-rom-short-read` when the stream reaches end of file early, for example
because the file was truncated during the read; and the underlying file
condition for a missing path.

**Example**:

```lisp
(cl-chip8:reset-cpu-state!)
(cl-chip8:load-rom-file! #p"roms/PONG.ch8")
```

## Rendering

`render-chip8!` is the exported whole-frame operator; it draws both the
playfield and the sound indicator. The sub-step renderers behind it, the
half-block glyph selection, and the playfield origin offsets are internal.
The two screen dimensions stay public because a caller must size the screen it
hands to `render-chip8!` or `render-chip8-concurrently!` -- a wrong-sized
screen clips silently rather than signalling.

### `+screen-width+`

```lisp
cl-chip8:+screen-width+ => 66
```

The terminal screen width: 64 playfield columns plus a one-cell border on
each side.

### `+screen-height+`

```lisp
cl-chip8:+screen-height+ => 18
```

The terminal screen height: 16 half-block rows plus a one-cell border on each
side.

### `sound-timer-active-p`

```lisp
(cl-chip8:sound-timer-active-p) => boolean
```

Test whether the sound timer is nonzero.

**Returns**: True when the sound timer is nonzero; otherwise nil.

**Signals**: `none` for an initialized CHIP-8 state.

### `render-chip8!`

```lisp
(cl-chip8:render-chip8! screen) => screen
```

Render the display and sound indicator into a screen on the caller thread.

**Returns**: `screen`.

**Signals**: Screen conditions for an incompatible `screen` value.

**Example**:

```lisp
(cl-chip8:render-chip8! screen)
```

## Concurrent rendering

The concurrent renderer parallelizes only pure row-to-character conversion.
Display reads and all screen mutations remain on the caller thread. Use the
pipeline macro for normal lifecycle management.

The exported surface is the pipeline type, its predicate, and the three
lifecycle operators that create, use, and close it. The tuning knobs and the
telemetry counters are internal: they expose the batching strategy, and the
parallel threshold cannot determine behavior on its own -- it is combined with
an internal minimum batch size.

### `chip8-render-pipeline`

```lisp
cl-chip8:chip8-render-pipeline
```

The persistent rendering pipeline type. It names a structure class, not a
constructor; build an instance with `make-chip8-render-pipeline` or
`with-chip8-render-pipeline`.

The type is exported so that a caller can name it in a `handler-case`.
`close-chip8-render-pipeline` and `render-chip8-concurrently!` both
`check-type` their `pipeline` argument against it, so passing a non-pipeline
signals a `type-error` that mentions this type; without the exported name a
caller could provoke that error but not write a clause for it.

**Returns**: A structure class designator, not a callable function.

**Signals**: Not applicable; this entry names a type.

**Example**:

```lisp
;; Name the type in your own guard,
(check-type pipeline cl-chip8:chip8-render-pipeline)

;; or handle the type-error the library's own check raises.
(handler-case (cl-chip8:render-chip8-concurrently! screen pipeline)
  (type-error (condition)
    (format t "expected ~S~%" (type-error-expected-type condition))))
```

### `with-chip8-render-pipeline`

```lisp
(cl-chip8:with-chip8-render-pipeline (pipeline &rest initargs) &body body)
```

Create a persistent rendering pipeline, evaluate `body`, and close the
pipeline during unwinding.

**Returns**: The values produced by `body`.

**Signals**: Conditions from pipeline construction, `body`, or cleanup.

**Example**:

```lisp
(cl-chip8:with-chip8-render-pipeline (pipeline :parallelism 4)
  (cl-chip8:render-chip8-concurrently! screen pipeline))
```

### `chip8-render-pipeline-p`

```lisp
(cl-chip8:chip8-render-pipeline-p object) => boolean
```

Test whether `object` is a rendering pipeline.

**Returns**: True for a rendering pipeline; otherwise nil.

**Signals**: `none`.

### `make-chip8-render-pipeline`

```lisp
(cl-chip8:make-chip8-render-pipeline
 &key (parallelism 4) (parallel-threshold 13)
      (shutdown-timeout (duration-of-seconds 1)))
  => pipeline
```

Create a persistent bounded worker pipeline. Partial frames use workers only
when their dirty-row count meets the configured threshold and internal
minimum; full frames use the serial path. `shutdown-timeout` defaults to a
one-second duration and is retained on the pipeline as the default timeout for
`close-chip8-render-pipeline`.

**Returns**: A persistent rendering pipeline.

**Signals**: `type-error` for invalid numeric or duration options, or a worker
startup condition.

**Example**:

```lisp
(cl-chip8:make-chip8-render-pipeline :parallelism 4)
```

### `close-chip8-render-pipeline`

```lisp
(cl-chip8:close-chip8-render-pipeline pipeline &key timeout) => pipeline
```

Close the pipeline's channels and workers. Closing is idempotent and serialized
with rendering. `timeout` defaults to the `shutdown-timeout` the pipeline was
created with, which is itself `(duration-of-seconds 1)` unless overridden.

**Returns**: `pipeline`.

**Signals**: An error if the native worker shutdown cannot complete within the
requested duration.

**Example**:

```lisp
(cl-chip8:close-chip8-render-pipeline pipeline)
```

### `render-chip8-concurrently!`

```lisp
(cl-chip8:render-chip8-concurrently! screen pipeline) => screen
```

Render the CHIP-8 display through `pipeline`, preserving caller-thread screen
mutation and immutable worker snapshots.

**Returns**: `screen`.

**Signals**: `type-error` for an invalid `pipeline`, or an error when the
pipeline is closed or a worker reports a failure.

**Example**:

```lisp
(cl-chip8:render-chip8-concurrently! screen pipeline)
```

## App

`run` is the exported entry point. It returns a `chip8-app` and stores a
mid-run failure on it rather than signalling, so the type, its predicate, and
the two slots that carry the outcome -- `chip8-app-quitp` and
`chip8-app-error` -- are part of `run`'s contract and are documented here. The
constructor and the remaining slots are internal wiring, as is the default
clock rate, whose value appears in `run`'s signature below.

### `chip8-app`

```lisp
cl-chip8:chip8-app
```

The runtime state structure used by the realtime tick loop, and the type `run`
returns. Machine state itself remains in the rulebase, memory array, display
array, and keypad facts.

**Returns**: A structure class designator, not a callable function.

**Signals**: Not applicable; this entry names a type.

### `chip8-app-p`

```lisp
(cl-chip8:chip8-app-p object) => boolean
```

Test whether `object` is a `chip8-app`.

**Returns**: True for a `chip8-app`; otherwise nil.

**Signals**: `none`.

### `chip8-app-quitp`

```lisp
(cl-chip8:chip8-app-quitp app) => boolean
```

Read whether the realtime loop should stop.

**Returns**: True when the realtime loop should stop; otherwise nil.

**Signals**: `type-error` when `app` is not a `chip8-app`.

### `chip8-app-error`

```lisp
(cl-chip8:chip8-app-error app) => condition-or-nil
```

Read an execution condition saved for reporting after terminal cleanup.

**Returns**: The saved execution condition, or nil.

**Signals**: `type-error` when `app` is not a `chip8-app`.

### `run`

```lisp
(cl-chip8:run &key rom-path (clock-hz 700) (stream *standard-output*))
  => app
```

Reset the machine, load `rom-path`, and run it in a raw alternate terminal
screen until Escape or Ctrl-C. The returned app contains any execution error
that occurred during the loop.

Every argument is a keyword; there is no positional ROM parameter. `run`
requires a live terminal, because it puts the terminal into raw mode on the
alternate screen before entering the loop. It resets all global machine state
-- CPU rulebase, memory, display, fontset, keypad -- on entry, so it is not
re-entrant and must not be called from two threads against the same image.

**Returns**: The final `chip8-app` state.

**Signals**: File and initialization conditions before the terminal session;
runtime conditions are stored in `chip8-app-error` and end the loop.

**Example**:

```lisp
(cl-chip8:run :rom-path #p"roms/PONG.ch8" :clock-hz 700)
```

## CLI

### `*app*` { #var-app }

```lisp
cl-chip8:*app* => cl-cli application
```

The declarative `cl-cli` specification for the `cl-chip8` command.

### `main`

```lisp
(cl-chip8:main) => implementation-dependent
```

Parse the current process arguments with `*app*` and exit with the command's
status code.

**Returns**: Does not return normally; `host-kit:quit` exits with the command
status.

**Signals**: CLI parsing conditions are reported before the command exits.

**Example**:

```lisp
(cl-chip8:main)
```

### `image-entry-point`

```lisp
(cl-chip8:image-entry-point) => implementation-dependent
```

Entry point used by the delivered executable; it has the same CLI behavior as
`main`.

**Returns**: Does not return normally; `host-kit:quit` exits with the command
status.

**Signals**: CLI parsing conditions are reported before the command exits.

**Example**:

```lisp
(cl-chip8:image-entry-point)
```
