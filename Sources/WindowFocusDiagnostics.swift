import Foundation

/// One small, private, local WPS diagnostic snapshot. No document titles,
/// paths, contents, screenshots, or keyboard input are recorded.
final class WindowFocusDiagnostics: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [[String: Any]] = []
    private let started = ProcessInfo.processInfo.systemUptime
    private static let output = DispatchQueue(label: "local.windownest.focus-diagnostics", qos: .utility)
    private static var newest: TimeInterval = 0

    init(pid: Int32, windowID: UInt32?, minimized: Bool, fullScreen: Bool) {
        add(["targetPID": pid, "targetWindowID": windowID ?? 0,
             "recordMinimized": minimized, "recordFullScreen": fullScreen])
    }
    func add(_ value: [String: Any]) {
        lock.lock(); defer { lock.unlock() }
        guard samples.count < 16 else { return }
        samples.append(value)
    }
    func finish(error: String?) {
        lock.lock(); let snapshot = samples; lock.unlock()
        let sequence = started
        Self.output.async {
            guard sequence >= Self.newest else { return }
            Self.newest = sequence
            let value: [String: Any] = ["success": error == nil, "message": error ?? "", "samples": snapshot]
            let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("WindowNest", isDirectory: true)
            if let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]) {
                try? PrivateStorage.write(data, to: folder.appendingPathComponent("window-focus-diagnostics.json"))
            }
        }
    }
}
