import AppKit
final class Fixture:NSObject,NSApplicationDelegate {
    var windows:[NSWindow]=[];var observer:NSObjectProtocol?
    let path=Bundle.main.object(forInfoDictionaryKey:"FixtureState") as! String
    let topic=Bundle.main.object(forInfoDictionaryKey:"FixtureTopic") as! String
    func applicationDidFinishLaunching(_ notification:Notification) {
        for index in 0..<2 {
            let window=NSWindow(contentRect:NSRect(x:150+index*20,y:150+index*20,width:500,height:350),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
            window.title="WindowNest activation test \(index)";window.isReleasedWhenClosed=false
            windows.append(window);window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate();write(-1)
        observer=DistributedNotificationCenter.default().addObserver(forName:Notification.Name(topic),object:nil,queue:.main) { [weak self] note in
            guard let self,let index=note.userInfo?["index"] as? Int,self.windows.indices.contains(index) else { return }
            self.windows[index].makeKeyAndOrderFront(nil);self.write(index)
        }
    }
    func write(_ index:Int) {
        let data=try! JSONSerialization.data(withJSONObject:["pid":getpid(),"ids":windows.map{$0.windowNumber},"prepared":index])
        try! data.write(to:URL(fileURLWithPath:path),options:.atomic)
    }
}
let app=NSApplication.shared;app.setActivationPolicy(.regular)
let delegate=Fixture();app.delegate=delegate;app.run()
