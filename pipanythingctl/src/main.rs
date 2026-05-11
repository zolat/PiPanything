// pipanythingctl — command-line + MCP control surface for PiPanything.
//
// Phase 1: shell-ergonomic CLI that talks to the PiPanything GUI over
// a Unix-domain control socket. Phase 2 (not in this commit) adds an
// `mcp` subcommand that bridges the same socket to stdio MCP.

mod autolaunch;
mod client;
mod protocol;

use std::path::PathBuf;
use std::process::ExitCode;

use anyhow::{anyhow, Context, Result};
use clap::{Parser, Subcommand};

use crate::client::Client;

#[derive(Parser, Debug)]
#[command(
    name = "pipanythingctl",
    version,
    about = "Control PiPanything from the shell or expose it as an MCP server."
)]
struct Cli {
    /// Override the control socket path. Defaults to
    /// `~/Library/Application Support/PiPanything/control.sock`.
    #[arg(long, global = true)]
    socket: Option<PathBuf>,

    /// Don't try to auto-launch PiPanything if the socket is unreachable.
    #[arg(long, global = true)]
    no_launch: bool,

    #[command(subcommand)]
    cmd: Command,
}

#[derive(Subcommand, Debug)]
enum Command {
    /// Round-trip a ping to the running app and print {version, pid}.
    Ping,

    /// List capturable windows (same filter as the right-click picker).
    List,

    /// List active overlays.
    Overlays,
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("pipanythingctl: {e:#}");
            ExitCode::from(1)
        }
    }
}

fn run() -> Result<()> {
    let cli = Cli::parse();
    let socket = cli
        .socket
        .clone()
        .unwrap_or_else(client::default_socket_path);

    if !cli.no_launch {
        autolaunch::ensure_app_running(&socket)?;
    }

    let mut client = Client::connect(&socket).with_context(|| {
        format!("connecting to PiPanything at {}", socket.display())
    })?;

    match cli.cmd {
        Command::Ping => {
            let resp = client.call("ping", &serde_json::json!({}))?;
            print_result(resp)?;
        }
        Command::List => {
            let resp = client.call("list_windows", &protocol::ListWindowsArgs::default())?;
            print_result(resp)?;
        }
        Command::Overlays => {
            let resp = client.call("list_overlays", &serde_json::json!({}))?;
            print_result(resp)?;
        }
    }
    Ok(())
}

fn print_result(resp: protocol::Response) -> Result<()> {
    if !resp.ok {
        return Err(anyhow!(
            "{}",
            resp.error
                .unwrap_or_else(|| "(server reported failure without message)".into())
        ));
    }
    let value = resp.result.unwrap_or(serde_json::Value::Null);
    println!("{}", serde_json::to_string_pretty(&value)?);
    Ok(())
}
