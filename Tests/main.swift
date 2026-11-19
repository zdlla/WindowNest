import Foundation

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !condition() { fatalError("FAIL: \(message)") }
}
check(WindowNaming.label(app: "访达", title: "Finder", document: "file:///Users/me/Documents/%E8%AE%BA%E6%96%87/", isFinder: true) == "论文", "Finder uses folder name rather than application title")
check(WindowNaming.label(app: "访达", title: "旧标题", document: "file:///Users/me/a%2520b/", isFinder: true) == "a%20b", "Literal percent sequences are decoded only once")
check(WindowNaming.label(app: "访达", title: "最近使用", document: nil, isFinder: true) == "最近使用", "Finder virtual folders retain their accessible titles")
check(WindowNaming.label(app: "编辑器", title: "  项目.swift  ", document: "file:///tmp/other.txt", isFinder: false) == "项目.swift", "Document app keeps window title")
check(WindowNaming.label(app: "预览", title: " \n", document: "file:///tmp/report.pdf", isFinder: false) == "report.pdf", "Untitled document uses filename")
check(WindowNaming.label(app: "终端", title: "", document: nil, isFinder: false) == "终端 · 未命名窗口", "Missing titles have an honest fallback")
check(WindowNaming.matches(query: "访达 论文", fields: ["访达", "论文材料"]), "Search terms can span app and folder")
check(WindowNaming.matches(query: "CAFE", fields: ["café notes"]), "Search ignores case and diacritics")
check(!WindowNaming.matches(query: "论文 财务", fields: ["论文材料"]), "All search terms must match")
check(WindowNaming.matches(query: "  ", fields: []), "Empty searches show everything")
check(WindowGeometry.same(CGRect(x: -900, y: 0, width: 600, height: 500), CGRect(x: -899, y: 1, width: 601, height: 500)), "Bounds matching tolerates rounding on secondary displays")
check(!WindowGeometry.same(CGRect(x: 0, y: 0, width: 600, height: 500), CGRect(x: 50, y: 0, width: 600, height: 500)), "Different window positions must not share thumbnails")
let fixtures = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("LibraryTests-\(UUID().uuidString)", isDirectory: true)
try FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: fixtures) }
let fakeApp = fixtures.appendingPathComponent("Example.app", isDirectory: true)
try FileManager.default.createDirectory(at: fakeApp, withIntermediateDirectories: true)
let link = fixtures.appendingPathComponent("Alias.app")
try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fakeApp)
var library = AppLibrary()
let workID = library.categories[0].id
let studyID = library.categories[2].id
try library.add(name: "Example", path: fakeApp.path, bundleID: "local.test.example", categoryID: workID)
let originalID = library.applications[0].id
try library.add(name: "Example", path: link.path, bundleID: "local.test.example", categoryID: studyID)
check(library.applications.count == 1, "Symlink and original app are deduplicated")
check(library.applications[0].id == originalID, "Reimport preserves application identity")
check(library.applications[0].categoryID == studyID, "Adding an existing app to an explicit category moves it")
try library.add(name: "Example", path: fakeApp.path, bundleID: "local.test.example", categoryID: nil)
check(library.applications[0].categoryID == studyID, "Reimport into All Apps retains an existing category")
let customID = try library.addCategory(name: "  科研工具  ", symbol: "folder")
check(library.categories.last?.name == "科研工具", "Category names are trimmed")
var duplicateRejected = false
do { _ = try library.addCategory(name: "科研工具", symbol: "folder") } catch { duplicateRejected = true }
check(duplicateRejected, "Duplicate categories are rejected")
var blankRejected = false
do { _ = try library.addCategory(name: " \n", symbol: "folder") } catch { blankRejected = true }
check(blankRejected, "Empty categories are rejected")
var tooLongRejected = false
do { _ = try library.addCategory(name: String(repeating: "长", count: 31), symbol: "folder") } catch { tooLongRejected = true }
check(tooLongRejected, "Overlong categories are rejected")
try library.renameCategory(id: customID, name: "研究")
check(library.categories.last?.name == "研究", "Renaming preserves category identity")
try library.moveApplication(id: originalID, categoryID: customID)
var badCategoryRejected = false
do { try library.moveApplication(id: originalID, categoryID: UUID()) } catch { badCategoryRejected = true }
check(badCategoryRejected && library.applications[0].categoryID == customID, "An invalid move leaves the current category unchanged")
library.reorderCategory(id: customID, offset: -1)
check(library.categories[library.categories.count - 2].id == customID, "Categories can be reordered")
library.removeCategory(id: customID)
check(library.applications.count == 1 && library.applications[0].categoryID == nil, "Removing a category keeps its apps in Uncategorized")
check(FileManager.default.fileExists(atPath: fakeApp.path), "Category changes never delete application bundles")
let repository = LibraryRepository(url: fixtures.appendingPathComponent("nested/library.json"))
let emptyLoaded = try repository.load()
check(emptyLoaded == AppLibrary(), "A missing library initializes clean defaults")
try repository.save(library)
let roundTrip = try repository.load()
check(roundTrip == library, "Library, UUIDs and category order survive a disk round trip")
var orphaned = library
orphaned.applications[0].categoryID = UUID()
try repository.save(orphaned)
let repaired = try repository.load()
check(repaired.applications[0].categoryID == nil, "Orphaned app references remain visible as Uncategorized")
var future = library
future.version = 99
try repository.save(future)
let futureBytes = try Data(contentsOf: repository.url)
var futureRejected = false
do { _ = try repository.load() } catch { futureRejected = true }
let preservedFuture = try Data(contentsOf: repository.url)
check(futureRejected && preservedFuture == futureBytes, "An unknown format is rejected without changing its file")
let corrupt = Data("not JSON".utf8)
try corrupt.write(to: repository.url)
var corruptionRejected = false
do { _ = try repository.load() } catch { corruptionRejected = true }
let preservedCorrupt = try Data(contentsOf: repository.url)
check(corruptionRejected && preservedCorrupt == corrupt, "Corrupt input is rejected and preserved")
library.removeApplication(id: originalID)
check(library.applications.isEmpty && FileManager.default.fileExists(atPath: fakeApp.path), "Removing a launcher entry preserves the original app")
var previewLibrary = AppLibrary()
for name in ["F", "B", "A", "E", "D", "C"] {
    try previewLibrary.add(name: name, path: fixtures.appendingPathComponent("\(name).app").path, bundleID: nil, categoryID: workID)
}
let four = previewLibrary.preview(in: .category(workID))
check(four.map(\.name) == ["F", "B", "A", "E"], "Folder preview follows saved manual order")
check(previewLibrary.applications(in: .category(workID)).count == 6, "Preview truncation never removes apps from an expanded folder")
check(previewLibrary.preview(in: .uncategorized).isEmpty, "Empty folders never borrow icons from other categories")
let pageRepository = WorkspaceStateRepository(url: fixtures.appendingPathComponent("page-state/workspace.json"))
let firstMode = try pageRepository.load()
check(firstMode == .windows, "A first launch has a defined fallback")
try pageRepository.save(.applications)
let reopenedApps = try WorkspaceStateRepository(url: pageRepository.url).load()
check(reopenedApps == .applications, "A new repository instance restores the last applications page from disk")
try pageRepository.save(.windows)
let reopenedWindows = try WorkspaceStateRepository(url: pageRepository.url).load()
check(reopenedWindows == .windows, "The last windows page replaces the previous applications preference")
let appLibraryBytes = try Data(contentsOf: repository.url)
try pageRepository.save(.applications)
let libraryAfterPageChange = try Data(contentsOf: repository.url)
check(appLibraryBytes == libraryAfterPageChange, "Page persistence never rewrites the app library")
func gesture(_ tracker: inout PageSwipeTracker, _ dx: Double, _ dy: Double = 0,
    _ phase: PageGesturePhase = .changed, time: Double = 0.05, mode: WorkspaceMode = .windows,
    precise: Bool = true, momentum: Bool = false) -> PageSwipeEffect {
    tracker.handle(dx: dx, dy: dy, phase: phase, precise: precise, momentum: momentum,
        timestamp: time, mode: mode, width: 900)
}
var swipe = PageSwipeTracker()
check(gesture(&swipe, 140, 0, .began, precise: false) == .pass, "A coarse mouse wheel never changes pages")
check(gesture(&swipe, 140, 0, .unphased) == .pass, "Unphased scrolling cannot start a page transition")
_ = gesture(&swipe, 1, 20, .began)
check(gesture(&swipe, 200, 1) == .pass, "A gesture that starts vertically stays a normal vertical scroll")
_ = gesture(&swipe, 0, 0, .ended)
_ = gesture(&swipe, 45, 1, .began, time: 1)
check(gesture(&swipe, 0, 0, .ended, time: 1.5) == .finish(.applications, false), "A short slow horizontal swipe rolls back")
_ = gesture(&swipe, 150, 1, .began, time: 2)
check(gesture(&swipe, 0, 0, .ended, time: 2.5) == .finish(.applications, true), "A sufficiently long swipe commits the applications page")
check(gesture(&swipe, 400, momentum: true) == .swallow, "Post-swipe momentum cannot trigger a second navigation")
check(gesture(&swipe, 0, 0, .ended) == .pass, "A duplicate end event cannot navigate twice")
_ = gesture(&swipe, -150, 1, .began, time: 3, mode: .applications)
check(gesture(&swipe, 0, 0, .ended, time: 3.5, mode: .applications) == .finish(.windows, true), "Reverse swipes return from applications to windows")
_ = gesture(&swipe, 200, 0, .began, time: 4)
check(gesture(&swipe, 0, 0, .cancelled, time: 4.1) == .finish(.applications, false), "Cancellation rolls back even a long swipe")
_ = gesture(&swipe, 55, 0, .began, time: 5)
check(gesture(&swipe, 0, 0, .ended, time: 5.02) == .finish(.applications, true), "A deliberate fast flick can commit before the distance threshold")
check(gesture(&swipe, -160, 0, .began, time: 6) == .pass, "Swiping outward past the first page does not wrap around")
_ = gesture(&swipe, 0, 0, .ended)
check(gesture(&swipe, 160, 0, .began, time: 7, mode: .files) == .pass, "Swiping outward past the last page does not wrap around")
_ = gesture(&swipe, 0, 0, .ended, mode: .applications)
_ = gesture(&swipe, 80, 0, .began, time: 8)
check(gesture(&swipe, -90, 0, .changed, time: 8.1) == .track(.applications, 0), "Reversing a swipe clamps the live transition at its starting position")
check(gesture(&swipe, 0, 0, .ended, time: 8.4) == .finish(.applications, false), "A reversed gesture returns to its original page")
_ = gesture(&swipe, 160, 0, .began, time: 9)
check(gesture(&swipe, 0, 0, .ended, time: 9.5, momentum: true) == .finish(.applications, true), "A physical end event is honored even if momentum begins on the same event")
var clickMotion = PageMotion(position: 0, destination: 1)
clickMotion.advance(by: 0.02)
check(clickMotion.position > 0 && clickMotion.position < 0.2, "Click motion starts gradually")
var previous = clickMotion.position
var monotonic = true
for _ in 0..<100 {
    clickMotion.advance(by: 0.01)
    monotonic = monotonic && clickMotion.position >= previous && clickMotion.position <= 1
    previous = clickMotion.position
}
check(monotonic && clickMotion.isSettled, "A click settles without a decorative overshoot")
var quick = PageMotion(position: 0.35, velocity: 2, destination: 1)
var slow = PageMotion(position: 0.35, velocity: 0, destination: 1)
quick.advance(by: 0.025); slow.advance(by: 0.025)
check(quick.position > slow.position, "A faster release carries its velocity forward")
var rollback = PageMotion(position: 0.13, velocity: 0, destination: 0)
rollback.advance(by: 0.2)
check(rollback.position > 0 && rollback.position < 0.02, "Short gestures return smoothly without a fixed long delay")
var oneFrame = PageMotion(position: 0.22, velocity: -0.7, destination: 1)
var manyFrames = oneFrame
oneFrame.advance(by: 0.4)
for _ in 0..<48 { manyFrames.advance(by: 1.0 / 120) }
check(abs(oneFrame.position - manyFrames.position) < 1e-10 && abs(oneFrame.velocity - manyFrames.velocity) < 1e-10,
    "Animation state is independent of frame rate or a delayed frame")
var reverseMotion = PageMotion(position: 0.5, velocity: 2, destination: 0)
reverseMotion.advance(by: 0.001)
check(reverseMotion.position > 0.5, "Retargeting preserves velocity instead of instantly reversing direction")
reverseMotion.advance(by: 0.7)
check(reverseMotion.isSettled, "Retargeted motion converges to the new destination")
var interrupted = PageSwipeTracker()
let takeover = interrupted.handle(dx: -30, dy: 0, phase: .began, precise: true, momentum: false,
    timestamp: 20, mode: .windows, width: 1000, startingPosition: 0.6)
if case let .track(mode, amount) = takeover {
    check(mode == .windows && abs(amount - 0.57) < 1e-10, "A reverse gesture can take over a partially completed forward transition")
} else {
    check(false, "A reverse gesture did not claim the partial transition")
}
_ = interrupted.handle(dx: 0, dy: 0, phase: .ended, precise: true, momentum: false,
    timestamp: 20.03, mode: .windows, width: 1000, startingPosition: 0.57)
check(interrupted.releaseVelocity < 0, "Gesture release velocity preserves its absolute direction")
var paused = PageSwipeTracker()
_ = paused.handle(dx: 60, dy: 0, phase: .began, precise: true, momentum: false,
    timestamp: 21, mode: .windows, width: 1000)
_ = paused.handle(dx: 0, dy: 0, phase: .ended, precise: true, momentum: false,
    timestamp: 21.5, mode: .windows, width: 1000)
check(paused.releaseVelocity == 0, "Pausing before release must not retain an old flick velocity")
try pageRepository.save(.files)
let savedFilesMode = try pageRepository.load()
check(savedFilesMode == .files, "The third page is persisted without changing previous mode identifiers")
var thirdSwipe = PageSwipeTracker()
_ = gesture(&thirdSwipe, 150, 0, .began, time: 30, mode: .applications)
check(gesture(&thirdSwipe, 0, 0, .ended, time: 30.5, mode: .applications) == .finish(.files, true), "Applications swipe forward to files")
_ = gesture(&thirdSwipe, -150, 0, .began, time: 31, mode: .files)
check(gesture(&thirdSwipe, 0, 0, .ended, time: 31.5, mode: .files) == .finish(.applications, true), "Files swipe backward to applications")
check(FileSearchKind.documents.query("report | notes").hasPrefix("(report | notes) ext:"), "Type filter preserves grouped user boolean logic")
check(FileSearchKind.all.query("  文档  ") == "文档", "File search trims only outer whitespace")
let fileData = Data(#"{"path":"/tmp/资料/报告.pdf","directory":false,"size":1200,"modified":1234}"#.utf8)
let decodedFile = try JSONDecoder().decode(IndexedFile.self, from: fileData)
check(decodedFile.name == "报告.pdf" && decodedFile.parent == "/tmp/资料", "File result preserves Unicode path components")
// App-library v2: migration, pins and stable per-folder order.
let preview = previewLibrary.folderPreview(in: .category(workID))
check(preview.direct.map(\.name) == ["F", "B", "A"], "Exactly the first three folder icons are direct launch targets")
check(preview.stacked.map(\.name) == ["E", "D", "C"] && preview.remainingCount == 3, "The fourth slot represents the remaining apps in manual order")
let emptyPreview = AppFolderPreview(applications: [])
check(emptyPreview.direct.isEmpty && emptyPreview.stacked.isEmpty && emptyPreview.remainingCount == 0, "Empty folders never invent preview applications")
let shortPreview = AppFolderPreview(applications: Array(previewLibrary.applications.prefix(2)))
check(shortPreview.direct.count == 2 && shortPreview.stacked.isEmpty, "Small folders keep their direct apps while retaining a separate expansion target")
var ordered = previewLibrary
let beforeIDs = Set(ordered.applications.map(\.id))
let moveID = ordered.applications(in: .category(workID))[3].id
ordered.reorderApplication(id: moveID, offset: -1)
check(ordered.applications(in: .category(workID)).map(\.name) == ["F", "B", "E", "A", "D", "C"], "Folder ordering moves only the requested adjacent positions")
let firstID = ordered.applications(in: .category(workID))[0].id
let lastID = ordered.applications(in: .category(workID)).last!.id
ordered.placeApplication(id: lastID, before: firstID)
check(ordered.applications(in: .category(workID)).first?.name == "C", "Drag-to-front moves an item before its drop target")
ordered.placeApplication(id: firstID, before: moveID)
check(ordered.applications(in: .category(workID)).map(\.name) == ["C", "B", "F", "E", "A", "D"], "Forward drag accounts for removal before insertion")
check(Set(ordered.applications.map(\.id)) == beforeIDs, "Sorting never duplicates or drops apps")
ordered.moveApplicationToEnd(id: lastID)
check(ordered.applications(in: .category(workID)).last?.id == lastID, "Dropping on folder whitespace reaches the last position")
ordered.placeApplication(id: lastID, before: ordered.applications(in: .category(workID))[0].id)
let unchangedOrder = ordered
ordered.placeApplication(id: firstID, before: firstID)
ordered.placeApplication(id: firstID, before: UUID())
ordered.reorderApplication(id: UUID(), offset: 1)
check(ordered == unchangedOrder, "Invalid and self drops do not change the library")
ordered.pinApplication(id: firstID)
ordered.pinApplication(id: lastID)
ordered.pinApplication(id: firstID)
check(ordered.pinnedApplicationIDs == [firstID, lastID], "Pinning is ordered and deduplicated")
check(ordered.applications.first(where: { $0.id == firstID })?.categoryID == workID, "Pinning preserves category membership")
ordered.reorderPinned(id: lastID, offset: -1)
check(ordered.pinnedApplicationIDs == [lastID, firstID], "Pinned apps can reorder independently")
ordered.movePinnedToEnd(id: lastID)
check(ordered.pinnedApplicationIDs == [firstID, lastID], "Dropping a pinned shortcut on blank space moves it to the row end")
let folderOrder = ordered.applications(in: .category(workID)).map(\.id)
ordered.pinApplication(id: firstID, before: lastID)
check(ordered.pinnedApplicationIDs == [firstID, lastID], "A pinned drop inserts before its target")
check(ordered.applications(in: .category(workID)).map(\.id) == folderOrder, "Pinned sorting never reorders folder apps")
ordered.unpinApplication(id: firstID)
check(ordered.applications.contains(where: { $0.id == firstID }) && !ordered.pinnedApplicationIDs.contains(firstID), "Unpin removes only the shortcut")
ordered.pinApplication(id: UUID())
check(ordered.pinnedApplicationIDs == [lastID], "Nonexistent apps cannot be pinned")
try ordered.moveApplication(id: firstID, categoryID: studyID)
let otherOrder = ordered.applications(in: .category(studyID)).map(\.id)
ordered.sortApplications(in: .category(workID))
check(ordered.applications(in: .category(workID)).map(\.name) == ["A", "B", "C", "D", "E"], "Name sorting applies to one selected folder")
check(ordered.applications(in: .category(studyID)).map(\.id) == otherOrder, "Sorting does not affect another folder")
try ordered.moveApplication(id: firstID, categoryID: workID)
check(ordered.applications(in: .category(workID)).last?.id == firstID, "Moving between folders appends to destination order")
ordered.pinApplication(id: firstID)
ordered.removeCategory(id: workID)
check(ordered.pinnedApplications.count == 2 && ordered.applications.allSatisfy { $0.categoryID == nil }, "Removing a category retains apps and pinned shortcuts")
ordered.removeApplication(id: lastID)
check(!ordered.pinnedApplicationIDs.contains(lastID) && !ordered.applications.contains(where: { $0.id == lastID }), "Removing an app cleans its pin reference")
let v2Repository = LibraryRepository(url: fixtures.appendingPathComponent("v2/library.json"))
try v2Repository.save(ordered)
let loadedV2 = try v2Repository.load()
check(loadedV2 == ordered, "Manual order and pinned order survive restart")
var v1JSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(previewLibrary)) as! [String: Any]
v1JSON["version"] = 1
v1JSON.removeValue(forKey: "pinnedApplicationIDs")
let v1Bytes = try JSONSerialization.data(withJSONObject: v1JSON)
try v1Bytes.write(to: v2Repository.url, options: .atomic)
var migrated = try v2Repository.load()
check(migrated.version == 2 && migrated.applications(in: .category(workID)).map(\.name) == ["A", "B", "C", "D", "E", "F"], "Version 1 migration preserves its displayed alphabetical order")
let afterLoad = try Data(contentsOf: v2Repository.url)
check(afterLoad == v1Bytes && migrated.pinnedApplications.isEmpty, "Reading old data never rewrites it or auto-pins private apps")
migrated.pinApplication(id: migrated.applications[0].id)
try v2Repository.save(migrated)
let backupFiles = try FileManager.default.contentsOfDirectory(at: v2Repository.url.deletingLastPathComponent().appendingPathComponent("backups"), includingPropertiesForKeys: nil)
check(backupFiles.count == 1, "The first v1-to-v2 edit creates a recovery backup")
let backupBytes = try Data(contentsOf: backupFiles[0])
check(backupBytes == v1Bytes, "Migration backup preserves the exact original file bytes")
let savedMigration = try v2Repository.load()
check(savedMigration == migrated, "Migrated data stores the selected pin and existing categories")
var brokenPins = try JSONSerialization.jsonObject(with: JSONEncoder().encode(migrated)) as! [String: Any]
brokenPins["pinnedApplicationIDs"] = [migrated.applications[0].id.uuidString, UUID().uuidString, migrated.applications[0].id.uuidString]
let cleanedPins = try JSONDecoder().decode(AppLibrary.self, from: JSONSerialization.data(withJSONObject: brokenPins))
check(cleanedPins.pinnedApplicationIDs == [migrated.applications[0].id], "Duplicate and stale pin references cannot produce empty or duplicate icons")
// The grid must fill its container without clipping the 2x2 interactive preview.
for width in [CGFloat(900), 1060, 1280, 1600] {
    let grid = FolderGridLayout(width: width)
    check(abs(CGFloat(grid.columns) * grid.side + CGFloat(grid.columns - 1) * 24 - (width - 64)) < 0.001, "Folder columns fill both content edges at \(width)")
    check(grid.icon * 2 + 12 + 32 <= grid.side + 0.001, "Four interactive icons fit within their cover at \(width)")
}
check(FolderGridLayout(width: 900).columns == 4 && FolderGridLayout(width: 1060).columns == 4, "Compact and regular windows keep a consistent four-column library")
let appearanceRepo = AppearanceRepository(url: fixtures.appendingPathComponent("appearance/preferences.json"))
let initialAppearance = try appearanceRepo.load()
check(initialAppearance.previewsEnabled && initialAppearance.effects == .soft, "New installations default to previews and soft effects")
check(!FileManager.default.fileExists(atPath: appearanceRepo.url.path), "Reading defaults never rewrites unrelated user files")
var appearance = initialAppearance
appearance.accent = .purple; appearance.appearance = .dark; appearance.effects = .minimal; appearance.previewsEnabled = false
try appearanceRepo.save(appearance)
let restoredAppearance = try appearanceRepo.load()
check(restoredAppearance == appearance, "All appearance choices and disabled previews survive reopening")
let partialAppearance = try JSONDecoder().decode(AppearanceSettings.self, from: Data("{}".utf8))
check(partialAppearance == initialAppearance, "Missing optional appearance keys keep explicit defaults")
try Data("{\"version\":2}".utf8).write(to: appearanceRepo.url)
do { _ = try appearanceRepo.load(); check(false, "Future appearance schema must not be overwritten") } catch { check(true, "Future appearance schema rejected") }
let retainedAppearance = try Data(contentsOf: appearanceRepo.url)
check(retainedAppearance == Data("{\"version\":2}".utf8), "Rejected settings stay byte-for-byte intact")
let blankBounds = CGRect(x: 0, y: 0, width: 720, height: 560)
let appRect = CGRect(x: 30, y: 90, width: 140, height: 160)
func blank(_ down: CGPoint, _ up: CGPoint, dragged: Bool = false) -> Bool {
    FolderBlankClickPolicy.dismiss(down: down, up: up, bounds: blankBounds, protected: [appRect], dragged: dragged)
}
check(blank(CGPoint(x: 300, y: 400), CGPoint(x: 301, y: 400)), "A blank click inside the panel dismisses")
check(!blank(CGPoint(x: 80, y: 130), CGPoint(x: 80, y: 130)), "App tiles retain clicks")
check(!blank(CGPoint(x: 80, y: 130), CGPoint(x: 300, y: 400)), "Dragging from an app into blank space cannot dismiss")
check(!blank(CGPoint(x: 300, y: 400), CGPoint(x: 300, y: 400), dragged: true), "A drag ending at its origin cannot dismiss")
check(!blank(CGPoint(x: -10, y: 400), CGPoint(x: 300, y: 400)), "A click starting outside the panel cannot dismiss it")
let folderPlan = FolderMotionPlan(reduced: false, effects: .soft)
check(folderPlan.itemDelay(index: 0, count: 7, entering: true) < folderPlan.itemDelay(index: 6, count: 7, entering: true), "Icons appear in reading order")
check(folderPlan.itemDelay(index: 0, count: 7, entering: false) > folderPlan.itemDelay(index: 6, count: 7, entering: false), "Icons disappear in reverse order")
check(folderPlan.itemDelay(index: 0, count: 500, entering: false) + 0.16 < folderPlan.removalDelay, "Large folders finish disappearing before panel removal")
for plan in [FolderMotionPlan(reduced: true, effects: .glass), FolderMotionPlan(reduced: false, effects: .minimal)] {
    check(plan.panelScale == 1 && plan.itemScale == 1 && plan.itemDelay(index: 4, count: 8, entering: true) == 0, "Reduced motion and minimal style remove zoom and staggering")
}
var clearAppearance = AppearanceSettings()
clearAppearance.effects = .clearGlass
let clearBytes = try JSONEncoder().encode(clearAppearance)
let clearRestored = try JSONDecoder().decode(AppearanceSettings.self, from: clearBytes)
check(clearRestored == clearAppearance && clearRestored.effects.usesGlass, "Clear glass is a separately persisted style")
let oldGlass = try JSONDecoder().decode(AppearanceSettings.self, from: Data("{\"effects\":\"glass\"}".utf8))
check(oldGlass.effects == .glass, "Existing glass settings retain their original meaning")
check(FolderMotionPlan(reduced: true, effects: .clearGlass).simple, "Clear glass still respects reduced motion")
print("Passed \(checks) total logic and motion checks")

