import Foundation

enum DesktopNewFileKind:String,CaseIterable,Identifiable {
    case text,rtf,xml,word,excel,powerpoint,markdown,python
    var id:String { rawValue }
    var title:String {
        switch self {
        case .text:return "TXT";case .rtf:return "RTF";case .xml:return "XML"
        case .word:return "Word";case .excel:return "Excel";case .powerpoint:return "PPT"
        case .markdown:return "Markdown";case .python:return "Python"
        }
    }
    var ext:String {
        switch self {
        case .text:return "txt";case .rtf:return "rtf";case .xml:return "xml"
        case .word:return "docx";case .excel:return "xlsx";case .powerpoint:return "pptx"
        case .markdown:return "md";case .python:return "py"
        }
    }
    var editableContents:Bool { ![Self.word,.excel,.powerpoint].contains(self) }
    var defaultName:String { "新建\(title)文件.\(ext)" }
    var initialContents:String {
        switch self {
        case .xml:return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<root>\n</root>\n"
        case .python:return "# -*- coding: utf-8 -*-\n"
        default:return ""
        }
    }
    func data(contents:String,templates:URL? = Bundle.main.resourceURL?.appendingPathComponent("NewFileTemplates"))throws->Data {
        guard contents.utf8.count <= 1024*1024 else { throw DesktopBoxFileError.textTooLarge }
        if !editableContents {
            guard let file=templates?.appendingPathComponent("blank.\(ext)") else { throw CocoaError(.fileReadNoSuchFile) }
            return try Data(contentsOf:file,options:.mappedIfSafe)
        }
        if self == .rtf {
            var escaped=""
            for unit in contents.utf16 {
                switch unit {
                case 10:escaped += "\\par\n"
                case 13:break
                case 9:escaped += "\\tab "
                case 92,123,125:escaped += "\\"+String(UnicodeScalar(unit)!)
                case 32...126:escaped += String(UnicodeScalar(unit)!)
                default:escaped += "\\u\(Int16(bitPattern:unit))?"
                }
            }
            return Data(("{\\rtf1\\ansi\\deff0{\\fonttbl{\\f0 Helvetica;}}\\f0\\fs24 "+escaped+"}").utf8)
        }
        return Data(contents.utf8)
    }
}
