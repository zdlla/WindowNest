import Foundation

@main struct DesktopBoxInteractionTests {
    static func main() {
        typealias P=DesktopBoxItemClickPolicy
        precondition(P.action(clickCount:1,wasSelected:false,onName:true) == .select)
        precondition(P.action(clickCount:1,wasSelected:false,onName:false) == .select)
        precondition(P.action(clickCount:1,wasSelected:true,onName:true) == .rename)
        precondition(P.action(clickCount:1,wasSelected:true,onName:false) == .select)
        for selected in [false,true] { for name in [false,true] {
            precondition(P.action(clickCount:2,wasSelected:selected,onName:name) == .open)
            precondition(P.action(clickCount:3,wasSelected:selected,onName:name) == .none)
        } }
        print("Passed selection, slow name-click rename, fast double-click open and triple-click suppression checks")
    }
}
