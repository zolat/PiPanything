# pipanythingctl

Command-line interface and MCP control surface for
[PiPanything](https://github.com/zolat/PiPanything) — a macOS
picture-in-picture overlay that floats over other apps' fullscreen
Spaces.

`pipanythingctl` talks to a running PiPanything app over a Unix domain
socket and lets you script the overlay from a shell or expose it as an
MCP server to agents like Claude Code.

## Quick start

```sh
pipanythingctl list                  # list capturable windows
pipanythingctl show "Finder"         # display Finder as a PiP overlay
pipanythingctl overlays              # list active overlays
pipanythingctl geom <id> --x 100 --y 100 --w 640 --h 360
pipanythingctl hide <id>             # close an overlay
```

If PiPanything isn't running, `pipanythingctl` auto-launches it via
`open -ga PiPanything` and waits up to 5s for the control socket to
appear. Pass `--no-launch` to disable.

## MCP server (Phase 2)

```sh
pipanythingctl mcp
```

Speaks the Model Context Protocol over stdio. Register in Claude Code:

```json
{
  "mcpServers": {
    "pipanything": {
      "command": "/Applications/PiPanything.app/Contents/Resources/pipanythingctl",
      "args": ["mcp"]
    }
  }
}
```

## Installation

This binary ships inside the PiPanything app bundle at
`Contents/Resources/pipanythingctl`. To make it shell-accessible:

```sh
ln -s "/Applications/PiPanything.app/Contents/Resources/pipanythingctl" \
      /usr/local/bin/pipanythingctl
```

A standalone homebrew tap is planned; until then, use the symlink or
invoke the bundle path directly.

## Wire protocol

See `docs/agent-control.md` in the PiPanything repo for the full NDJSON
command catalog. The Rust types in `src/protocol.rs` mirror Swift
`PiPanything/Sources/Server/ControlProtocol.swift` exactly — the two
files change in the same commit when the wire format evolves.

## Build

```sh
rustup target add aarch64-apple-darwin x86_64-apple-darwin   # one time
cargo build --release
```

The PiPanything Xcode build invokes `tools/build-cli.sh` to compile
this crate and lipo it into a universal binary inside the .app bundle.

## License

GPL-3.0-only. See [LICENSE](LICENSE).
