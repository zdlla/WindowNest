import Foundation

enum DesktopBoxItemClickPolicy {
    enum Action:Equatable { case select, open, rename, none }
    static func action(clickCount:Int,wasSelected:Bool,onName:Bool)->Action {
        if clickCount == 2 { return .open }
        guard clickCount == 1 else { return .none }
        return wasSelected && onName ? .rename : .select
    }
}

