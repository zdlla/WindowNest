import Foundation

@main struct DesktopBoxClickFeedbackTests {
    @MainActor static func main() async {
        let feedback=DesktopBoxClickFeedback()
        precondition(!feedback.active)
        feedback.click();precondition(feedback.active)
        try? await Task.sleep(for:.milliseconds(350))
        precondition(!feedback.active,"A click must not leave a selected background")
        for _ in 0..<10 { feedback.click() }
        precondition(feedback.active)
        try? await Task.sleep(for:.milliseconds(350))
        precondition(!feedback.active,"Repeated taps must still expire")
        feedback.click();feedback.clear();precondition(!feedback.active)
        feedback.click();feedback.clear();feedback.click()
        try? await Task.sleep(for:.milliseconds(350))
        precondition(!feedback.active,"A reused cell must not retain a highlight")
        print("Passed click expiration, rapid taps, disappearance and reused-cell feedback checks")
    }
}
