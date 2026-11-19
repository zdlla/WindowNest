import SwiftUI

/// One row fades out, switches its data, then fades in. No duplicate screenshot
/// trees, interpolated card positions, or stale selection tasks on quick clicks.
@MainActor
final class WindowFilterTransition: ObservableObject {
    @Published private(set) var displayedApp: String?
    @Published private(set) var contentVisible = true
    @Published private(set) var offset: CGFloat = 0
    private var task: Task<Void, Never>?
    private var generation: UInt64 = 0

    func select(_ app: String?, animated: Bool, simple: Bool, order: [String] = []) {
        generation &+= 1
        let token = generation
        task?.cancel(); task = nil
        if !animated || displayedApp == app {
            displayedApp = app; contentVisible = true; offset = 0
            return
        }
        let direction = InteractionMotion.filterDirection(from: displayedApp, to: app, order: order)
        offset = simple ? 0 : -direction * 6
        contentVisible = false
        task = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(simple ? 45 : 85)) } catch { return }
            guard !Task.isCancelled, let self, self.generation == token else { return }
            // Replace one tree while invisible; never interpolate unrelated
            // window positions or retain a second set of screenshot views.
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) {
                self.displayedApp = app
                self.offset = simple ? 0 : direction * 8
            }
            await Task.yield()
            guard !Task.isCancelled, self.generation == token else { return }
            withAnimation(simple ? .easeOut(duration: 0.08) : .smooth(duration: 0.22)) {
                self.contentVisible = true
                self.offset = 0
            }
            self.task = nil
        }
    }
}
