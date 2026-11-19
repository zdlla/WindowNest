import AppKit
import SwiftUI
import Combine

private struct UpdatePreferences:Codable {
    var automatic=true
    var lastCheck:Date?
    var notifiedVersion:String?
}
@MainActor final class UpdateController:ObservableObject {
    @Published private(set) var busy=false
    @Published private(set) var status=""
    @Published private(set) var available:VerifiedUpdate?
    @Published private(set) var automatic=true
    var mayInstall:()->Bool = { true }
    let currentVersion=Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "0.0.0"
    private let url:URL
    private var preferences=UpdatePreferences()
    private var task:Task<Void,Never>?
    init() {
        url=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("WindowNest/update-settings.json")
        if let data=try? Data(contentsOf:url),let saved=try? JSONDecoder().decode(UpdatePreferences.self,from:data) { preferences=saved }
        automatic=preferences.automatic
    }
    private func save() { try? PrivateStorage.write(JSONEncoder().encode(preferences),to:url) }
    func setAutomatic(_ value:Bool) { automatic=value;preferences.automatic=value;save() }
    func checkIfDue() {
        guard automatic,!busy,Date().timeIntervalSince(preferences.lastCheck ?? .distantPast)>86400 else { return }
        check(manual:false)
    }
    func check(manual:Bool=true) {
        guard !busy else { return };busy=true;status="正在检查更新…"
        preferences.lastCheck=Date();save()
        task=Task { @MainActor in
            var handedOff=false
            defer { if !handedOff { self.busy=false } }
            do {
                let update=try await UpdateFeed.latest()
                guard let next=ReleaseVersion(update.manifest.version),let current=ReleaseVersion(self.currentVersion) else { throw UpdateError.invalidManifest }
                if next>current {
                    self.available=update;self.status="发现新版 \(update.manifest.version)"
                    if manual || self.preferences.notifiedVersion != update.manifest.version {
                        self.preferences.notifiedVersion=update.manifest.version;self.save()
                        let alert=NSAlert();alert.messageText="发现窗匣 \(update.manifest.version)"
                        alert.informativeText=String(update.manifest.notes.prefix(1800))+"\n\n更新只替换 App，保留本机设置、文件盒绑定、布局和个人文件。"
                        alert.addButton(withTitle:"下载并更新");alert.addButton(withTitle:"稍后")
                        if alert.runModal() == .alertFirstButtonReturn {
                            self.busy=false;handedOff=true;self.install(update)
                        }
                    }
                } else { self.available=nil;self.status="已是最新版本（\(self.currentVersion)）" }
            } catch { self.status="检查失败：\(error.localizedDescription)" }
        }
    }
    func install(_ update:VerifiedUpdate) {
        guard !busy else { return }
        guard mayInstall() else { status="请先等待文件移动或重命名完成，再安装更新。";return }
        let minimum=update.manifest.minimumSystemVersion.split(separator:".").compactMap { Int($0) }
        guard minimum.count>=2,ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion:minimum[0],minorVersion:minimum[1],patchVersion:minimum.count>2 ? minimum[2] : 0)) else { status=UpdateError.systemTooOld.localizedDescription;return }
        let target=Bundle.main.bundleURL.standardizedFileURL
        guard target.pathExtension=="app",!target.path.contains("AppTranslocation"),FileManager.default.isWritableFile(atPath:target.deletingLastPathComponent().path) else {
            status="请先将窗匣安装到可写的应用程序文件夹，再更新。";return
        }
        busy=true;status="正在下载并核验更新…"
        task=Task { @MainActor in
            do {
                let session=UpdateFeed.session();defer { session.finishTasksAndInvalidate() }
                let (download,response)=try await session.download(from:update.downloadURL)
                guard (response as? HTTPURLResponse)?.statusCode==200 else { throw UpdateError.invalidArchive }
                let work=url.deletingLastPathComponent().appendingPathComponent("Updates/\(UUID()).noindex",isDirectory:true)
                let staged=try await Task.detached(priority:.utility) {
                    try FileManager.default.createDirectory(at:work,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
                    let archive=work.appendingPathComponent("update.zip")
                    try FileManager.default.moveItem(at:download,to:archive)
                    try UpdatePolicy.verifyArchive(archive,manifest:update.manifest)
                    return try UpdateInstallation.prepare(archive:archive,work:work,manifest:update.manifest)
                }.value
                guard self.mayInstall() else { throw UpdateError.installation("文件操作仍在进行，请完成后重新更新。") }
                guard let script=Bundle.main.url(forResource:"install-update",withExtension:"sh") else { throw UpdateError.installation("安装组件缺失。") }
                let process=Process();process.executableURL=URL(fileURLWithPath:"/bin/sh")
                process.arguments=[script.path,String(getpid()),staged.path,target.path,work.path]
                process.standardInput=FileHandle.nullDevice;process.standardOutput=FileHandle.nullDevice;process.standardError=FileHandle.nullDevice
                try process.run();self.status="即将重启，配置与文件会保留。";NSApp.terminate(nil)
            } catch { self.status="更新未完成：\(error.localizedDescription)";self.busy=false }
        }
    }
}
enum UpdateInstallation {
    static func run(_ executable:String,_ arguments:[String])throws->Data {
        let process=Process(),pipe=Pipe();process.executableURL=URL(fileURLWithPath:executable);process.arguments=arguments
        process.standardOutput=pipe;process.standardError=FileHandle.nullDevice
        try process.run();let data=pipe.fileHandleForReading.readDataToEndOfFile();process.waitUntilExit()
        guard process.terminationStatus==0 else { throw UpdateError.invalidArchive };return data
    }
    static func prepare(archive:URL,work:URL,manifest:UpdateManifest)throws->URL {
        let listing=try run("/usr/bin/unzip",["-Z1",archive.path])
        guard listing.count<2*1024*1024,let text=String(data:listing,encoding:.utf8) else { throw UpdateError.invalidArchive }
        let entries=text.split(separator:"\n")
        guard !entries.isEmpty,entries.allSatisfy({ !$0.hasPrefix("/") && !$0.split(separator:"/").contains("..") && ($0.hasPrefix("窗匣.app/") || $0.hasPrefix("__MACOSX/")) }) else { throw UpdateError.invalidArchive }
        let output=work.appendingPathComponent("payload",isDirectory:true)
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        _=try run("/usr/bin/ditto",["-x","-k",archive.path,output.path])
        let app=output.appendingPathComponent("窗匣.app",isDirectory:true)
        let info=try PropertyListSerialization.propertyList(from:Data(contentsOf:app.appendingPathComponent("Contents/Info.plist")),format:nil) as? [String:Any]
        guard info?["CFBundleIdentifier"] as? String == "local.windownest.app",info?["CFBundleShortVersionString"] as? String == manifest.version,
              String(describing:info?["CFBundleVersion"] ?? "") == String(manifest.build) else { throw UpdateError.invalidArchive }
        _=try run("/usr/bin/codesign",["--verify","--deep","--strict",app.path]);return app
    }
}
struct UpdateSettings:View {
    @ObservedObject var controller:UpdateController
    var body:some View {
        Section {
            HStack {
                Text("当前版本 \(controller.currentVersion)");Spacer()
                Button(controller.busy ? "正在处理…" : "检查更新") { controller.check() }.disabled(controller.busy)
            }
            Toggle("自动检查更新并提醒",isOn:Binding(get:{controller.automatic},set:{controller.setAutomatic($0)}))
            if !controller.status.isEmpty { Text(controller.status).font(.system(size:12)).foregroundStyle(.secondary) }
            if let update=controller.available { Button("下载并更新至 \(update.manifest.version)") { controller.install(update) }.disabled(controller.busy) }
            Link("GitHub 发行页面",destination:UpdatePolicy.releasesURL)
        } header:{ Text("软件更新") } footer:{ Text("自动检查每天最多一次，仅向 GitHub 请求公开版本信息；不上传文件、目录、索引或设置。更新保留本机数据，安装包经过签名及校验和核验。") }
    }
}
