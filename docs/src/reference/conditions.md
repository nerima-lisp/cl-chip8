# Conditions

All runtime-specific conditions inherit from `chip8-error`.

| Condition | Meaning | Accessors |
|---|---|---|
| `chip8-rom-too-large` | A ROM does not fit in the selected machine's memory. | `chip8-rom-too-large-size`, `chip8-rom-too-large-available` |
| `chip8-rom-short-read` | A ROM file ended before the reported length was read. | `chip8-rom-short-read-actual-size`, `chip8-rom-short-read-expected-size` |
| `chip8-invalid-opcode` | No implemented instruction matches the opcode. | `chip8-invalid-opcode-opcode` |
| `chip8-stack-overflow` | `CALL` would exceed the sixteen-entry call stack. | `chip8-stack-overflow-depth` |
| `chip8-stack-underflow` | `RET` was attempted with an empty stack. | None |
| `chip8-memory-access-out-of-bounds` | An access exceeds the selected machine's 4 KiB or 64 KiB memory. | `chip8-memory-access-out-of-bounds-address`, `chip8-memory-access-out-of-bounds-span` |
| `chip8-rom-not-regular-file` | The ROM path exists but does not name a regular file. | `chip8-rom-not-regular-file-path` |
| `chip8-cps-error` | A continuation was resumed at an invalid phase. | `chip8-cps-error-phase`, `chip8-cps-error-cause` |
| `chip8-config-error` | TOML is invalid or a configuration value is unknown or invalid. | `chip8-config-error-source-name`, `chip8-config-error-line`, `chip8-config-error-column`, `chip8-config-error-path`, `chip8-config-error-key`, `chip8-config-error-reason` |
| `chip8-unsupported-platform` | A matched ROM lists only upstream platforms that cl-chip8 does not implement. | `chip8-unsupported-platform-name` |

`chip8-unsupported-platform` is signaled before the terminal session starts.
An explicit CLI `--platform` or `--quirks` selects how to run that ROM and
bypasses the condition; configuration-file values do not. See the
[Compatibility reference](compatibility.md) for the database platform map.

CLI argument errors use exit status `64`. ROM, runtime, unsupported-platform,
and TOML configuration errors use exit status `1`. `--help` and `--version`
exit with status `0`.

See the [API reference](api.md) for operation details.
