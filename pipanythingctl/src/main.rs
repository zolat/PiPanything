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
use clap::{Parser, Subcommand, ValueEnum};

#[derive(Clone, Debug, ValueEnum)]
enum OnOff {
    On,
    Off,
}

impl OnOff {
    fn enabled(&self) -> bool {
        matches!(self, OnOff::On)
    }
}

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

    /// Set overlay opacity (alpha 0..1).
    Opacity {
        overlay_id: String,
        /// 0 (fully transparent) to 1 (fully opaque).
        alpha: f64,
    },

    /// Toggle click-through on an overlay. When on, the overlay dims and
    /// ignores mouse events so the user can work in the app behind it.
    ClickThrough {
        overlay_id: String,
        #[arg(value_enum)]
        state: OnOff,
    },

    /// Toggle auto-hide on an overlay. When on, the overlay hides whenever
    /// the captured app is frontmost.
    AutoHide {
        overlay_id: String,
        #[arg(value_enum)]
        state: OnOff,
    },

    /// Move and/or resize an overlay. Missing fields preserve current value.
    /// Frames are in screen-coordinate points (bottom-left origin).
    Geom {
        overlay_id: String,
        #[arg(long, allow_negative_numbers = true)]
        x: Option<f64>,
        #[arg(long, allow_negative_numbers = true)]
        y: Option<f64>,
        #[arg(long)]
        w: Option<f64>,
        #[arg(long)]
        h: Option<f64>,
    },

    /// Apply or clear a crop region on the overlay's active tab (or a
    /// specific tab via --tab). Rect coords are normalized [0,1]
    /// bottom-left. Note: crop currently no-ops until first frame
    /// settles the source aspect — retry until it sticks if needed.
    Crop {
        overlay_id: String,
        /// "x,y,w,h" in normalized [0,1] coords. Conflicts with --clear.
        #[arg(long, conflicts_with = "clear")]
        rect: Option<String>,
        /// Clear the existing crop.
        #[arg(long, conflicts_with = "rect")]
        clear: bool,
        /// Target a specific tab by id. Defaults to the active tab.
        #[arg(long)]
        tab: Option<String>,
    },

    /// Close an overlay, idle it, or toggle the manual-hide latch.
    ///
    /// Default mode for the primary overlay is "stop" (idle, keep the
    /// entry-point alive); for secondary overlays it is "remove" (tear
    /// down). Use --mode to override.
    Hide {
        /// Overlay id (from `pipanythingctl overlays`). Omit with --all.
        overlay_id: Option<String>,

        /// Close every overlay (stops the primary, removes the rest).
        #[arg(long, conflicts_with = "overlay_id")]
        all: bool,

        /// "hide" (manual-hide latch), "stop" (idle), or "remove" (tear down).
        #[arg(long, value_parser = ["hide", "stop", "remove"], conflicts_with = "all")]
        mode: Option<String>,
    },

    /// Display a window as a picture-in-picture overlay.
    ///
    /// Routing: with --overlay, replaces that overlay's active tab
    /// (or adds a tab with --new-tab). Without --overlay, fills the
    /// idle entry-point overlay if there is one, else spawns a new
    /// overlay (or always with --new-overlay).
    Show {
        /// Substring match against "App — Title" (case-insensitive).
        #[arg(conflicts_with = "window_id")]
        query: Option<String>,

        /// Exact window ID from `pipanythingctl list`.
        #[arg(long, conflicts_with = "query")]
        window_id: Option<u32>,

        /// Target an existing overlay by id.
        #[arg(long, value_name = "OVERLAY_ID")]
        overlay: Option<String>,

        /// Always spawn a new overlay (ignored if --overlay is set).
        #[arg(long, conflicts_with = "overlay")]
        new_overlay: bool,

        /// Add as a new tab inside the --overlay target.
        #[arg(long, requires = "overlay")]
        new_tab: bool,
    },
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
        Command::Opacity { overlay_id, alpha } => {
            let args = protocol::OpacityArgs { overlay_id, alpha };
            let resp = client.call("opacity", &args)?;
            print_result(resp)?;
        }
        Command::ClickThrough { overlay_id, state } => {
            let args = protocol::ClickThroughArgs {
                overlay_id,
                enabled: state.enabled(),
            };
            let resp = client.call("click_through", &args)?;
            print_result(resp)?;
        }
        Command::AutoHide { overlay_id, state } => {
            let args = protocol::AutoHideArgs {
                overlay_id,
                enabled: state.enabled(),
            };
            let resp = client.call("auto_hide", &args)?;
            print_result(resp)?;
        }
        Command::Geom {
            overlay_id,
            x,
            y,
            w,
            h,
        } => {
            let args = protocol::GeomArgs {
                overlay_id,
                x,
                y,
                w,
                h,
            };
            let resp = client.call("geom", &args)?;
            print_result(resp)?;
        }
        Command::Crop {
            overlay_id,
            rect,
            clear,
            tab,
        } => {
            if rect.is_none() && !clear {
                return Err(anyhow!("crop requires --rect 'x,y,w,h' or --clear"));
            }
            let parsed_rect = match rect {
                Some(s) => Some(parse_rect(&s)?),
                None => None,
            };
            let args = protocol::CropArgs {
                overlay_id,
                tab_id: tab,
                rect: parsed_rect,
            };
            let resp = client.call("crop", &args)?;
            print_result(resp)?;
        }
        Command::Hide {
            overlay_id,
            all,
            mode,
        } => {
            if all {
                let resp = client.call("hide_all", &serde_json::json!({}))?;
                print_result(resp)?;
            } else {
                let overlay_id = overlay_id.ok_or_else(|| {
                    anyhow!("hide requires an <overlay_id> or --all")
                })?;
                let args = protocol::HideArgs { overlay_id, mode };
                let resp = client.call("hide", &args)?;
                print_result(resp)?;
            }
        }
        Command::Show {
            query,
            window_id,
            overlay,
            new_overlay,
            new_tab,
        } => {
            if query.is_none() && window_id.is_none() {
                return Err(anyhow!(
                    "show requires a query or --window-id (run `pipanythingctl list`)"
                ));
            }
            let args = protocol::ShowArgs {
                window_id,
                query,
                overlay_id: overlay,
                new_overlay: new_overlay.then_some(true),
                new_tab: new_tab.then_some(true),
                crop: None,
            };
            let resp = client.call("show", &args)?;
            print_result(resp)?;
        }
    }
    Ok(())
}

fn parse_rect(s: &str) -> Result<protocol::FrameRect> {
    let parts: Vec<&str> = s.split(',').collect();
    if parts.len() != 4 {
        return Err(anyhow!("rect must be 'x,y,w,h' (got {} parts)", parts.len()));
    }
    let vals: Vec<f64> = parts
        .iter()
        .map(|p| p.trim().parse::<f64>().map_err(|e| anyhow!("{e}")))
        .collect::<Result<_>>()?;
    Ok(protocol::FrameRect {
        x: vals[0],
        y: vals[1],
        w: vals[2],
        h: vals[3],
    })
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
