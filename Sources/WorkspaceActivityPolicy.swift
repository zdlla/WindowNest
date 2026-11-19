import Foundation

enum WorkspaceActivityPolicy {
    static func allowsWork(visible: Bool, miniaturized: Bool, occluded: Bool, suspended: Bool) -> Bool {
        visible && !miniaturized && !occluded && !suspended
    }
}

/// Mouse motion may arrive at 120–240 Hz. Keep dwell/leave clocks and mouse
/// buttons immediate; only redundant motion samples share one 60 Hz budget.
struct OverviewMotionBudget {
    private var previous: TimeInterval?
    mutating func accept(time: TimeInterval, motion: Bool) -> Bool {
        if motion, let previous, time >= previous, time - previous < 1.0 / 60 { return false }
        previous = time
        return true
    }
}

struct WindowDiscoveryBudget {
    private var retries: [Int32: [UInt32: TimeInterval]] = [:]
    mutating func prune(pids: Set<Int32>) { retries = retries.filter { pids.contains($0.key) } }
    mutating func eligible(pid: Int32, candidates: Set<UInt32>, now: TimeInterval) -> Set<UInt32> {
        retries[pid] = (retries[pid] ?? [:]).filter { candidates.contains($0.key) }
        return candidates.filter { now >= (retries[pid]?[$0] ?? -.infinity) }
    }
    mutating func attempted(pid: Int32, requested: Set<UInt32>, resolved: Set<UInt32>, now: TimeInterval) {
        for id in requested { retries[pid, default: [:]][id] = resolved.contains(id) ? nil : now + 2 }
    }
}
