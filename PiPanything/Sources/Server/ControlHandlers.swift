import Darwin
import Foundation
import ScreenCaptureKit

// Command dispatch for the control socket. Switches on the command
// name, decodes args into the typed payload, calls into the app
// (via the weak AppDelegate), and wraps the result in a
// ControlResponse. Errors flow back through ControlError → message.

@MainActor
enum ControlHandlers {
    static func dispatch(_ req: ControlRequest, delegate: AppDelegate?) async -> ControlResponse {
        do {
            switch req.cmd {
            case "ping":
                return try handlePing(req: req)
            case "list_windows":
                return try await handleListWindows(req: req)
            case "list_overlays":
                return try handleListOverlays(req: req, delegate: delegate)
            case "show":
                return try await handleShow(req: req, delegate: delegate)
            default:
                throw ControlError.unknownCommand(req.cmd)
            }
        } catch let error as ControlError {
            return ControlResponse.failure(id: req.id, error: error.message)
        } catch {
            return ControlResponse.failure(id: req.id, error: error.localizedDescription)
        }
    }

    // MARK: - ping

    private static func handlePing(req: ControlRequest) throws -> ControlResponse {
        let result = PingResult(
            version: ControlProtocol.version,
            pid: getpid()
        )
        return ControlResponse.success(id: req.id, result: result)
    }

    // MARK: - list_windows

    private static func handleListWindows(req: ControlRequest) async throws -> ControlResponse {
        _ = try req.decodeArgs(ListWindowsArgs.self) // `refresh` is implicit — we always re-query
        let sources = await SourceList.refresh()
        if sources.permissionDenied {
            throw ControlError.other("Screen Recording permission denied — grant in System Settings → Privacy & Security")
        }
        let infos = sources.windows.map(Self.windowInfo(from:))
        return ControlResponse.success(id: req.id, result: infos)
    }

    private static func windowInfo(from window: SCWindow) -> WindowInfo {
        let app = window.owningApplication
        return WindowInfo(
            windowId: window.windowID,
            appName: app?.applicationName,
            bundleId: app?.bundleIdentifier,
            pid: app?.processID,
            title: window.title,
            width: Double(window.frame.width),
            height: Double(window.frame.height)
        )
    }

    // MARK: - list_overlays

    private static func handleListOverlays(req: ControlRequest, delegate: AppDelegate?) throws -> ControlResponse {
        guard let delegate else { throw ControlError.other("app delegate unavailable") }
        let infos = delegate.coordinator.sessions.map { session -> OverlayInfo in
            let f = session.window.frame
            return OverlayInfo(
                overlayId: session.id.value.uuidString,
                label: session.sessionLabel,
                isCapturing: session.isCapturing,
                capturedWindowId: session.capturedWindowID,
                frame: FrameRect(x: Double(f.origin.x), y: Double(f.origin.y),
                                 w: Double(f.size.width), h: Double(f.size.height)),
                opacity: Double(session.opacity),
                clickThrough: session.clickThroughLatched,
                autoHide: session.autoHide,
                manuallyHidden: session.activeTab?.visibility.manuallyHidden ?? false,
                tabs: session.tabs.map { tab in
                    OverlayTabInfo(
                        tabId: tab.id.value.uuidString,
                        label: tab.sessionLabel,
                        isCapturing: tab.isCapturing,
                        capturedWindowId: tab.capturedWindowID
                    )
                }
            )
        }
        return ControlResponse.success(id: req.id, result: infos)
    }

    // MARK: - show

    private static func handleShow(req: ControlRequest, delegate: AppDelegate?) async throws -> ControlResponse {
        guard let delegate else { throw ControlError.other("app delegate unavailable") }
        let args = try req.decodeArgs(ShowArgs.self)

        // Resolve source window first so we don't burn an overlay slot on a
        // bad query.
        let scWindow = try await resolveWindow(args: args)

        // Resolve target session + tab per routing rules.
        let session: OverlaySession
        let tabID: OverlayTabID?

        if let overlayIdString = args.overlayId {
            guard let uuid = UUID(uuidString: overlayIdString) else {
                throw ControlError.parse("invalid overlay_id: \(overlayIdString)")
            }
            guard let target = delegate.coordinator.session(id: OverlayID(uuid)) else {
                throw ControlError.overlayNotFound(overlayIdString)
            }
            session = target
            if args.newTab == true {
                tabID = session.addTab(window: scWindow, cropImmediately: false)
            } else {
                tabID = session.setActiveSource(window: scWindow, cropImmediately: false)
            }
        } else if args.newOverlay == true {
            if delegate.coordinator.isAtSoftCap { throw ControlError.softCapReached }
            session = delegate.addConfiguredSession()
            session.start(window: scWindow, cropImmediately: false)
            tabID = session.activeTab?.id
        } else if let primary = delegate.coordinator.sessions.first, !primary.isCapturing, !primary.isMinimized {
            // Empty primary — fill it. Matches the picker's "fill idle" routing.
            primary.start(window: scWindow, cropImmediately: false)
            session = primary
            tabID = primary.activeTab?.id
        } else {
            // Primary busy or minimized → spawn a new overlay.
            if delegate.coordinator.isAtSoftCap { throw ControlError.softCapReached }
            session = delegate.addConfiguredSession()
            session.start(window: scWindow, cropImmediately: false)
            tabID = session.activeTab?.id
        }

        guard let tab = tabID, let resolvedTab = session.tabs.first(where: { $0.id == tab }) else {
            throw ControlError.other("show succeeded but the resulting tab could not be located")
        }

        // NOTE: args.crop is accepted on the wire but not honored in Phase 1.
        // applyCropProgrammatic no-ops until sourceAspect lands on first frame,
        // and we don't have a pending-crop hook on OverlayTab yet. Workaround:
        // agents call `show` then `crop` once `list_overlays` reports
        // is_capturing=true (or just retry the crop until it sticks).

        let result = ShowResult(
            overlayId: session.id.value.uuidString,
            tabId: resolvedTab.id.value.uuidString
        )
        return ControlResponse.success(id: req.id, result: result)
    }

    private static func resolveWindow(args: ShowArgs) async throws -> SCWindow {
        let sources = await SourceList.refresh()
        if sources.permissionDenied {
            throw ControlError.other("Screen Recording permission denied — grant in System Settings → Privacy & Security")
        }
        if let wid = args.windowId {
            guard let w = sources.windows.first(where: { $0.windowID == wid }) else {
                throw ControlError.windowNotFound("window_id=\(wid)")
            }
            return w
        }
        if let q = args.query, !q.isEmpty {
            let needle = q.lowercased()
            let match = sources.windows.first { w in
                let label = "\(w.owningApplication?.applicationName ?? "") — \(w.title ?? "")"
                return label.lowercased().contains(needle)
            }
            guard let m = match else { throw ControlError.windowNotFound(q) }
            return m
        }
        throw ControlError.missingArg("'show' requires window_id or query")
    }
}
