// pipanythingctl — command-line + MCP control surface for PiPanything.
// Phase 1 bootstrap: prints version and exits. Subsequent commits add
// the socket client, subcommand surface, and (Phase 2) MCP server.

fn main() {
    println!("pipanythingctl {}", env!("CARGO_PKG_VERSION"));
}
