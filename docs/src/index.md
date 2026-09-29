# cl-chip8

An SBCL-only [CHIP-8](https://en.wikipedia.org/wiki/CHIP-8) interpreter for
the terminal. Version 0.2.0 exposes a typed machine-state API, a terminal
application, headless execution helpers, configurable compatibility profiles,
TOML configuration, logging, and metrics.

From a checkout with Nix installed:

```sh
nix run .#cl-chip8 -- path/to/rom.ch8
```

The flake provides `x86_64-linux` and `aarch64-darwin` outputs. On other
systems, load the system through SBCL and ASDF directly. See
[Getting Started](getting-started.md) for both routes.

Start with [Getting Started](getting-started.md), then read [Core Concepts](guide/core-concepts.md),
the [Terminal guide](guide/terminal.md), or the [API reference](reference/api.md).
Compatibility limits and the development workflow are documented separately.
