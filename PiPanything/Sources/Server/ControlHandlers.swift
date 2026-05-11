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
}
