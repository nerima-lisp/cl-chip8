# cl-chip8

An SBCL-only [CHIP-8](https://en.wikipedia.org/wiki/CHIP-8) interpreter for
the terminal. The CPU state is represented by [cl-prolog-kit](https://github.com/nerima-lisp/cl-prolog-kit)
facts, while memory and the display remain direct Lisp arrays. The runtime
implements the original CHIP-8 instruction set with a fixed modern behavior
profile.

From a checkout with Nix installed, on `x86_64-linux`:

```sh
nix run .#cl-chip8 -- path/to/rom.ch8
```

The flake declares outputs for `x86_64-linux` only, so every `nix` command
fails on any other system. On those hosts, load the system through SBCL and
ASDF directly -- see [Getting Started](getting-started.md) for both routes.

Start with the [Getting Started](getting-started.md) guide, then read
[Core Concepts](guide/core-concepts.md), the [Terminal guide](guide/terminal.md),
or the [API reference](reference/api.md). Compatibility limits and the
development workflow are documented separately.
