import Foundation

struct IndexedFile: Decodable, Identifiable {
    let path: String
    let directory: Bool
    let size: Int64?
    let modified: Double?
    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }
    var name: String { url.lastPathComponent.isEmpty ? path : url.lastPathComponent }
    var parent: String { url.deletingLastPathComponent().path }
    var kind: String { directory ? "文件夹" : (url.pathExtension.isEmpty ? "文件" : url.pathExtension.uppercased()) }
}

enum FileSearchKind: String, CaseIterable, Identifiable {
    case all = "全部", documents = "文档", images = "图片", media = "影音", folders = "文件夹", archives = "压缩包"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .documents: return "doc.text"
        case .images: return "photo"
        case .media: return "play.rectangle"
        case .folders: return "folder"
        case .archives: return "archivebox"
        }
    }
    var expression: String {
        switch self {
        case .all: return ""
        case .documents: return "ext:pdf;doc;docx;pages;txt;md;rtf;ppt;pptx;xls;xlsx;numbers;key"
        case .images: return "ext:png;jpg;jpeg;heic;gif;webp;tif;tiff;svg;psd"
        case .media: return "ext:mp4;mov;mkv;avi;mp3;m4a;wav;flac;aac"
        case .folders: return "folder:"
        case .archives: return "ext:zip;7z;rar;tar;gz;dmg"
        }
    }
    func query(_ text: String) -> String {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if expression.isEmpty { return text }
        return text.isEmpty ? expression : "(\(text)) \(expression)"
    }
}

struct FileSearchSettings: Codable {
    var root = "/"
    var showHidden = false
}

struct CardinalEvent: Decodable {
    let event: String
    let id: UInt64?
    let count: Int?
    let rows: [IndexedFile]?
    let total: Int?
    let milliseconds: Double?
    let message: String?
    let restored: Bool?
    let watching: Bool?
}
