import AppKit
import CoreGraphics

struct DesktopDisplay:Equatable {
    let id:String
    let frame:CGRect
    let visibleFrame:CGRect
    var scale:Double=1
    var mirroredTo:String?=nil
}
struct DesktopDisplayEnvironment:Equatable {
    var displays:[DesktopDisplay]
    var screens:[CGRect] { displays.filter { $0.mirroredTo == nil }.map(\.visibleFrame).filter { !$0.isEmpty } }
    // Deliberately exclude the Dock/menu-bar work area: changing those should
    // fit the existing placement, not create a different display configuration.
    var key:String {
        displays.sorted { $0.id<$1.id }.map {
            let f=$0.frame
            return "\($0.id):\(Int(f.minX.rounded())),\(Int(f.minY.rounded())),\(Int(f.width.rounded())),\(Int(f.height.rounded()))@\($0.scale):\($0.mirroredTo ?? "extended")"
        }.joined(separator:";")
    }
    @MainActor static func current()->Self {
        let screens=NSScreen.screens
        var count:UInt32=0
        guard CGGetOnlineDisplayList(0,nil,&count) == .success,count>0 else { return Self(displays:[]) }
        var ids=[CGDirectDisplayID](repeating:0,count:Int(count))
        guard CGGetOnlineDisplayList(count,&ids,&count) == .success else { return Self(displays:[]) }
        func identity(_ id:CGDirectDisplayID)->String {
            if let uuid=CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() { return CFUUIDCreateString(nil,uuid) as String }
            return "display-\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(CGDisplaySerialNumber(id))"
        }
        let displays=ids.prefix(Int(count)).compactMap { id->DesktopDisplay? in
            let mirror=CGDisplayMirrorsDisplay(id)
            guard CGDisplayIsActive(id) != 0 || mirror != kCGNullDirectDisplay else { return nil }
            let screen=screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id }
            let frame=screen?.frame ?? CGDisplayBounds(id)
            guard !frame.isEmpty else { return nil }
            return DesktopDisplay(id:identity(id),frame:frame,visibleFrame:screen?.visibleFrame ?? frame,scale:Double(screen?.backingScaleFactor ?? 1),mirroredTo:mirror == kCGNullDirectDisplay ? nil : identity(mirror))
        }
        return Self(displays:displays)
    }
}

struct DesktopBoxLayoutMemory:Codable {
    private(set) var profiles:[String:[String:CGRect]]=[:]
    func frame(for id:UUID,in environment:DesktopDisplayEnvironment)->CGRect? { profiles[environment.key]?[id.uuidString] }
    mutating func remember(_ frame:CGRect,for id:UUID,in environment:DesktopDisplayEnvironment) {
        guard !environment.screens.isEmpty,!frame.isNull,!frame.isInfinite,
              frame.minX.isFinite,frame.minY.isFinite,frame.width.isFinite,frame.height.isFinite,frame.width>0,frame.height>0 else { return }
        profiles[environment.key,default:[:]][id.uuidString]=frame
    }
}
