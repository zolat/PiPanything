//! Wire format for the PiPanything control socket.
//!
//! Mirrored from `PiPanything/Sources/Server/ControlProtocol.swift` —
//! changes must touch both files in the same commit. snake_case on the
//! wire matches serde defaults; the Swift side opts in via
//! `convertToSnakeCase`/`convertFromSnakeCase`.

#![allow(dead_code)] // populated incrementally; full surface exists for handlers

use serde::{Deserialize, Serialize};

pub const PROTOCOL_VERSION: &str = "0.1";

// -- Envelope + response --------------------------------------------------

#[derive(Debug, Serialize, Deserialize)]
pub struct Request<T: Serialize> {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub id: Option<String>,
    pub cmd: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub args: Option<T>,
}

#[derive(Debug, Deserialize)]
pub struct Response {
    #[serde(default)]
    pub id: Option<String>,
    pub ok: bool,
    #[serde(default)]
    pub result: Option<serde_json::Value>,
    #[serde(default)]
    pub error: Option<String>,
}

// -- Shared types ---------------------------------------------------------

/// Window geometry in screen-coordinate points (bottom-left origin),
/// or normalized [0,1] crop sub-rect (also bottom-left origin).
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct FrameRect {
    pub x: f64,
    pub y: f64,
    pub w: f64,
    pub h: f64,
}

// -- ping -----------------------------------------------------------------

#[derive(Debug, Serialize, Deserialize)]
pub struct PingResult {
    pub version: String,
    pub pid: i32,
}

// -- list_windows ---------------------------------------------------------

#[derive(Debug, Default, Serialize, Deserialize)]
pub struct ListWindowsArgs {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub refresh: Option<bool>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct WindowInfo {
    pub window_id: u32,
    pub app_name: Option<String>,
    pub bundle_id: Option<String>,
    pub pid: Option<i32>,
    pub title: Option<String>,
    pub width: f64,
    pub height: f64,
}

// -- list_overlays --------------------------------------------------------

#[derive(Debug, Serialize, Deserialize)]
pub struct OverlayTabInfo {
    pub tab_id: String,
    pub label: String,
    pub is_capturing: bool,
    pub captured_window_id: Option<u32>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct OverlayInfo {
    pub overlay_id: String,
    pub label: String,
    pub is_capturing: bool,
    pub captured_window_id: Option<u32>,
    pub frame: FrameRect,
    pub opacity: f64,
    pub click_through: bool,
    pub auto_hide: bool,
    pub manually_hidden: bool,
    pub tabs: Vec<OverlayTabInfo>,
}

// -- show -----------------------------------------------------------------

#[derive(Debug, Default, Serialize, Deserialize)]
pub struct ShowArgs {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub window_id: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub query: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub overlay_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub new_overlay: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub new_tab: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub crop: Option<FrameRect>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ShowResult {
    pub overlay_id: String,
    pub tab_id: String,
}

// -- hide -----------------------------------------------------------------

#[derive(Debug, Serialize, Deserialize)]
pub struct HideArgs {
    pub overlay_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub mode: Option<String>, // "hide" | "stop" | "remove"
}

// -- geom -----------------------------------------------------------------

#[derive(Debug, Serialize, Deserialize)]
pub struct GeomArgs {
    pub overlay_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub x: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub y: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub w: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub h: Option<f64>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct GeomResult {
    pub frame: FrameRect,
}

// -- crop -----------------------------------------------------------------

#[derive(Debug, Serialize, Deserialize)]
pub struct CropArgs {
    pub overlay_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tab_id: Option<String>,
    /// `None` clears the crop.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub rect: Option<FrameRect>,
}

// -- opacity / click_through / auto_hide ----------------------------------

#[derive(Debug, Serialize, Deserialize)]
pub struct OpacityArgs {
    pub overlay_id: String,
    pub alpha: f64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ClickThroughArgs {
    pub overlay_id: String,
    pub enabled: bool,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct AutoHideArgs {
    pub overlay_id: String,
    pub enabled: bool,
}
