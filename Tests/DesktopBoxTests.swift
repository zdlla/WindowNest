import Foundation
import AppKit

@main struct DesktopBoxTests {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DesktopBoxTest-\(UUID())",isDirectory:true)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let a = root.appendingPathComponent("DemoA",isDirectory:true)
        let b = root.appendingPathComponent("DemoB",isDirectory:true)
        try FileManager.default.createDirectory(at:a,withIntermediateDirectories:true)
        try FileManager.default.createDirectory(at:b,withIntermediateDirectories:true)
        try Data("test".utf8).write(to:a.appendingPathComponent("Example.txt"))
        let sub = a.appendingPathComponent("Subfolder",isDirectory:true)
        try FileManager.default.createDirectory(at:sub,withIntermediateDirectories:true)
        try Data("nested".utf8).write(to:sub.appendingPathComponent("NotRecursed.txt"))
        try Data("hidden".utf8).write(to:a.appendingPathComponent(".hidden"))
        let entries = try DesktopBoxDirectory.read(a)
        precondition(entries.count == 2 && entries[0].directory)
        precondition(!entries.contains { $0.url.lastPathComponent == "NotRecursed.txt" })
        var config = DesktopBoxConfiguration()
        config.folders = [try QuickFolder(url:a),try QuickFolder(url:b)]
        config.selected = config.folders[0].id; config.theme = "dark"; config.width = 880
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(DesktopBoxConfiguration.self,from:data)
        precondition(decoded == config)
        let model = DesktopBoxModel(config)
        precondition(model.items.isEmpty, "Construction must not enumerate a folder")
        model.refresh()
        try? await Task.sleep(for:.milliseconds(250))
        precondition(model.items.count == 2 && !model.loading)
        model.select(config.folders[1])
        try? await Task.sleep(for:.milliseconds(150))
        precondition(model.items.isEmpty)
        let dropped=root.appendingPathComponent("DropIntoBox.txt")
        try Data("drop fixture".utf8).write(to:dropped)
        precondition(model.receiveDrop([NSItemProvider(object:dropped as NSURL)],asTabs:false))
        for _ in 0..<200 where model.fileOperationActive { try? await Task.sleep(for:.milliseconds(10)) }
        precondition(!model.fileOperationActive)
        let droppedTarget=b.appendingPathComponent("DropIntoBox.txt")
        precondition(!FileManager.default.fileExists(atPath:dropped.path) && FileManager.default.fileExists(atPath:droppedTarget.path))
        model.rename(droppedTarget,folder:config.folders[1],to:"RenamedDrop.txt",tab:false)
        for _ in 0..<200 where model.fileOperationActive { try? await Task.sleep(for:.milliseconds(10)) }
        precondition(FileManager.default.fileExists(atPath:b.appendingPathComponent("RenamedDrop.txt").path))
        let child=b.appendingPathComponent("NestedTarget",isDirectory:true)
        try FileManager.default.createDirectory(at:child,withIntermediateDirectories:true)
        model.refresh()
        for _ in 0..<200 where model.loading { try? await Task.sleep(for:.milliseconds(10)) }
        let nestedSource=root.appendingPathComponent("Inside.txt")
        try Data("nested drop".utf8).write(to:nestedSource)
        let providers=[NSItemProvider(object:nestedSource as NSURL)]
        precondition(model.receiveDrop(providers,asTabs:false,intoChild:child))
        precondition(!model.receiveDrop(providers,asTabs:false),"Parent must not also receive an accepted child drop")
        for _ in 0..<200 where model.fileOperationActive { try? await Task.sleep(for:.milliseconds(10)) }
        precondition(!FileManager.default.fileExists(atPath:nestedSource.path))
        precondition(FileManager.default.fileExists(atPath:child.appendingPathComponent("Inside.txt").path))
        precondition(!FileManager.default.fileExists(atPath:b.appendingPathComponent("Inside.txt").path))
        let outside=root.appendingPathComponent("Outside",isDirectory:true)
        try FileManager.default.createDirectory(at:outside,withIntermediateDirectories:true)
        let invalid=root.appendingPathComponent("MustRemain.txt");try Data().write(to:invalid)
        precondition(!model.receiveDrop([NSItemProvider(object:invalid as NSURL)],asTabs:false,intoChild:outside))
        precondition(FileManager.default.fileExists(atPath:invalid.path))
        let alias=b.appendingPathComponent("AliasTarget")
        try FileManager.default.createSymbolicLink(at:alias,withDestinationURL:outside)
        model.refresh()
        for _ in 0..<200 where model.loading { try? await Task.sleep(for:.milliseconds(10)) }
        precondition(!model.receiveDrop([NSItemProvider(object:invalid as NSURL)],asTabs:false,intoChild:alias))
        guard let entry=model.items.first(where:{$0.url.lastPathComponent=="NestedTarget"}) else { fatalError("Missing navigation fixture") }
        model.enter(entry)
        for _ in 0..<200 where model.loading { try? await Task.sleep(for:.milliseconds(10)) }
        precondition(model.pathComponents==["NestedTarget"] && model.items.contains(where:{$0.url.lastPathComponent=="Inside.txt"}))
        model.rename(child.appendingPathComponent("Inside.txt"),folder:config.folders[1],to:"EditedName.txt",tab:false)
        for _ in 0..<200 where model.fileOperationActive || model.loading { try? await Task.sleep(for:.milliseconds(10)) }
        precondition(FileManager.default.fileExists(atPath:child.appendingPathComponent("EditedName.txt").path))
        model.createFolder()
        for _ in 0..<200 where model.fileOperationActive || model.loading { try? await Task.sleep(for:.milliseconds(10)) }
        model.createFolder()
        for _ in 0..<200 where model.fileOperationActive || model.loading { try? await Task.sleep(for:.milliseconds(10)) }
        precondition(FileManager.default.fileExists(atPath:child.appendingPathComponent("新建文件夹 2").path))
        let deepDrop=root.appendingPathComponent("DeepDrop.txt");try Data().write(to:deepDrop)
        precondition(model.receiveDrop([NSItemProvider(object:deepDrop as NSURL)],asTabs:false))
        for _ in 0..<200 where model.fileOperationActive || model.loading { try? await Task.sleep(for:.milliseconds(10)) }
        precondition(FileManager.default.fileExists(atPath:child.appendingPathComponent("DeepDrop.txt").path))
        let browsed=try JSONDecoder().decode(DesktopBoxConfiguration.self,from:JSONEncoder().encode(model.configuration))
        precondition(browsed.browsePaths?[config.folders[1].id.uuidString]==["NestedTarget"])
        do { _=try DesktopBoxNavigation.directory(root:b,components:[".."]);preconditionFailure("Traversal accepted") } catch {}
        do { _=try DesktopBoxNavigation.directory(root:b,components:["AliasTarget"]);preconditionFailure("External symlink accepted") } catch {}
        model.navigate(to:[])
        for _ in 0..<200 where model.loading { try? await Task.sleep(for:.milliseconds(10)) }
        model.move(config.folders[1].id,by:-1)
        precondition(model.configuration.folders[0].id == config.folders[1].id)
        model.remove(config.folders[0].id)
        precondition(FileManager.default.fileExists(atPath:a.path), "Removing a tab must not remove data")
        model.stop(); precondition(model.items.isEmpty && !model.loading)
        let repo = root.appendingPathComponent("private/config.json")
        try PrivateStorage.write(data,to:repo)
        let mode = try FileManager.default.attributesOfItem(atPath:repo.path)[.posixPermissions] as! NSNumber
        precondition(mode.intValue == 0o600)
        let archiveURL=root.appendingPathComponent("private/boxes.json")
        try PrivateStorage.write(JSONEncoder().encode([config]),to:archiveURL)
        let prefs=AppearanceStore(repository:AppearanceRepository(url:root.appendingPathComponent("prefs.json")))
        let controller=DesktopFileBoxController(preferences:prefs,configURL:archiveURL)
        precondition(controller.models.count == 1 && controller.models[0].items.isEmpty)
        controller.setLocked(controller.models[0],true)
        controller.setCollapsed(controller.models[0],true)
        controller.setEnabled(false)
        let restored=DesktopFileBoxController(preferences:prefs,configURL:archiveURL)
        precondition(!restored.enabled && restored.models[0].locked && restored.models[0].collapsed)
        restored.restore()
        precondition(restored.models[0].items.isEmpty, "Disabled boxes must not load selected folders")
        print("Passed desktop-box listing, nested drops, duplicate rejection, target containment, tabs, persistence and private storage")
    }
}
