# Conditions

All runtime-specific conditions inherit from `chip8-error`.

| Condition | Meaning | Accessors |
|---|---|---|
| `chip8-rom-too-large` | A ROM or memory span does not fit. | `chip8-rom-too-large-size`, `chip8-rom-too-large-available` |
| `chip8-rom-short-read` | A ROM file ended before the reported length was read. | `chip8-rom-short-read-actual-size`, `chip8-rom-short-read-expected-size` |
| `chip8-invalid-opcode` | No implemented instruction matches the opcode. | `chip8-invalid-opcode-opcode` |
| `chip8-stack-overflow` | `CALL` would exceed the call stack. | `chip8-stack-overflow-depth` |
| `chip8-stack-underflow` | `RET` was attempted with an empty stack. | None |
| `chip8-memory-access-out-of-bounds` | An access exceeds the 4,096-byte memory. | `chip8-memory-access-out-of-bounds-address`, `chip8-memory-access-out-of-bounds-span` |
| `chip8-rom-not-regular-file` | The ROM path is not a regular file. | `chip8-rom-not-regular-file-path` |
| `chip8-cps-error` | A continuation was resumed at an invalid phase. | `chip8-cps-error-phase`, `chip8-cps-error-cause` |

CLI failures use exit status `64` for argument errors. ROM, runtime, and TOML
configuration errors use exit status `1`. `--help` and `--version` exit with
status `0`.

See the [API reference](api.md) for operation details.
