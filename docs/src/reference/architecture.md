# Architecture

The source is split by responsibility:

| Area | Files | Responsibility |
|---|---|---|
| Data and machine state | `types.lisp`, `machine-types.lisp`, `machine.lisp`, `quirks.lisp`, `fontset.lisp` | Types, constants, machine construction, reset, fontset, and profiles. |
| CPU execution | `memory.lisp`, `rom.lisp`, `opcode-data.lisp`, `opcode-dispatch.lisp`, `opcode-execution.lisp`, `opcode-cps.lisp`, `timers.lisp`, `keypad.lisp` | Memory, ROM loading, opcode dispatch, instruction effects, waits, timers, and input. |
| State transitions | `control-events.lisp`, `state-machine.lisp`, `control-cps.lisp`, `headless.lisp` | Control events, application states, continuations, and terminal-free execution. |
| Terminal I/O | `app-types.lisp`, `app.lisp`, `config.lisp`, `logging.lisp`, `metrics.lisp`, `cli.lisp` | Terminal lifecycle, TOML, JSON logging, metrics, and CLI entry points. |
| Rendering | `display-types.lisp`, `display.lisp`, `render-types.lisp`, `render.lisp`, `concurrent-render-types.lisp`, `concurrent-render-macros.lisp`, `concurrent-render.lisp`, `concurrent-render-rows.lisp` | Framebuffer operations, serial rendering, and concurrent row conversion. |

`chip8-machine` owns CPU registers, memory, timers, keypad, framebuffer,
quirks, wait state, and the instruction counter. The machine is passed
explicitly to CPU and headless APIs, so independent runs do not share mutable
interpreter state.

Opcode metadata is declared in `opcode-data.lisp`; dispatch and execution
consume that declaration. The normal instruction path is direct. CPS is used
only at interruption boundaries such as `FX0A`, display wait, and resume.

Headless execution returns a `chip8-run-result` with status, executed count,
machine, and any continuation. The terminal application builds on this API,
while rendering receives framebuffer snapshots and keeps its own row-diff state.
