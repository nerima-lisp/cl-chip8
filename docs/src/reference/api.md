# API reference

The public package is `cl-chip8`. Its exported symbols are declared in
`src/package.lisp`; this page groups the public machine, execution, rendering,
configuration, and application interfaces. Implementation-only symbols are
omitted.

## Conditions

`chip8-error`, `chip8-rom-too-large`, `chip8-rom-too-large-size`,
`chip8-rom-too-large-available`, `chip8-rom-short-read`,
`chip8-rom-short-read-actual-size`, `chip8-rom-short-read-expected-size`,
`chip8-invalid-opcode`, `chip8-invalid-opcode-opcode`, `chip8-stack-overflow`,
`chip8-stack-overflow-depth`, `chip8-stack-underflow`,
`chip8-memory-access-out-of-bounds`,
`chip8-memory-access-out-of-bounds-address`,
`chip8-memory-access-out-of-bounds-span`, `chip8-rom-not-regular-file`,
`chip8-rom-not-regular-file-path`, `chip8-cps-error`,
`chip8-cps-error-phase`, `chip8-cps-error-cause`, `chip8-config-error`,
`chip8-config-error-source-name`, `chip8-config-error-line`,
`chip8-config-error-column`, `chip8-config-error-path`,
`chip8-config-error-key`, `chip8-config-error-reason`,
`chip8-unsupported-platform`, and `chip8-unsupported-platform-name` name
condition classes and their readers. See [Conditions](conditions.md) for when
they are signaled.

## Constants and types

The exported constants are `+memory-size+` (4096), `+maximum-memory-size+`
(65536), `+rom-load-address+`, `+register-count+`, `+initial-pc+`,
`+call-stack-limit+`, `+display-width+` and `+display-height+` (64 by 32),
`+physical-display-width+` and `+physical-display-height+` (128 by 64),
`+fontset-address+`, `+chip8-fontset+`, `+screen-width+`, and
`+screen-height+`. `chip8-framebuffer` is the exported framebuffer type name.

## Machine and platform

`chip8-machine`, `chip8-machine-p`, `make-chip8-machine`, and
`chip8-reset!` create and reset machine state. The constructor accepts
`:platform` (default `:modern`), optional `:memory-size` (4096 or 65536), and
optional `:quirks` (a `chip8-quirks` value). If omitted, memory size and
quirks come from the selected platform. Its call shape is
`(make-chip8-machine &key (platform :modern) memory-size quirks)`.

Machine readers include `chip8-machine-memory`,
`chip8-machine-memory-size`, `chip8-machine-platform`, `chip8-machine-v`,
`chip8-machine-register`, `chip8-machine-i`, `chip8-machine-pc`,
`chip8-machine-sp`, `chip8-machine-stack`, `chip8-machine-delay-timer`,
`chip8-machine-sound-timer`, `chip8-machine-keypad`,
`chip8-machine-framebuffer`, `chip8-machine-quirks`,
`chip8-machine-waiting`, `chip8-machine-instructions`,
`chip8-machine-audio-pattern`, and `chip8-machine-pitch`.

`chip8-platform`, `chip8-platform-p`, `chip8-platform-name`,
`chip8-platform-memory-size`, `chip8-platform-resolutions`,
`chip8-platform-font-sets`, `chip8-platform-default-tickrate`,
`chip8-platform-default-quirks`, and `find-chip8-platform` inspect platform
definitions. `chip8-machine-resolution`,
`set-chip8-machine-resolution!`, `chip8-machine-logical-width`,
`chip8-machine-logical-height`, `chip8-machine-plane-mask`, and
`set-chip8-machine-plane-mask!` inspect or change display state. The physical
framebuffer stores 2-bit pixels; snapshots use the current logical size and
return each pixel's full 2-bit value (bit 0 for plane 1 and bit 1 for plane 2)
without applying the selected plane mask. `chip8-wait-state-pc` reads a wait
state's saved PC.

`chip8-quirks`, `chip8-quirks-p`, `make-chip8-quirks`, `merge-chip8-quirks`,
`chip8-quirks-profile`, `chip8-quirks-vf-behavior`,
`chip8-quirks-memory-i`, `chip8-quirks-display-wait`,
`chip8-quirks-clipping`, `chip8-quirks-shift-source`,
`chip8-quirks-bnnn-register`, `chip8-quirks-fx0a-completion`,
`chip8-quirks-lores-sprite`, `chip8-quirks-collision`,
`chip8-quirks-lores-scroll`, and `chip8-quirks-mode-switch-clear` create and
inspect profile settings.

## Execution and I/O

`memory-reset!`, `load-bytes-into-memory`, `check-memory-access`,
`memory-read`, `load-fontset-into-memory!`, `load-rom`, and `load-rom-file`
load and inspect memory. `check-memory-access` takes `(machine address span)`,
where `span` is the number of bytes. `load-rom` accepts an octet vector and
optional `:address`, which defaults to `+rom-load-address+`; its call shape is
`(load-rom machine bytes &key (address +rom-load-address+))`.

`display-reset!`, `display-pixel-value`, `display-xor-pixel!`,
`chip8-framebuffer`, and `chip8-framebuffer-snapshot` operate on display state.
Display coordinates use the current logical resolution. Snapshot and display
mutation functions synchronize access; callers should not mutate the raw
`chip8-machine-framebuffer` array directly. `display-pixel-value` and
`display-xor-pixel!` accept `(machine x y &optional plane-mask)`; the default
mask is the machine's selected plane mask.

`fetch-opcode`, `execute-instruction!`, `step-timers!`,
`sound-timer-active-p`, `keypad-reset!`, `key-down-p`, `pressed-keys`,
`chip8-key-down!`, and `chip8-key-up!` provide execution and input.
`chip8-run-result`, `chip8-run-result-status`, `chip8-run-result-executed`,
`chip8-run-result-machine`, `chip8-run-result-continuation`,
`chip8-run-instructions`, `chip8-run-ticks`, and `chip8-resume!` run a machine
without a terminal. The headless runners return `:completed`, `:waiting`, or
`:halted` in the result status. `chip8-run-instructions` accepts
`(machine count &key on-wait)`; `chip8-run-ticks` accepts
`(machine ticks &key (instructions-per-tick 1) on-wait)`.

`find-rom-record` accepts ROM bytes or a 40-character SHA-1 string, and
returns a matching record or `nil`. `resolve-chip8-clock-hz` resolves the
clock from explicit values, ROM and platform tickrates, and a fallback.

## Rendering and application

`render-chip8!`, `set-chip8-render-palette!`,
`render-chip8-concurrently!`, and `with-chip8-render-pipeline` are the public
rendering operations. `set-chip8-render-palette!` accepts a list of two or four
`#RRGGBB` strings. `chip8-control-event`, `chip8-control-event-p`,
`make-chip8-control-event`, `chip8-control-event-type`,
`chip8-control-event-value`, `*chip8-state-machine-definition*`,
`make-chip8-control-state-machine`, `chip8-control-state`, and
`step-chip8-control-state` describe events and state transitions.

`chip8-app`, `make-chip8-app`, `chip8-app-machine`,
`chip8-app-state-machine`, `chip8-app-renderer`, `chip8-app-decoder`,
`chip8-app-render-pipeline`, `chip8-app-clock-hz`, `chip8-app-quit-p`,
`chip8-app-error`, `chip8-app-instruction-remainder`,
`chip8-app-paused-p`, `chip8-app-started-at`, and `run` expose the terminal
application. `run` accepts `:rom-path` or `:rom-bytes`, `:clock-hz`,
`:platform`, `:quirks`, `:stream`, `:audio-mode`, and `:on-audio-fallback`.
Its call shape is `(run &key rom-path rom-bytes (clock-hz 700)
(platform :modern) quirks (stream *standard-output*) (audio-mode :off)
on-audio-fallback)`. Audio mode accepts `:auto`, `:pcm`, `:bell`, or `:off`.
The CLI default is `auto`.

## Configuration, logs, metrics, and CLI

`chip8-config`, `chip8-config-rom-path`, `chip8-config-rom-sha1`,
`chip8-config-clock-hz`, `chip8-config-clock-source`,
`chip8-config-platform`, `chip8-config-platform-source`,
`chip8-config-quirks`, `chip8-config-quirks-source`,
`chip8-config-colors-pixels`, `chip8-config-colors-source`,
`chip8-config-log-path`, `merge-chip8-config`, `load-chip8-config-file`, and
`make-chip8-config-from-sources` handle configuration sources.

`make-chip8-logger`, `close-chip8-logger`, `chip8-log`, `chip8-log-info`,
`chip8-log-error`, and `flush-chip8-logger` provide structured logging.
`chip8-metrics`, `make-chip8-metrics`, `chip8-metric-add`, `chip8-metric-set`,
`flush-chip8-metrics!`, `finalize-chip8-metrics!`,
`chip8-metrics-snapshot`, and `chip8-metrics-fields` provide metrics.

`chip8-run-options`, `*app*`, `main`, and `image-entry-point` are the CLI
entry points.
