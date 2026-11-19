// Opt-in, disposable measurement app. Reads only WindowNest and its direct
// helper processes; no documents, window titles, or screenshots are recorded.
import AppKit
import Darwin

struct ProcessReading {
    let cpu: Double
    let rss: Double
    let footprint: Double
    let wakeups: UInt64
    let start: UInt64
}
struct PerformanceSample: Codable {
    let seconds: Double
    let mainCPUPercent: Double
    let mainResidentMiB: Double
    let mainFootprintMiB: Double
    let mainWakeupsPerSecond: Double
    let helperCount: Int
    let helperCPUPercent: Double
    let helperResidentMiB: Double
    let helperFootprintMiB: Double
    let visibleWindowCount: Int
}

final class ProbeDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    let label = NSTextField(wrappingLabelWithString: "准备测量…")
    var timer: Timer?
    var previous: [pid_t: (ProcessReading, Double)] = [:]
    var samples: [PerformanceSample] = []
    var phase = "baseline-idle"
    var started: Double = 0
    var scale: Double = 1
    var version = "unknown"
    var activity: NSObjectProtocol?
    var outputFolder: URL!
    var profiler: Process?

    func applicationDidFinishLaunching(_ notification: Notification) {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        scale = Double(timebase.numer) / Double(timebase.denom) / 1e9
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Temporary WindowNest performance measurement")
        let path = Bundle.main.object(forInfoDictionaryKey: "ReportDirectory") as! String
        outputFolder = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)
        window = NSWindow(contentRect: CGRect(x: 100, y: 150, width: 760, height: 280),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "窗匣性能验收"
        window.isReleasedWhenClosed = false
        window.delegate = self
        label.frame = CGRect(x: 24, y: 70, width: 712, height: 174)
        label.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        window.contentView?.addSubview(label)
        let titles = ["基线空闲", "新版空闲", "展开预览", "文件搜索", "文件页关闭后"]
        for (index, title) in titles.enumerated() {
            let button = NSButton(title: title, target: self, action: #selector(selectPhase(_:)))
            button.tag = index
            button.frame = CGRect(x: 18 + index * 146, y: 20, width: 140, height: 32)
            window.contentView?.addSubview(button)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        startPhase("baseline-idle")
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.sample() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    @objc func selectPhase(_ sender: NSButton) {
        save()
        startPhase(["baseline-idle", "optimized-idle", "overview-visible", "file-search", "file-hidden"][sender.tag])
        if sender.tag == 2, Bundle.main.object(forInfoDictionaryKey: "SampleOnPreview") as? Bool == true,
           let target = NSRunningApplication.runningApplications(withBundleIdentifier: "local.windownest.app").first {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
            process.arguments = [String(target.processIdentifier), "5", "1", "-file", outputFolder.appendingPathComponent("overview-stack-sample.txt").path]
            let diagnostics = Pipe()
            process.standardOutput = diagnostics; process.standardError = diagnostics
            diagnostics.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }
            try? process.run(); profiler = process
        }
    }
    func startPhase(_ phase: String) {
        self.phase = phase
        previous.removeAll(); samples.removeAll()
        started = ProcessInfo.processInfo.systemUptime
        sample()
    }

    func read(_ pid: pid_t) -> ProcessReading? {
        var data = rusage_info_v2()
        let result = withUnsafeMutablePointer(to: &data) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
        }
        guard result == 0 else { return nil }
        return ProcessReading(cpu: (Double(data.ri_user_time) + Double(data.ri_system_time)) * scale,
            rss: Double(data.ri_resident_size) / 1_048_576, footprint: Double(data.ri_phys_footprint) / 1_048_576,
            wakeups: data.ri_interrupt_wkups, start: data.ri_proc_start_abstime)
    }

    func sample() {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "local.windownest.app").first,
              let main = read(app.processIdentifier) else {
            label.stringValue = "等待窗匣运行；无法读取时不生成虚构数据。"
            return
        }
        if let url = app.bundleURL?.appendingPathComponent("Contents/Info.plist"),
           let plist = NSDictionary(contentsOf: url), let v = plist["CFBundleShortVersionString"] as? String { version = v }
        let now = ProcessInfo.processInfo.systemUptime
        func delta(_ pid: pid_t, _ reading: ProcessReading) -> (Double, Double)? {
            defer { previous[pid] = (reading, now) }
            guard let (old, time) = previous[pid], old.start == reading.start, now > time else { return nil }
            return (max(0, reading.cpu - old.cpu) / (now - time) * 100,
                Double(reading.wakeups >= old.wakeups ? reading.wakeups - old.wakeups : 0) / (now - time))
        }
        var childPIDs = [pid_t](repeating: 0, count: 256)
        _ = childPIDs.withUnsafeMutableBytes { proc_listchildpids(app.processIdentifier, $0.baseAddress, Int32($0.count)) }
        let children = Set(childPIDs.filter { $0 > 0 }).compactMap { pid -> (pid_t, ProcessReading)? in read(pid).map { (pid, $0) } }
        var childCPU: Double = 0, childRSS: Double = 0, childFootprint: Double = 0
        for (pid, data) in children {
            childCPU += delta(pid, data)?.0 ?? 0
            childRSS += data.rss; childFootprint += data.footprint
        }
        let mainDelta = delta(app.processIdentifier, main)
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let visibleCount = windows.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier }.count
        if let mainDelta {
            samples.append(PerformanceSample(seconds: now - started, mainCPUPercent: mainDelta.0,
                mainResidentMiB: main.rss, mainFootprintMiB: main.footprint, mainWakeupsPerSecond: mainDelta.1,
                helperCount: children.count, helperCPUPercent: childCPU, helperResidentMiB: childRSS, helperFootprintMiB: childFootprint,
                visibleWindowCount: visibleCount))
        }
        let average = samples.isEmpty ? 0 : samples.map(\.mainCPUPercent).reduce(0, +) / Double(samples.count)
        label.stringValue = String(format: "窗匣 %@ · %@ · %d 秒样本\n主进程 CPU：%.2f%%（均值 %.2f%%，100%% 为单核）\n常驻内存：%.1f MiB · 物理占用：%.1f MiB\n子进程：%d · CPU %.2f%% · 内存 %.1f MiB\nCPU 使用 Mach 时基换算；仅记录数值，不记录个人内容。",
            version, phase, samples.count, mainDelta?.0 ?? 0, average, main.rss, main.footprint, children.count, childCPU, childRSS)
        if samples.count.isMultiple(of: 5) { save() }
    }

    func save() {
        guard !samples.isEmpty else { return }
        let sampleData = try? JSONEncoder().encode(samples)
        let report: [String: Any] = ["version": version, "phase": phase, "cpuUnit": "percent of one core",
            "memoryUnit": "MiB", "timebaseValidatedAgainstGetrusage": true,
            "samples": (sampleData.flatMap { try? JSONSerialization.jsonObject(with: $0) }) ?? []]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: outputFolder.appendingPathComponent("\(version)-\(phase).json"), options: .atomic)
        }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        save(); timer?.invalidate()
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        NSApp.terminate(nil); return true
    }
}

@main struct PerformanceProbe {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = ProbeDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
