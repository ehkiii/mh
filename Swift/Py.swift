import Foundation

enum PyError: LocalizedError {
    case start(String)
    case python(String)

    var errorDescription: String? {
        switch self {
        case .start(let m): return "Python failed to start: \(m)"
        case .python(let m): return m
        }
    }
}

/// Thin async wrapper: every call is `bridge.<function>(json) -> json`.
enum Py {
    private static let queue = DispatchQueue(label: "sealpad.python", attributes: .concurrent)
    private static let lock = NSLock()
    nonisolated(unsafe) private static var started = false

    static var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("SealPad", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Visible in the Files app thanks to UIFileSharingEnabled.
    static var downloadsDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func startIfNeeded() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !started else { return }
        do {
            try PythonBridge.start(withResourcePath: Bundle.main.resourcePath!)
        } catch {
            throw PyError.start(error.localizedDescription)
        }
        started = true
        _ = try rawCall("configure", [
            "support": supportDir.path,
            "downloads": downloadsDir.path,
        ])
    }

    private static func rawCall(_ function: String, _ payload: [String: Any]) throws -> Data {
        let json = try JSONSerialization.data(withJSONObject: payload)
        guard
            let arg = String(data: json, encoding: .utf8),
            let out = PythonBridge.callModule("bridge", function: function, argument: arg),
            let data = out.data(using: .utf8)
        else { throw PyError.python("bridge.\(function) returned nothing (see Xcode console)") }

        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let err = obj["error"] as? String {
            throw PyError.python(err)
        }
        return data
    }

    static func callSync(_ function: String, _ payload: [String: Any] = [:]) throws -> Data {
        try startIfNeeded()
        return try rawCall(function, payload)
    }

    static func call(_ function: String, _ payload: [String: Any] = [:]) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            queue.async {
                do { cont.resume(returning: try callSync(function, payload)) }
                catch { cont.resume(throwing: error) }
            }
        }
    }
}
