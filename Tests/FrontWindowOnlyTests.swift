import AppKit
import Foundation
import Carbon

@main struct Test {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.regular)
        let bundle=URL(fileURLWithPath:CommandLine.arguments[1])
        let state=URL(fileURLWithPath:CommandLine.arguments[2])
        let topic=CommandLine.arguments[3]
        let previous=NSWorkspace.shared.frontmostApplication
        var fixture:NSRunningApplication?
        let config=NSWorkspace.OpenConfiguration();config.activates=true
        NSWorkspace.shared.openApplication(at:bundle,configuration:config) { app,_ in fixture=app }
        defer { fixture?.terminate();previous?.activate(options:[]) }
        func wait(_ seconds:Double) { RunLoop.current.run(until:Date().addingTimeInterval(seconds)) }
        for _ in 0..<50 where !FileManager.default.fileExists(atPath:state.path) { wait(0.1) }
        let initial=try JSONSerialization.jsonObject(with:Data(contentsOf:state)) as! [String:Any]
        let ids=initial["ids"] as! [Int];let pid=(initial["pid"] as! NSNumber).int32Value
        let overlay=NSWindow(contentRect:NSRect(x:140,y:140,width:550,height:400),styleMask:[.titled],backing:.buffered,defer:false)
        overlay.title="WindowNest front-only test overlay";overlay.isReleasedWhenClosed=false
        defer { overlay.close() }
        let focus=NativeWindowFocus()
        typealias Lookup = @convention(c) (pid_t,UnsafeMutablePointer<ProcessSerialNumber>)->Int32
        typealias Bring = @convention(c) (UnsafePointer<ProcessSerialNumber>,UInt32)->Int32
        let symbols=UnsafeMutableRawPointer(bitPattern:-2)
        let lookup=unsafeBitCast(dlsym(symbols,"GetProcessForPID")!,to:Lookup.self)
        let bring=unsafeBitCast(dlsym(symbols,"SetFrontProcessWithOptions")!,to:Bring.self)
        func report(_ label:String) {
            let entries=CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as! [[String:Any]]
            let order=entries.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.intValue }
            let text="\(label): own indices \(ids.map{order.firstIndex(of:$0) ?? -1}), overlay \(order.firstIndex(of:overlay.windowNumber) ?? -1)\n"
            FileHandle.standardOutput.write(Data(text.utf8))
        }
        for index in [0,1,0] {
            overlay.makeKeyAndOrderFront(nil)
            var owner=ProcessSerialNumber();_ = lookup(getpid(),&owner);_ = bring(&owner,UInt32(kSetFrontProcessFrontWindowOnly))
            wait(0.2);report("baseline")
            DistributedNotificationCenter.default().postNotificationName(Notification.Name(topic),object:nil,userInfo:["index":index],deliverImmediately:true)
            wait(0.2)
            report("prepared")
            if CommandLine.arguments.contains("--native") { precondition(focus.request(pid:pid,windowID:UInt32(ids[index]),isCurrent:{true})) }
            else { precondition(focus.activateFrontWindowOnly(pid:pid,isCurrent:{true})) }
            wait(0.2)
            report("activated")
            // Only numeric window IDs/order are read; no titles or file data.
            let entries=CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as! [[String:Any]]
            let order=entries.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.intValue }
            guard let target=order.firstIndex(of:ids[index]),let behind=order.firstIndex(of:ids[1-index]),let cover=order.firstIndex(of:overlay.windowNumber) else { fatalError("Missing owned test window") }
            precondition(target<cover && cover<behind,"Activation raised another window along with the selected one")
        }
        print("Passed native front-window-only activation in three selections; sibling window stayed behind the owned overlay. No personal folders or Finder windows opened.")
    }
}
