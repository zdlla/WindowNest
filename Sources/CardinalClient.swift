import Foundation

/// A private JSON-lines pipe; no shell, network endpoint or second application UI.
@MainActor
final class CardinalClient {
    var onEvent: ((CardinalEvent) -> Void)?
    var onFailure: ((String) -> Void)?
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var errors: FileHandle?
    private var pending = Data()
    private var generation = 0

    func start(root: String, cache: URL, rebuild: Bool = false) {
        stop()
        let token = generation
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/WindowNestCardinal")
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            onFailure?("搜索引擎缺失，请使用包含 Cardinal 引擎的完整窗匣应用。"); return
        }
        do {
            try PrivateStorage.ensureDirectory(cache.deletingLastPathComponent())
            if rebuild && FileManager.default.fileExists(atPath: cache.path) { try FileManager.default.removeItem(at: cache) }
            let process = Process()
            let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
            process.executableURL = helper
            process.arguments = [root, cache.path]
            var environment = ProcessInfo.processInfo.environment
            environment["RAYON_NUM_THREADS"] = "\(min(2, ProcessInfo.processInfo.activeProcessorCount))"
            process.environment = environment
            process.standardInput = stdin; process.standardOutput = stdout; process.standardError = stderr
            stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                DispatchQueue.main.async { self?.receive(data, token: token) }
            }
            // Drain diagnostics so a full stderr pipe cannot stall the engine.
            stderr.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }
            process.terminationHandler = { [weak self] process in
                DispatchQueue.main.async {
                    guard let self, self.generation == token else { return }
                    self.onFailure?("文件搜索引擎已停止（\(process.terminationStatus)），可点击重新连接。"); self.stop()
                }
            }
            self.process = process; input = stdin.fileHandleForWriting
            output = stdout.fileHandleForReading; errors = stderr.fileHandleForReading
            try process.run()
        } catch { onFailure?("无法启动文件搜索：\(error.localizedDescription)"); stop() }
    }
    func send(id: UInt64, query: String, hidden: Bool, cancel: Bool = false, refresh: Bool = false) {
        guard let input else { return }
        do {
            var data = try JSONSerialization.data(withJSONObject: ["id": id, "query": query, "limit": 300, "hidden": hidden, "cancel": cancel, "refresh": refresh])
            data.append(0x0A)
            try input.write(contentsOf: data)
        } catch { onFailure?("无法连接文件搜索引擎，请重新连接。"); stop() }
    }
    private func receive(_ data: Data, token: Int) {
        guard token == generation else { return }
        guard !data.isEmpty else { output?.readabilityHandler = nil; return }
        pending.append(data)
        guard pending.count < 16 * 1024 * 1024 else { onFailure?("搜索响应过大，请缩小查询范围。"); stop(); return }
        while let end = pending.firstIndex(of: 0x0A) {
            let line = pending.prefix(upTo: end)
            pending.removeSubrange(...end)
            if let event = try? JSONDecoder().decode(CardinalEvent.self, from: line) { onEvent?(event) }
        }
    }
    func stop() {
        generation += 1
        output?.readabilityHandler = nil; errors?.readabilityHandler = nil
        try? input?.close(); input = nil
        // EOF cancels scans/searches. Terminate an old helper before starting a new one.
        if let process, process.isRunning { process.terminate() }
        process = nil; output = nil; errors = nil; pending.removeAll()
    }
}
