;;;; Package definitions and public API.
(in-package #:cl-user)

(defpackage #:cl-chip8
  (:use #:cl)
  ;; Prolog rulebase and query primitives.
  (:import-from #:cl-prolog-kit
                #:make-rulebase
                #:query-prolog
                #:query-prolog-first
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
                #:extend-rulebase)
  ;; Terminal input and rendering.
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
  ;; CLI primitives.
  (:import-from #:cl-cli
                #:make-app
                #:make-option
                #:make-positional
                #:run-app
                #:option-value
                #:positional-value
                #:current-process-argv)
  ;; Concurrent rendering.
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
  ;; Timeout types.
  (:import-from #:cl-date-kit
                #:duration
                #:duration-of-seconds
                #:duration-to-seconds)
  ;; Process termination.
  (:import-from #:host-kit
                #:quit)
  ;; Public API.
  (:export
   ;; -- Conditions --
   #:chip8-error
   #:chip8-rom-too-large
   #:chip8-rom-too-large-size
   #:chip8-rom-too-large-available
   #:chip8-rom-short-read
   #:chip8-rom-short-read-actual-size
   #:chip8-rom-short-read-expected-size
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

   ;; -- Display: the 64x32 monochrome framebuffer --
   ;; Use the accessors so concurrent rendering sees dirty-row updates.
   #:+display-width+
   #:+display-height+
   #:display-reset!
   #:display-pixel-value
   #:display-xor-pixel!

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

   ;; -- Opcodes: the instruction rulebase's execute entry point --
   ;; FETCH-OPCODE/DECODE-OPCODE are sub-steps of EXECUTE-INSTRUCTION!, and
   ;; the STEP rulebase's goal functors are internal per the rule above.
   #:execute-instruction!

   ;; -- Keypad --
   #:keypad-reset!

   ;; -- Timers: 60Hz delay/sound timer stepping --
   #:step-timers!

   ;; -- ROM loading --
   #:load-rom-file!

   ;; -- Rendering --
   #:+screen-width+
   #:+screen-height+
   #:sound-timer-active-p
   #:render-chip8!

   ;; -- Concurrent rendering --
   #:chip8-render-pipeline
   #:chip8-render-pipeline-p
   #:with-chip8-render-pipeline
   #:make-chip8-render-pipeline
   #:close-chip8-render-pipeline
   #:render-chip8-concurrently!

   ;; -- App --
   #:chip8-app
   #:chip8-app-p
   #:chip8-app-quitp
   #:chip8-app-error
   #:run

   ;; -- CLI: the `cl-chip8' command --
   #:*app*
   #:main
   #:image-entry-point))
