;;;; src/package.lisp -- the sole DEFPACKAGE form for this repository.
;;;;
;;;; CODING_STANDARD.md requires `:use` to name only #:cl and every sibling
;;;; package to come in through `:import-from`, so the import list below is
;;;; the price of that rule, not an oversight.
;;;;
;;;; Stage 1 built the CPU state core: the Prolog rulebase of dynamic facts
;;;; (state.lisp), the memory and display arrays and their foreign
;;;; predicates (memory.lisp, display.lisp), and the fontset (fontset.lisp).
;;;; This stage adds the opcode rulebase (opcodes.lisp), keypad decoding
;;;; (keypad.lisp), 60Hz timer stepping (timers.lisp), ROM loading (rom.lisp),
;;;; terminal rendering (render.lisp), and the realtime app/CLI (app.lisp,
;;;; cli.lisp) -- hence the #:cl-tty-kit and #:cl-cli import-from clauses
;;;; below, added now that this stage's code needs them.
(in-package #:cl-user)

(defpackage #:cl-chip8
  (:use #:cl)
  ;; cl-prolog (L1): the rulebase container, the query API, and the
  ;; assert/retract/define-foreign-predicate primitives this package's CPU
  ;; state is built from. #:assert is deliberately NOT imported: this
  ;; package never calls it (ASSERTZ covers every insertion this stage
  ;; needs), which avoids a name clash with CL:ASSERT that would otherwise
  ;; require a :SHADOWING-IMPORT-FROM.
  ;;
  ;; IS is this stage's addition: the opcode rulebase (opcodes.lisp)
  ;; evaluates arithmetic (PC/I/register updates, BCD digits, ALU flags) via
  ;; `is/2` goals inside clause bodies. FRESH-LOGIC-VARIABLE lets a foreign
  ;; predicate build a throwaway logic variable for a retract pattern (see
  ;; LOAD-REGISTERS in opcodes.lisp) without reusing a caller-visible name.
  ;; Goal functors like `is` must come in by exact symbol identity, same as
  ;; ASSERTZ/RETRACT above: the engine's builtin dispatch matches by EQL on
  ;; the interned CL-PROLOG symbol, not by name, so a same-named
  ;; CL-CHIP8::IS the reader might otherwise intern here would silently
  ;; fail to dispatch. Arithmetic *sub-expression* operators inside an is/2
  ;; expression (+, -, mod, //, *, ...) do NOT need this treatment: cl-prolog
  ;; resolves those by STRING= on the symbol's name, so the plain CL symbols
  ;; already inherited via :USE #:CL (or even a fresh CL-CHIP8:: symbol for
  ;; a non-CL name like `//') work without any import.
  (:import-from #:cl-prolog
                #:make-rulebase
                #:query-prolog
                #:prolog-succeeds-p
                #:solution-binding
                #:assertz
                #:retract
                #:retractall
                #:define-foreign-predicate
                #:unify
                #:logic-substitute
                #:is
                #:fresh-logic-variable
                ;; EXTEND-RULEBASE is the rule DSL macro opcodes.lisp uses to
                ;; add the ~35-instruction STEP rulebase on top of
                ;; *RULEBASE*. Like IS above, a macro also needs exact-symbol
                ;; import: without it, a bare `extend-rulebase' token here
                ;; would intern a fresh, unbound CL-CHIP8::EXTEND-RULEBASE
                ;; and the compiler would try to evaluate `(extend-rulebase
                ;; ...)' as an ordinary function call -- evaluating each
                ;; quoted-looking clause literal as code in the process,
                ;; which is exactly the "illegal function call" this import
                ;; was added to fix.
                #:extend-rulebase)
  ;; cl-tty-kit (L1): key-event introspection and input decoding for the
  ;; keypad (keypad.lisp), the screen/renderer/style types and tick loop for
  ;; the realtime app (render.lisp, app.lisp), and raw-mode/session
  ;; management for the real terminal app.lisp drives.
  (:import-from #:cl-tty-kit
                #:key-event-type
                #:key-event-code
                #:key-event-kind
                #:make-input-decoder
                #:decode-input
                #:decode-input-chunk
                #:make-renderer
                #:renderer-screen
                #:renderer-render
                #:renderer-resize
                #:screen-write-string
                #:with-screen-batch
                #:make-style
                #:with-raw-mode
                #:with-terminal-session
                #:tick-loop-run-realtime)
  ;; cl-cli (L1): the declarative app spec and invocation accessors cli.lisp
  ;; builds the `cl-chip8` command from.
  (:import-from #:cl-cli
                #:make-app
                #:make-option
                #:make-positional
                #:run-app
                #:option-value
                #:positional-value
                #:current-process-argv)
  ;; cl-concurrent-kit (L1): a persistent bounded worker executor and atomic
  ;; counters for the pure terminal-row rendering stage. CHIP-8 instruction
  ;; execution remains on the owner thread because its Prolog rulebase is
  ;; intentionally stateful and sequential.
  (:import-from #:cl-concurrent-kit
              #:make-executor
              #:shutdown-executor
              #:submit
              #:make-channel
              #:make-semaphore
              #:send
              #:try-send
              #:recv
              #:close-channel
              #:wait-on-semaphore
              #:signal-semaphore
              #:executor-queue-depth
              #:executor-high-water-mark
              #:make-atomic-counter
              #:atomic-counter-value
              #:atomic-counter-incf
              #:make-lock
              #:with-lock-held)
  (:export
   ;; -- Conditions --
   #:chip8-error
   #:chip8-rom-too-large
   #:chip8-rom-too-large-size
   #:chip8-rom-too-large-available
   #:chip8-invalid-opcode
   #:chip8-invalid-opcode-opcode
   #:chip8-stack-overflow
   #:chip8-stack-overflow-depth
   #:chip8-stack-underflow
   #:chip8-memory-access-out-of-bounds
   #:chip8-memory-access-out-of-bounds-address
   #:chip8-memory-access-out-of-bounds-span
   #:chip8-rom-not-regular-file
   #:chip8-rom-not-regular-file-path

   ;; -- Memory: the 4096-byte address space --
   #:+memory-size+
   #:+rom-load-address+
   #:*memory*
   #:memory-reset!
   #:load-bytes-into-memory
   ;; Prolog-callable goal functors (see memory.lisp). Exported, not just
   ;; documented, because DEFINE-FOREIGN-PREDICATE dispatches on the exact
   ;; symbol object used at both definition and call time (EQL on the
   ;; predicate name) -- a caller in another package needs the real,
   ;; interned CL-CHIP8:MEMORY-READ/CL-CHIP8:MEMORY-WRITE, not a same-named
   ;; symbol of its own that would silently miss every dispatch.
   #:memory-read
   #:memory-write
   #:check-memory-access

   ;; -- Display: the 64x32 monochrome framebuffer --
   #:+display-width+
   #:+display-height+
   #:*display*
   #:display-reset!
   #:display-mark-all-dirty!
   #:display-pixel-value
   #:display-xor-pixel!
   ;; Prolog-callable goal functors (see display.lisp); exported for the same
   ;; EQL-dispatch reason as MEMORY-READ/MEMORY-WRITE above.
   #:display-clear
   #:display-pixel
   #:display-xor-pixel

   ;; -- Fontset: the 16 built-in hex-digit glyphs --
   #:+fontset-address+
   #:+chip8-fontset+
   #:load-fontset-into-memory!

   ;; -- CPU state: the Prolog rulebase and its fact shapes --
   #:*rulebase*
   #:+register-count+
   #:+initial-pc+
   #:+call-stack-limit+
   #:reset-cpu-state!
   #:key-down-p
   #:pressed-keys
   ;; Fact functors asserted/retracted against *RULEBASE* (see state.lisp):
   ;;   (v Index Value)         -- 16 general registers V0-VF
   ;;   (i-register Value)      -- the 16-bit I register
   ;;   (pc Value)              -- program counter
   ;;   (call-stack List)       -- return-address stack, most recent first
   ;;   (delay-timer Value)     -- delay timer, 0-255
   ;;   (sound-timer Value)     -- sound timer, 0-255
   ;;   (key-down Hex)          -- one fact per currently pressed hex key
   #:v
   #:i-register
   #:pc
   #:call-stack
   #:delay-timer
   #:sound-timer
   #:key-down

   ;; -- Opcodes: the instruction rulebase and its fetch/decode/execute glue --
   #:execute-instruction!
   #:fetch-opcode
   #:decode-opcode
   ;; Prolog-callable goal functors the STEP rulebase calls into (see
   ;; opcodes.lisp); exported for the same EQL-dispatch reason as
   ;; MEMORY-READ/DISPLAY-XOR-PIXEL above.
   #:raise-stack-overflow
   #:raise-stack-underflow
   #:draw-sprite
   #:random-byte-masked
   #:bitwise-op
   #:store-registers
   #:load-registers

   ;; -- Keypad: cl-tty-kit KEY-EVENTs to CHIP-8 hex keys --
   #:+keypad-mapping+
   #:+key-hold-ticks+
   #:key-event->chip8-key
   #:keypad-reset!
   #:keypad-apply-key-event!
   #:keypad-apply-key-events!
   #:keypad-step!

   ;; -- Timers: 60Hz delay/sound timer stepping --
   #:step-timers!

   ;; -- ROM loading --
   #:read-file-bytes
   #:load-rom-file!
   #:regular-file-p
   #:check-regular-rom-file

   ;; -- Rendering: half-block blit of *DISPLAY* into a cl-tty-kit SCREEN --
   #:+screen-width+
   #:+screen-height+
   #:+playfield-origin-x+
   #:+playfield-origin-y+
   #:half-block-character
   #:render-display-into-screen!
   #:sound-timer-active-p
   #:render-sound-indicator-into-screen!
   #:render-chip8!

   ;; -- Concurrent rendering: immutable row snapshots and serial screen commit --
   #:with-chip8-render-pipeline
   #:chip8-render-pipeline-p
   #:make-chip8-render-pipeline
   #:close-chip8-render-pipeline
   #:render-chip8-concurrently!
   #:chip8-render-pipeline-parallelism
   #:chip8-render-pipeline-parallel-threshold
   #:chip8-render-pipeline-shutdown-timeout
   #:chip8-render-pipeline-submitted-rows
   #:chip8-render-pipeline-completed-rows
   #:chip8-render-pipeline-serial-rows
   #:chip8-render-pipeline-queue-depth
   #:chip8-render-pipeline-high-water-mark

   ;; -- App: the realtime tick loop --
   #:+default-clock-hz+
   #:chip8-app
   #:make-chip8-app
   #:chip8-app-p
   #:chip8-app-renderer
   #:chip8-app-decoder
   #:chip8-app-render-pipeline
   #:chip8-app-clock-hz
   #:chip8-app-quitp
   #:chip8-app-error
   #:quit-key-event-p
   #:run

   ;; -- CLI: the `cl-chip8' command --
   #:*app*
   #:main
   #:image-entry-point))
