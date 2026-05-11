import Darwin
import Foundation

// Command dispatch for the control socket. Switches on the command
// name, decodes args into the typed payload, calls into the app
// (via the weak AppDelegate), and wraps the result in a
// ControlResponse. Errors flow back through ControlError → message.

@MainActor
enum ControlHandlers {
    static func dispatch(_ req: ControlRequest, delegate: AppDelegate?) -> ControlResponse {
        do {
            switch req.cmd {
            case "ping":
                return try handlePing(req: req)
            default:
                throw ControlError.unknownCommand(req.cmd)
            }
        } catch let error as ControlError {
            return ControlResponse.failure(id: req.id, error: error.message)
        } catch {
            return ControlResponse.failure(id: req.id, error: error.localizedDescription)
        }
    }

    private static func handlePing(req: ControlRequest) throws -> ControlResponse {
        let result = PingResult(
            version: ControlProtocol.version,
            pid: getpid()
        )
        return ControlResponse.success(id: req.id, result: result)
    }
}
