import AppKit

@main struct DesktopBoxNativeGeometryTests {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("WindowNest-NativeGeometry-\(UUID())")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let prefs=AppearanceStore(repository:AppearanceRepository(url:root.appendingPathComponent("prefs.json")))
        let controller=DesktopFileBoxController(preferences:prefs,configURL:root.appendingPathComponent("boxes.json"))
        controller.create()
        guard let model=controller.models.first,let window=NSApp.windows.first(where:{$0.title == "窗匣 · 桌面文件盒"}) else { fatalError("Missing owned test window") }
        defer { controller.shutdown();window.close() }
        RunLoop.current.run(until:Date().addingTimeInterval(0.15))
        let original=window.frame
        for _ in 0..<3 {
            controller.setCollapsed(model,true)
            RunLoop.current.run(until:Date().addingTimeInterval(0.15))
            precondition(window.frame.height == 48)
            precondition(window.frame.maxY == original.maxY)
            precondition(model.configuration.height == original.height)
            precondition(!window.styleMask.contains(.resizable))
            controller.setCollapsed(model,false)
            RunLoop.current.run(until:Date().addingTimeInterval(0.15))
            precondition(window.frame == original)
        }
        controller.setLocked(model,true);controller.setCollapsed(model,true)
        precondition(!window.isMovable && window.frame.height == 48)
        controller.setCollapsed(model,false)
        precondition(!window.isMovable && window.frame == original)
        print("Passed native AppKit window fold/expand cycles, anchor, remembered height and locked geometry checks; no user folders loaded")
    }
}
