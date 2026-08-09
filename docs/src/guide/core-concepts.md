# Core Concepts

cl-chip8 models a classic CHIP-8 machine as a small stateful runtime. A ROM
is loaded at address `0x200`; the machine has 4,096 bytes of memory, sixteen
8-bit registers, a 16-bit `I` register, a call stack, a 64x32 monochrome
display, a sixteen-key keypad, and delay and sound timers.

## State and execution

The CPU facts live in a [cl-prolog](https://github.com/nerima-lisp/cl-prolog)
rulebase. The public facts are `v(Index, Value)`, `i-register(Value)`,
`pc(Value)`, `call-stack(List)`, `delay-timer(Value)`, `sound-timer(Value)`,
and `key-down(Key)`. Memory and display pixels use Lisp arrays because they
are dense structures that need direct indexed access.

One instruction follows this boundary:

1. `fetch-opcode` reads two bytes at the program counter.
2. `decode-opcode` returns the family and hexadecimal fields of the opcode.
3. `execute-instruction!` resolves the corresponding declarative rule and
   advances the machine state.

The CPU clock and timer clock are separate. `run` executes instructions at
the requested clock rate, while `step-timers!` decrements both timers at the
fixed 60 Hz CHIP-8 rate.

## Reset and embedding

An embedding that drives the machine manually should initialize the state
before loading a ROM:

```lisp
(cl-chip8:reset-cpu-state!)
(cl-chip8:memory-reset!)
(cl-chip8:display-reset!)
(cl-chip8:load-fontset-into-memory!)
(cl-chip8:load-rom-file! #p"/path/to/rom.ch8")
(cl-chip8:keypad-reset!)
```

Call `execute-instruction!` for CPU steps and `step-timers!` at 60 Hz.

There is no exported function for delivering input. Key-event decoding belongs
to the terminal layer, so a headless embedding drives the keypad by asserting
and retracting `key-down` facts directly against `*rulebase*`. The query
builtins come from `cl-prolog`, which `cl-chip8` imports but does not
re-export, so name that package explicitly:

```lisp
;; Press CHIP-8 key 5.
(cl-prolog:query-prolog cl-chip8:*rulebase*
                        '(cl-prolog:assertz (cl-chip8:key-down 5)))

;; The interpreter now sees it: EX9E/EXA1/FX0A all read this fact.
(cl-chip8:key-down-p 5)   ; => true
(cl-chip8:pressed-keys)   ; => (5)

;; Release it.
(cl-prolog:query-prolog cl-chip8:*rulebase*
                        '(cl-prolog:retract (cl-chip8:key-down 5)))
```

Both the functor `cl-chip8:key-down` and the builtins `cl-prolog:assertz` and
`cl-prolog:retract` must be those exact symbols: the engine dispatches on
symbol identity, so a same-named symbol interned in another package will not
match. Do not call the internal key-hold countdown machinery; it belongs to
the terminal layer, and a fact you asserted yourself has no countdown entry to
advance. The [API reference](../reference/api.md) lists the lower-level
functions and their conditions.

## Declarative opcode semantics

The opcode table is expressed as Prolog clauses. Lisp foreign predicates
bridge operations that need dense array access, bit iteration, randomness, or
Lisp condition signaling. This keeps instruction selection declarative while
leaving memory and display operations direct and bounded.
