# Conditions

All runtime-specific conditions inherit from `chip8-error`.

| Condition | Meaning | Accessors |
|---|---|---|
| `chip8-rom-too-large` | The ROM does not fit after `0x200`. | `chip8-rom-too-large-size`, `chip8-rom-too-large-available` |
| `chip8-rom-short-read` | The ROM file ended before the length `file-length` reported had been read. | `chip8-rom-short-read-actual-size`, `chip8-rom-short-read-expected-size` |
| `chip8-invalid-opcode` | No implemented instruction matches the opcode. | `chip8-invalid-opcode-opcode` |
| `chip8-stack-overflow` | A call would exceed the stack limit. | `chip8-stack-overflow-depth` |
| `chip8-stack-underflow` | A return was attempted with an empty stack. | None |
| `chip8-memory-access-out-of-bounds` | A memory access exceeds the 4,096-byte array. | `chip8-memory-access-out-of-bounds-address`, `chip8-memory-access-out-of-bounds-span` |
| `chip8-rom-not-regular-file` | The supplied ROM path is not a regular file. | `chip8-rom-not-regular-file-path` |

The conditions are signaled by ROM loading, memory access, and instruction
execution functions. See the [API reference](api.md) for the function that
can signal each condition and the corresponding accessor signatures.
