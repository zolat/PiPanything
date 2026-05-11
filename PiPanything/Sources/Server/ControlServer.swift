import Darwin
import Foundation

// AF_UNIX SOCK_STREAM listener that speaks newline-delimited JSON to
// `pipanythingctl`. Accept loop runs on a private DispatchQueue;
// per-connection serve loops run as detached Tasks that hop to
// MainActor only to dispatch command handlers.
//
// Lifetime: started from AppDelegate.applicationDidFinishLaunching
// behind the PIP_CONTROL_SERVER=1 env gate, stopped from
// applicationWillTerminate. Stale socket files are unlinked on start
// and stop so a crash doesn't leave the path bound.

@MainActor
final class ControlServer {
    static let defaultSocketPath: String = {
        let dir = NSString(string: "~/Library/Application Support/PiPanything")
            .expandingTildeInPath
        return (dir as NSString).appendingPathComponent("control.sock")
    }()

    private let socketPath: String
    private let queue = DispatchQueue(
        label: "com.zolat.PiPanything.control",
        qos: .userInitiated
    )
    private var listenFD: Int32 = -1
    private var listenSource: DispatchSourceRead?

    weak var appDelegate: AppDelegate?

    init(socketPath: String = ControlServer.defaultSocketPath) {
        self.socketPath = socketPath
    }

    func start() throws {
        let parentDir = (socketPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: parentDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        unlink(socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ControlServerError.systemError("socket", errno) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        guard pathBytes.count <= maxLen else {
            Darwin.close(fd)
            throw ControlServerError.pathTooLong(socketPath)
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { tuplePtr in
            tuplePtr.withMemoryRebound(to: CChar.self, capacity: maxLen) { dst in
                pathBytes.withUnsafeBufferPointer { src in
                    _ = memcpy(dst, src.baseAddress, pathBytes.count)
                }
            }
        }

        let addrSize = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bindResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.bind(fd, sa, addrSize)
            }
        }
        guard bindResult == 0 else {
            let e = errno
            Darwin.close(fd)
            throw ControlServerError.systemError("bind", e)
        }
        chmod(socketPath, 0o600)

        guard Darwin.listen(fd, 8) == 0 else {
            let e = errno
            Darwin.close(fd)
            unlink(socketPath)
            throw ControlServerError.systemError("listen", e)
        }

        listenFD = fd

        let weakSelf = WeakRef(self)
        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        src.setEventHandler {
            ControlServer.acceptOne(listenFD: fd, server: weakSelf)
        }
        src.resume()
        listenSource = src

        NSLog("PiPanything: control server listening at \(socketPath)")
    }

    func stop() {
        listenSource?.cancel()
        listenSource = nil
        if listenFD >= 0 {
            Darwin.close(listenFD)
            listenFD = -1
        }
        unlink(socketPath)
        NSLog("PiPanything: control server stopped")
    }

    // MARK: - I/O (nonisolated; runs off the main actor)

    private nonisolated static func acceptOne(
        listenFD: Int32,
        server: WeakRef<ControlServer>
    ) {
        let connFD = Darwin.accept(listenFD, nil, nil)
        guard connFD >= 0 else { return }
        Task.detached {
            await ControlServer.serveConnection(fd: connFD, server: server)
        }
    }

    private nonisolated static func serveConnection(
        fd: Int32,
        server: WeakRef<ControlServer>
    ) async {
        defer { Darwin.close(fd) }
        var pending = Data()
        var readBuf = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = readBuf.withUnsafeMutableBufferPointer { buf -> Int in
                Darwin.read(fd, buf.baseAddress, buf.count)
            }
            if n <= 0 { return }
            pending.append(readBuf, count: n)
            while let nlIdx = pending.firstIndex(of: 0x0A) {
                let line = Data(pending[pending.startIndex..<nlIdx])
                pending.removeSubrange(pending.startIndex...nlIdx)
                if line.isEmpty { continue }
                await ControlServer.handleLine(line, fd: fd, server: server)
            }
        }
    }

    private nonisolated static func handleLine(
        _ line: Data,
        fd: Int32,
        server: WeakRef<ControlServer>
    ) async {
        let response: ControlResponse
        do {
            let req = try ControlRequest.decode(line: line)
            response = await MainActor.run {
                guard let srv = server.value else {
                    return ControlResponse.failure(id: req.id, error: "server stopped")
                }
                return ControlHandlers.dispatch(req, delegate: srv.appDelegate)
            }
        } catch let error as ControlError {
            response = ControlResponse.failure(id: nil, error: error.message)
        } catch {
            response = ControlResponse.failure(
                id: nil,
                error: "parse: \(error.localizedDescription)"
            )
        }
        do {
            var data = try ControlProtocol.encoder.encode(response)
            data.append(0x0A)
            data.withUnsafeBytes { raw in
                ControlServer.writeAll(raw.baseAddress!, raw.count, to: fd)
            }
        } catch {
            NSLog("PiPanything: failed to encode control response: \(error)")
        }
    }

    private nonisolated static func writeAll(
        _ buf: UnsafeRawPointer,
        _ count: Int,
        to fd: Int32
    ) {
        var written = 0
        while written < count {
            let n = Darwin.write(fd, buf.advanced(by: written), count - written)
            if n <= 0 { return }
            written += n
        }
    }
}

// Sendable weak-reference shim — the per-connection async tasks hold
// it across actor hops, and Swift's `weak self` doesn't survive that.
private final class WeakRef<T: AnyObject>: @unchecked Sendable {
    weak var value: T?
    init(_ value: T) { self.value = value }
}

enum ControlServerError: Error, CustomStringConvertible {
    case systemError(String, Int32)
    case pathTooLong(String)

    var description: String {
        switch self {
        case let .systemError(op, err):
            return "\(op) failed: \(String(cString: strerror(err)))"
        case let .pathTooLong(p):
            return "socket path too long (>\(MemoryLayout<sockaddr_un>.size) bytes): \(p)"
        }
    }
}
