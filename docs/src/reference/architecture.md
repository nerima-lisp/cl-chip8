# Architecture

The public runtime separates machine state, terminal rendering, and process
lifecycle so that applications can embed the CPU without adopting the
interactive terminal loop.

## State ownership

CPU registers, timers, the program counter, the call stack, and keypad facts
are stored in the cl-prolog-kit rulebase. The memory and display framebuffer are
direct Lisp arrays. Opcode foreign predicates are the boundary between the
declarative instruction rules and those arrays.

`run` owns the interactive lifecycle: it resets the machine, loads the
fontset and ROM, configures raw terminal input, executes instructions, steps
timers, and renders frames. An embedding can instead drive those steps itself
through the exported reset operators (`reset-cpu-state!`, `memory-reset!`,
`display-reset!`, `keypad-reset!`), the loaders (`load-fontset-into-memory!`,
`load-rom-file!`), `execute-instruction!`, `step-timers!`, and `render-chip8!`
or `render-chip8-concurrently!`.

There is no exported input operator. Key-event decoding belongs to the
terminal layer, so a headless embedding presses a key by asserting a
`key-down` fact against `*rulebase*` and releases it by retracting that fact.
[Core Concepts](../guide/core-concepts.md) shows the call.

## Rendering pipeline

`make-chip8-render-pipeline` creates a persistent bounded worker pipeline.
`render-chip8-concurrently!` follows these rules:

1. The caller thread reads the display and takes immutable row snapshots.
2. Worker tasks convert snapshots into terminal characters only.
3. The caller thread commits characters to the terminal screen.

Small partial updates use a serial path. With the default settings, the
pipeline has 8 workers, partial frames become eligible for workers at a
threshold of 13 dirty rows, and the implementation requires at least 9 partial
snapshots before submitting work. A batch uses no more workers than its row
count requires. Full dirty frames remain serial. The pipeline does maintain
counters for submitted, completed, and serial rows, plus executor queue depth
and high-water mark, but none of them is exported: they are telemetry over the
batching strategy and carry no compatibility promise. An embedding cannot
observe which path a frame took through the public API.

The serial full-frame renderer reuses its row-character buffer between calls.
Concurrent rendering keeps its snapshot and result buffers on the persistent
pipeline, so worker jobs never share the serial renderer's mutable buffer.
`DXYN` holds the display lock for the whole sprite operation and marks each
touched display row after its bit loop; this keeps pixel, collision, and
dirty-row state changes atomic without acquiring the lock for every pixel.

Use `with-chip8-render-pipeline` for exception-safe lifecycle management. A
pipeline must be closed before its owning application or terminal resources
are discarded; `close-chip8-render-pipeline` accepts a timeout for bounded
shutdown.
