//! Auto-launch PiPanything if the control socket is unreachable.
//!
//! Probes by attempting an actual `connect()` — that catches the
//! "path exists but listener crashed" case as well as the
//! "path doesn't exist" case. Targets the .app bundle this CLI ships
//! inside (resolved via `current_exe`) rather than the LaunchServices
//! default for "PiPanything", so dev builds in DerivedData open
//! themselves rather than whichever bundle macOS registered last.
//! Then polls the socket every 100ms for up to 5s.

use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{Duration, Instant};

use anyhow::{anyhow, Context, Result};

const POLL_INTERVAL: Duration = Duration::from_millis(100);
const POLL_TIMEOUT: Duration = Duration::from_secs(5);

pub fn ensure_app_running(socket_path: &Path) -> Result<()> {
    if can_connect(socket_path) {
        return Ok(());
    }

    let target = resolve_bundle_target();

    // `--env=PIP_CONTROL_SERVER=1` is a Phase-1 crutch: the GUI app
    // currently gates the control server behind that env var so the
    // surface is opt-in through the first ship. Drop the flag once
    // the gate flips default-on.
    let status = Command::new("/usr/bin/open")
        .arg("-ga")
        .arg(&target)
        .arg("--env=PIP_CONTROL_SERVER=1")
        .status()
        .context("invoke `open -ga <PiPanything>`")?;
    if !status.success() {
        return Err(anyhow!(
            "PiPanything is not running and could not be launched (open exited {status})"
        ));
    }

    let deadline = Instant::now() + POLL_TIMEOUT;
    while Instant::now() < deadline {
        if can_connect(socket_path) {
            return Ok(());
        }
        std::thread::sleep(POLL_INTERVAL);
    }

    Err(anyhow!(
        "PiPanything launched but control socket {} did not become reachable within {}s.",
        socket_path.display(),
        POLL_TIMEOUT.as_secs()
    ))
}

/// If the CLI is running from inside a `*.app/Contents/Resources/`,
/// return the absolute bundle path so we open *that* bundle. Otherwise
/// fall back to the bare app name and let LaunchServices resolve it.
fn resolve_bundle_target() -> PathBuf {
    if let Ok(exe) = std::env::current_exe().and_then(|p| p.canonicalize()) {
        if let Some(bundle) = bundle_for_exe(&exe) {
            return bundle;
        }
    }
    PathBuf::from("PiPanything")
}

fn bundle_for_exe(exe: &Path) -> Option<PathBuf> {
    // exe = .../<bundle>.app/Contents/Resources/pipanythingctl
    let resources = exe.parent()?;
    let contents = resources.parent()?;
    let bundle = contents.parent()?;
    if bundle.extension().and_then(|e| e.to_str()) == Some("app") {
        Some(bundle.to_path_buf())
    } else {
        None
    }
}

fn can_connect(path: &Path) -> bool {
    UnixStream::connect(path).is_ok()
}
