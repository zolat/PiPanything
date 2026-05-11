//! Unix-socket client for the PiPanything control surface.
//!
//! One round-trip per call: write a newline-delimited JSON request,
//! read one newline-delimited JSON response, decode. The socket is
//! held open for the lifetime of `Client`, so multiple calls reuse
//! the same connection.

use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};

use anyhow::{anyhow, Context, Result};
use serde::Serialize;

use crate::protocol;

pub struct Client {
    write_half: UnixStream,
    read_half: BufReader<UnixStream>,
    next_req_id: u64,
}

impl Client {
    pub fn connect(path: &Path) -> Result<Self> {
        let write_half = UnixStream::connect(path)
            .with_context(|| format!("connecting to {}", path.display()))?;
        let read_clone = write_half
            .try_clone()
            .context("clone unix-socket fd")?;
        Ok(Self {
            write_half,
            read_half: BufReader::new(read_clone),
            next_req_id: 1,
        })
    }

    /// Send one command and return the parsed response.
    pub fn call<A: Serialize>(&mut self, cmd: &str, args: &A) -> Result<protocol::Response> {
        let id = format!("req-{}", self.next_req_id);
        self.next_req_id += 1;

        let envelope = serde_json::json!({
            "id": id,
            "cmd": cmd,
            "args": serde_json::to_value(args)?,
        });
        let mut line = serde_json::to_vec(&envelope)?;
        line.push(b'\n');
        self.write_half.write_all(&line)?;
        self.write_half.flush()?;

        let mut response = String::new();
        let n = self.read_half.read_line(&mut response)?;
        if n == 0 {
            return Err(anyhow!("server closed connection before responding"));
        }
        serde_json::from_str::<protocol::Response>(response.trim_end())
            .with_context(|| format!("parse response: {}", response.trim_end()))
    }
}

/// `~/Library/Application Support/PiPanything/control.sock`
pub fn default_socket_path() -> PathBuf {
    let home = std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/tmp"));
    home.join("Library/Application Support/PiPanything/control.sock")
}
