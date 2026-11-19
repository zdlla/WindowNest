import Combine
import Foundation

/// Transient feedback, rather than a persisted file selection. New taps replace
/// the deadline; removing/reusing a cell cancels it immediately.
@MainActor final class DesktopBoxClickFeedback: ObservableObject {
    @Published private(set) var active=false
    private var release:Task<Void,Never>?
    func click() {
        release?.cancel();active=true
        release=Task { @MainActor [weak self] in
            do { try await Task.sleep(for:.milliseconds(160)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.active=false;self?.release=nil
        }
    }
    func clear() { release?.cancel();release=nil;active=false }
    deinit { release?.cancel() }
}
