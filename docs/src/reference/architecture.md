# Architecture

The source is split by responsibility:

| Area | Files | Responsibility |
|---|---|---|
| Platform and machine state | `types.lisp`, `machine-types.lisp`, `machine.lisp`, `platforms.lisp`, `quirks.lisp`, `fontset.lisp` | Types, machine construction and reset, platform capabilities and defaults, font sets, and compatibility profiles. |
| CPU execution | `memory.lisp`, `rom.lisp`, `rom-database-data.lisp`, `rom-database.lisp`, `opcode-data.lisp`, `opcode-dispatch.lisp`, `opcode-execution.lisp`, `opcode-cps.lisp`, `timers.lisp`, `keypad.lisp` | Memory, ROM loading and identification, opcode dispatch and effects, waits, timers, and input. |
| Display and rendering | `display-types.lisp`, `display.lisp`, `render-types.lisp`, `render.lisp`, `concurrent-render-types.lisp`, `concurrent-render-macros.lisp`, `concurrent-render.lisp`, `concurrent-render-rows.lisp` | Logical display operations over the physical two-plane framebuffer, adaptive terminal rendering, and concurrent row conversion. |
| State transitions and headless execution | `control-events.lisp`, `state-machine.lisp`, `control-cps.lisp`, `headless.lisp` | Control events, application states, continuations, and terminal-free execution. |
| Terminal application and audio | `app-types.lisp`, `app.lisp`, `audio.lisp`, `audio-output.lisp`, `config.lisp`, `cli.lisp` | Terminal lifecycle, PCM and bell output, TOML and source precedence, and CLI entry points. |
| Observability | `logging.lisp`, `metrics.lisp` | Structured JSON logging and runtime metrics. |

`chip8-machine` owns CPU registers, memory, timers, keypad, framebuffer,
platform, quirks, wait state, and instruction counter. Machine state is passed
explicitly to CPU and headless APIs, so independent runs do not share mutable
interpreter state. ROM metadata is matched against its SHA-1 digest and
participates in platform, quirk, clock, and color selection.

Opcode metadata is declared in `opcode-data.lisp`; dispatch and execution
consume that declaration. The normal instruction path is direct.
Continuation-passing style (CPS) is used only at interruption boundaries such
as `FX0A`, display wait, and resume.

Headless execution returns a `chip8-run-result` with status, executed count,
machine, and any continuation. The terminal application shares the machine
and instruction implementation with the headless API, but has its own tick
and control loop. It advances timers, executes instructions, and handles app
control state directly. The app selects a display mode based on machine
resolution and terminal size, then passes logical framebuffer snapshots to
the renderer. Renderers keep their own row-diff state and do not mutate
machine state.
