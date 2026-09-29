# API reference

The public package is `cl-chip8`. This page lists the symbols exported by
`src/package.lisp`; implementation-only symbols are omitted.

## Conditions

`chip8-error`, `chip8-rom-too-large`, `chip8-rom-too-large-size`,
`chip8-rom-too-large-available`, `chip8-rom-short-read`,
`chip8-rom-short-read-actual-size`, `chip8-rom-short-read-expected-size`,
`chip8-invalid-opcode`, `chip8-invalid-opcode-opcode`, `chip8-stack-overflow`,
`chip8-stack-overflow-depth`, `chip8-stack-underflow`,
`chip8-memory-access-out-of-bounds`, `chip8-memory-access-out-of-bounds-address`,
`chip8-memory-access-out-of-bounds-span`, `chip8-rom-not-regular-file`,
`chip8-rom-not-regular-file-path`, `chip8-cps-error`, `chip8-cps-error-phase`,
`chip8-cps-error-cause`, `chip8-config-error`, `chip8-config-error-source-name`,
`chip8-config-error-line`, `chip8-config-error-column`,
`chip8-config-error-path`, `chip8-config-error-key`, and
`chip8-config-error-reason` name condition classes or their readers.

## Constants and types

The constants are `+memory-size+`, `+rom-load-address+`, `+register-count+`,
`+initial-pc+`, `+call-stack-limit+`, `+display-width+`, `+display-height+`,
`+fontset-address+`, `+chip8-fontset+`, `+screen-width+`, and
`+screen-height+`.

The exported type names are `chip8-octet`, `chip8-nibble`, `chip8-opcode`,
`chip8-key`, `chip8-memory-index`, `chip8-program-counter`, and
`chip8-framebuffer`.

## Machine and profiles

`chip8-machine`, `chip8-machine-p`, `make-chip8-machine`, `chip8-reset!`, and
the readers `chip8-machine-memory`, `chip8-machine-v`,
`chip8-machine-register`, `chip8-machine-i`, `chip8-machine-pc`,
`chip8-machine-sp`, `chip8-machine-stack`, `chip8-machine-delay-timer`,
`chip8-machine-sound-timer`, `chip8-machine-keypad`,
`chip8-machine-framebuffer`, `chip8-machine-quirks`,
`chip8-machine-waiting`, and `chip8-machine-instructions` manage a machine.

`chip8-quirks`, `chip8-quirks-p`, `make-chip8-quirks`, `merge-chip8-quirks`,
`chip8-quirks-profile`, `chip8-quirks-vf-behavior`, `chip8-quirks-memory-i`,
`chip8-quirks-display-wait`, `chip8-quirks-clipping`,
`chip8-quirks-shift-source`, `chip8-quirks-bnnn-register`, and
`chip8-quirks-fx0a-completion` manage profiles and overrides.

## Execution and I/O

`memory-reset!`, `load-bytes-into-memory`, `check-memory-access`,
`memory-read`, `load-fontset-into-memory!`, `load-rom`, and `load-rom-file`
load and inspect memory. `display-reset!`, `display-pixel-value`,
`display-xor-pixel!`, `chip8-framebuffer`, and `chip8-framebuffer-snapshot`
operate on the framebuffer.

`fetch-opcode`, `execute-instruction!`, `step-timers!`,
`sound-timer-active-p`, `keypad-reset!`, `key-down-p`, `pressed-keys`,
`chip8-key-down!`, and `chip8-key-up!` provide execution and input.

`chip8-run-result`, `chip8-run-result-status`, `chip8-run-result-executed`,
`chip8-run-result-machine`, `chip8-run-result-continuation`,
`chip8-run-instructions`, `chip8-run-ticks`, and `chip8-resume!` run a machine
without a terminal.

## Control, rendering, and application

`chip8-control-event`, `chip8-control-event-p`, `make-chip8-control-event`,
`chip8-control-event-type`, `chip8-control-event-value`,
`*chip8-state-machine-definition*`, `make-chip8-control-state-machine`,
`chip8-control-state`, and `step-chip8-control-state` describe events and
state transitions.

`render-chip8!`, `render-chip8-concurrently!`, and
`with-chip8-render-pipeline` are the public rendering operations. The package
also exports `chip8-app`, `make-chip8-app`,
`chip8-app-machine`, `chip8-app-state-machine`, `chip8-app-renderer`,
`chip8-app-decoder`, `chip8-app-render-pipeline`, `chip8-app-clock-hz`,
`chip8-app-quit-p`, `chip8-app-error`, `chip8-app-instruction-remainder`,
`chip8-app-paused-p`, `chip8-app-started-at`, and `run`.

## Configuration, logs, metrics, and CLI

`chip8-config`, `chip8-config-rom-path`, `chip8-config-clock-hz`,
`chip8-config-quirks`, `chip8-config-log-path`, `merge-chip8-config`,
`load-chip8-config-file`, and `make-chip8-config-from-sources` handle TOML and
CLI configuration.

`make-chip8-logger`, `close-chip8-logger`, `chip8-log`, `chip8-log-info`,
`chip8-log-error`, and `flush-chip8-logger` provide structured logging.
`chip8-metrics`, `make-chip8-metrics`, `chip8-metric-add`, `chip8-metric-set`,
`flush-chip8-metrics!`, `finalize-chip8-metrics!`,
`chip8-metrics-snapshot`, and `chip8-metrics-fields` provide metrics.

`chip8-run-options`, `*app*`, `main`, and `image-entry-point` are the CLI
entry points.
