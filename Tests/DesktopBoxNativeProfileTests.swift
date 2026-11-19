import AppKit

@main struct DesktopBoxNativeProfileTests {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("WindowNest-NativeProfiles-\(UUID())")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let prefs=AppearanceStore(repository:AppearanceRepository(url:root.appendingPathComponent("prefs.json")))
        let path=root.appendingPathComponent("boxes.json")
        let actual=NSScreen.main!
        let laptop=DesktopDisplay(id:"test-laptop",frame:actual.frame,visibleFrame:actual.visibleFrame,scale:2)
        var external=DesktopDisplay(id:"test-external",frame:actual.frame.offsetBy(dx:actual.frame.width,dy:0),visibleFrame:actual.visibleFrame.offsetBy(dx:actual.frame.width,dy:0),scale:2)
        let single=DesktopDisplayEnvironment(displays:[laptop]),extended=DesktopDisplayEnvironment(displays:[laptop,external])
        external.mirroredTo=laptop.id
        let mirror=DesktopDisplayEnvironment(displays:[laptop,external])
        var current=single
        let controller=DesktopFileBoxController(preferences:prefs,configURL:path,displayEnvironment:{current})
        controller.create()
        let model=controller.models[0]
        func visibleWindow()->NSWindow { NSApp.windows.first { $0.title == "窗匣 · 桌面文件盒" && $0.isVisible }! }
        let window=visibleWindow()
        func settle() { RunLoop.current.run(until:Date().addingTimeInterval(0.85)) }
        func place(_ rect:CGRect) {
            window.setFrame(rect,display:true)
            controller.windowDidEndLiveResize(Notification(name:NSWindow.didEndLiveResizeNotification,object:window));controller.save()
        }
        func transition(_ environment:DesktopDisplayEnvironment) {
            current=environment
            // Simulate AppKit moving the window before its screen notification.
            window.setFrame(window.frame.offsetBy(dx:8,dy:-8),display:false)
            controller.windowDidMove(Notification(name:NSWindow.didMoveNotification,object:window))
            NotificationCenter.default.post(name:NSApplication.didChangeScreenParametersNotification,object:nil);settle()
        }
        let s=actual.visibleFrame
        let a=DesktopBoxLayout.fitted(CGRect(x:s.minX+30,y:s.minY+50,width:600,height:230),screens:[s])
        let b=DesktopBoxLayout.fitted(CGRect(x:s.minX+70,y:s.minY+100,width:760,height:310),screens:[s])
        let c=DesktopBoxLayout.fitted(CGRect(x:s.minX+120,y:s.minY+140,width:480,height:200),screens:[s])
        place(a);transition(extended);place(b);transition(mirror);place(c)
        transition(single);precondition(window.frame==a,"Laptop layout must survive external and mirrored use")
        transition(extended);precondition(window.frame==b,"Extended layout must not be overwritten by automatic relocation")
        transition(mirror);precondition(window.frame==c)
        transition(extended);precondition(window.frame==b)
        controller.shutdown();window.close()
        let restarted=DesktopFileBoxController(preferences:prefs,configURL:path,displayEnvironment:{current})
        restarted.restore(atLaunch:true)
        precondition(visibleWindow().frame==b && restarted.models[0].configuration.visible)
        // A manual close can remain temporary when show-on-launch is enabled.
        visibleWindow().close();precondition(!restarted.models[0].configuration.visible);restarted.shutdown()
        let login=DesktopFileBoxController(preferences:prefs,configURL:path,displayEnvironment:{current})
        login.restore(atLaunch:true);precondition(visibleWindow().frame==b && login.models[0].configuration.visible)
        login.setShowOnLaunch(false);visibleWindow().close();login.shutdown()
        let hidden=DesktopFileBoxController(preferences:prefs,configURL:path,displayEnvironment:{current})
        hidden.restore(atLaunch:true);precondition(!hidden.showOnLaunch && !hidden.models[0].configuration.visible)
        hidden.setEnabled(false);hidden.shutdown()
        let disabled=DesktopFileBoxController(preferences:prefs,configURL:path,displayEnvironment:{current})
        disabled.restore(atLaunch:true);precondition(!disabled.enabled && !disabled.models[0].configuration.visible);disabled.shutdown()
        current=single
        let reopened=DesktopFileBoxController(preferences:prefs,configURL:path,displayEnvironment:{current})
        reopened.show(reopened.models[0]);precondition(visibleWindow().frame==a,"Explicit reopen must use the current display profile even after launch was disabled")
        reopened.shutdown();visibleWindow().close()
        precondition(model.items.isEmpty)
        print("Passed native single/extended/mirror round trips, AppKit relocation race, cold restart, login visibility and disabled preferences; no user directories loaded")
    }
}
