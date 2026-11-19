import SwiftUI

@main
struct FolderInteractionTests {
    @MainActor static func main() async throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            guard condition() else { fatalError(message) }; checks += 1
        }
        let presentation = FolderPresentation()
        let first = LibraryScope.category(UUID()), second = LibraryScope.category(UUID())
        presentation.show(first)
        check(presentation.scope == first && !presentation.visible, "New scope mounts before becoming visible")
        try await Task.sleep(for: .milliseconds(45))
        check(presentation.visible, "Mounted panel becomes visible")
        presentation.dismiss(after: 0.1)
        check(presentation.scope == first && !presentation.visible, "Closing retains the original scope and icon order")
        presentation.show(second)
        try await Task.sleep(for: .milliseconds(160))
        check(presentation.scope == second && presentation.visible, "Stale dismissal cannot remove a newly opened folder")
        presentation.dismiss(after: 0.05)
        try await Task.sleep(for: .milliseconds(100))
        check(presentation.scope == nil && !presentation.visible, "Completed close releases its scope")
        presentation.show(first)
        presentation.reset()
        try await Task.sleep(for: .milliseconds(50))
        check(presentation.scope == nil && !presentation.visible, "Leaving a page cancels pending insertion")
        print("Passed \(checks) folder presentation lifecycle checks")
    }
}
