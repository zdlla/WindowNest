import Foundation

/// Equal columns consume the available width exactly, so covers and captions
/// share the section edges at every supported window width.
struct FolderGridLayout {
    let columns: Int
    let side: CGFloat
    let icon: CGFloat
    init(width: CGFloat) {
        let available = max(0, width - 64)
        columns = max(1, Int(floor((available + 24) / 212)))
        side = max(0, (available - CGFloat(columns - 1) * 24) / CGFloat(columns))
        icon = min(88, max(0, (side - 44) / 2))
    }
}
