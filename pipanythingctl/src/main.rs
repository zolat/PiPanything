// pipanythingctl — command-line + MCP control surface for PiPanything.
// Phase 1 bootstrap: prints version and exits. Subsequent commits add
// the socket client, subcommand surface, and (Phase 2) MCP server.

mod protocol;

fn main() {
    println!(
        "pipanythingctl {} (protocol v{})",
        env!("CARGO_PKG_VERSION"),
        protocol::PROTOCOL_VERSION
    );
}
