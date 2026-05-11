import Foundation

// Wire format for the control socket. Mirrored in
// `pipanythingctl/src/protocol.rs` — changes must touch both files
// in the same commit. snake_case on the wire; camelCase in Swift via
// `keyEncodingStrategy/keyDecodingStrategy = .convert*SnakeCase`.

enum ControlProtocol {
    static let version = "0.1"

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
}

// MARK: - Envelope + response

struct ControlRequest {
    let id: String?
    let cmd: String
    let argsData: Data

    static func decode(line: Data) throws -> ControlRequest {
        guard let obj = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            throw ControlError.parse("expected JSON object")
        }
        let id = obj["id"] as? String
        guard let cmd = obj["cmd"] as? String else {
            throw ControlError.parse("missing 'cmd'")
        }
        let argsData: Data
        if let args = obj["args"] {
            argsData = try JSONSerialization.data(withJSONObject: args)
        } else {
            argsData = Data("{}".utf8)
        }
        return ControlRequest(id: id, cmd: cmd, argsData: argsData)
    }

    func decodeArgs<T: Decodable>(_ type: T.Type) throws -> T {
        try ControlProtocol.decoder.decode(type, from: argsData)
    }
}

struct ControlResponse: Encodable {
    let id: String?
    let ok: Bool
    let result: AnyEncodable?
    let error: String?

    static func success(id: String?, result: some Encodable) -> ControlResponse {
        ControlResponse(id: id, ok: true, result: AnyEncodable(result), error: nil)
    }

    static func failure(id: String?, error: String) -> ControlResponse {
        ControlResponse(id: id, ok: false, result: nil, error: error)
    }
}

struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    init(_ value: some Encodable) {
        _encode = value.encode
    }
    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}

enum ControlError: Error {
    case parse(String)
    case unknownCommand(String)
    case missingArg(String)
    case overlayNotFound(String)
    case tabNotFound(String)
    case windowNotFound(String)
    case softCapReached
    case unsupported(String)
    case other(String)

    var message: String {
        switch self {
        case let .parse(s): return "parse: \(s)"
        case let .unknownCommand(s): return "unknown command: '\(s)'"
        case let .missingArg(s): return "missing arg: \(s)"
        case let .overlayNotFound(s): return "no overlay with id '\(s)'"
        case let .tabNotFound(s): return "no tab with id '\(s)'"
        case let .windowNotFound(s): return "no window matched '\(s)'"
        case .softCapReached: return "overlay soft cap reached"
        case let .unsupported(s): return "unsupported: \(s)"
        case let .other(s): return s
        }
    }
}

// MARK: - Per-command args & results

// Frames and crop rects are normalized [0,1] bottom-left for crop,
// or screen-coords points bottom-left for window geometry.
struct FrameRect: Codable, Sendable {
    let x: Double
    let y: Double
    let w: Double
    let h: Double
}

// ping
struct PingResult: Encodable, Sendable {
    let version: String
    let pid: Int32
}

// list_windows
struct ListWindowsArgs: Decodable, Sendable {
    let refresh: Bool?
}

struct WindowInfo: Encodable, Sendable {
    let windowId: UInt32
    let appName: String?
    let bundleId: String?
    let pid: Int32?
    let title: String?
    let width: Double
    let height: Double
}

// list_overlays
struct OverlayTabInfo: Encodable, Sendable {
    let tabId: String
    let label: String
    let isCapturing: Bool
    let capturedWindowId: UInt32?
}

struct OverlayInfo: Encodable, Sendable {
    let overlayId: String
    let label: String
    let isCapturing: Bool
    let capturedWindowId: UInt32?
    let frame: FrameRect
    let opacity: Double
    let clickThrough: Bool
    let autoHide: Bool
    let manuallyHidden: Bool
    let tabs: [OverlayTabInfo]
}

// show
struct ShowArgs: Decodable, Sendable {
    let windowId: UInt32?
    let query: String?
    let overlayId: String?
    let newOverlay: Bool?
    let newTab: Bool?
    let crop: FrameRect?
}

struct ShowResult: Encodable, Sendable {
    let overlayId: String
    let tabId: String
}

// hide
struct HideArgs: Decodable, Sendable {
    let overlayId: String
    let mode: String?  // "hide" | "stop" | "remove" (nil = default)
}

// geom
struct GeomArgs: Decodable, Sendable {
    let overlayId: String
    let x: Double?
    let y: Double?
    let w: Double?
    let h: Double?
}

struct GeomResult: Encodable, Sendable {
    let frame: FrameRect
}

// crop
struct CropArgs: Decodable, Sendable {
    let overlayId: String
    let tabId: String?
    let rect: FrameRect?  // nil = clear
}

// opacity
struct OpacityArgs: Decodable, Sendable {
    let overlayId: String
    let alpha: Double
}

// click_through
struct ClickThroughArgs: Decodable, Sendable {
    let overlayId: String
    let enabled: Bool
}

// auto_hide
struct AutoHideArgs: Decodable, Sendable {
    let overlayId: String
    let enabled: Bool
}

// Empty payloads for handlers that take/return nothing.
struct EmptyArgs: Decodable, Sendable {}
struct EmptyResult: Encodable, Sendable {}
