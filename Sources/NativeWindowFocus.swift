import ApplicationServices
import Carbon
import Darwin

/// Targeted compatibility handoff for WPS document windows whose AX root is
/// missing. The window-key notification format is adapted from MIT-licensed
/// Amethyst (Ian Ynda-Hummel); see Licenses/Amethyst-MIT.txt. No pointer warp or
/// keyboard input is generated. Calls are optional and never run during scans.
final class NativeWindowFocus {
    private typealias ProcessLookup = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> Int32
    private typealias Handoff = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UInt32, UInt32) -> Int32
    private typealias KeyNotification = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeRawPointer) -> Int32
    private typealias FrontWindowOnly = @convention(c) (UnsafePointer<ProcessSerialNumber>, UInt32) -> Int32
    private let lookup: ProcessLookup?
    private let handoff: Handoff?
    private let notify: KeyNotification?
    private let frontWindowOnly:FrontWindowOnly?
    private(set) var status = "notRequested"
    var available: Bool { lookup != nil && handoff != nil && notify != nil }

    init() {
        let symbols = UnsafeMutableRawPointer(bitPattern: -2)
        lookup = dlsym(symbols, "GetProcessForPID").map { unsafeBitCast($0, to: ProcessLookup.self) }
        handoff = dlsym(symbols, "_SLPSSetFrontProcessWithOptions").map { unsafeBitCast($0, to: Handoff.self) }
        notify = dlsym(symbols, "SLPSPostEventRecordTo").map { unsafeBitCast($0, to: KeyNotification.self) }
        frontWindowOnly = dlsym(symbols,"SetFrontProcessWithOptions").map { unsafeBitCast($0,to:FrontWindowOnly.self) }
    }

    /// Documented Carbon flag: activate only the front non-floating window.
    /// The caller first makes its exact AX target the application's main window.
    func activateFrontWindowOnly(pid:pid_t,isCurrent:()->Bool)->Bool {
        guard pid != getpid(),let lookup,let frontWindowOnly,isCurrent() else { return false }
        var process=ProcessSerialNumber()
        guard lookup(pid,&process)==0,isCurrent() else { return false }
        let result=frontWindowOnly(&process,UInt32(kSetFrontProcessFrontWindowOnly | kSetFrontProcessCausedByUser))
        status="frontWindowOnly:\(result)";return result==0
    }

    @discardableResult
    func request(pid: pid_t, windowID: CGWindowID, isCurrent: () -> Bool) -> Bool {
        status = "unavailableOrCancelled"
        guard pid != getpid(), windowID != 0, let lookup, let handoff, let notify, isCurrent() else { return false }
        var process = ProcessSerialNumber()
        let processStatus = lookup(pid, &process)
        status = "process:\(processStatus)"
        guard processStatus == 0, isCurrent() else { return false }
        let handoffStatus = handoff(&process, windowID, 0x200)
        status = "handoff:\(handoffStatus)"
        guard handoffStatus == 0 else { return false }
        for phase: UInt8 in [1, 2] {
            guard isCurrent() else { return false }
            var record = [UInt8](repeating: 0, count: 248)
            record[4] = 248
            record[8] = phase
            record[58] = 16
            record.replaceSubrange(32..<48, with: repeatElement(UInt8.max, count: 16))
            var identifier = windowID.littleEndian
            withUnsafeBytes(of: &identifier) { record.replaceSubrange(60..<64, with: $0) }
            let notificationStatus = record.withUnsafeBytes { notify(&process, $0.baseAddress!) }
            status = "key\(phase):\(notificationStatus)"
            guard notificationStatus == 0 else { return false }
        }
        return true
    }
}
