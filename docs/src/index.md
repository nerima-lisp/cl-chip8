# cl-chip8

An SBCL-only [CHIP-8](https://en.wikipedia.org/wiki/CHIP-8) interpreter for
the terminal. The CPU state is represented by [cl-prolog](https://github.com/nerima-lisp/cl-prolog)
facts, while memory and the display remain direct Lisp arrays. The runtime
implements the original CHIP-8 instruction set with a fixed modern behavior
profile.

From a checkout with Nix installed:

```sh
nix run .#cl-chip8 -- path/to/rom.ch8
```

Start with the [Getting Started](getting-started.md) guide, then read
[Core Concepts](guide/core-concepts.md), the [Terminal guide](guide/terminal.md),
or the [API reference](reference/api.md). Compatibility limits and the
development workflow are documented separately.
