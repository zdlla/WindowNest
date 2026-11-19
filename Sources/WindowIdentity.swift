import Foundation
import CoreGraphics

enum WindowNaming {
    static func label(app: String, title: String, document: String?, isFinder: Bool) -> String {
        if isFinder, let document, let url = URL(string: document), url.isFileURL {
            let name = url.lastPathComponent
            if !name.isEmpty { return name }
        }
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty { return clean }
        if let document, let url = URL(string: document), url.isFileURL, !url.lastPathComponent.isEmpty {
            return url.lastPathComponent
        }
        return "\(app) · 未命名窗口"
    }

    static func matches(query: String, fields: [String]) -> Bool {
        let terms = query.split(whereSeparator: \.isWhitespace)
        let text = fields.joined(separator: " ")
        return terms.allSatisfy { text.range(of: String($0), options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}

struct WindowGeometry {
    static func same(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 3 && abs(a.minY - b.minY) < 3 &&
        abs(a.width - b.width) < 3 && abs(a.height - b.height) < 3
    }
}
