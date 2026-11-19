import Foundation
import CryptoKit

struct ReleaseVersion:Comparable,Equatable {
    let parts:[Int]
    init?(_ value:String) {
        let text=value.hasPrefix("v") ? String(value.dropFirst()) : value
        let fields=text.split(separator:".",omittingEmptySubsequences:false)
        guard fields.count==3,fields.allSatisfy({!$0.isEmpty && $0.allSatisfy(\.isNumber)}),fields.compactMap({Int($0)}).count==3 else { return nil }
        parts=fields.compactMap { Int($0) }
    }
    static func <(a:Self,b:Self)->Bool { a.parts.lexicographicallyPrecedes(b.parts) }
}
struct UpdateManifest:Codable {
    let version:String
    let build:Int
    let repository:String
    let minimumSystemVersion:String
    let artifact:String
    let sha256:String
    let bytes:Int
    let notes:String
}
enum UpdatePolicy {
    static let repository="zdlla/WindowNest"
    static let publicKey="AniixdafuqigBUxbdziMW3wcAcip6+O89IbMrlgYMt0="
    static let latestURL=URL(string:"https://api.github.com/repos/zdlla/WindowNest/releases/latest")!
    static let releasesURL=URL(string:"https://github.com/zdlla/WindowNest/releases/latest")!
    static func verified(_ data:Data,signature:Data,publicKey:String=publicKey)throws->UpdateManifest {
        guard data.count<128*1024,let raw=Data(base64Encoded:publicKey),let key=try? Curve25519.Signing.PublicKey(rawRepresentation:raw),
              let signatureText=String(data:signature,encoding:.utf8),let bytes=Data(base64Encoded:signatureText.trimmingCharacters(in:.whitespacesAndNewlines)),
              key.isValidSignature(bytes,for:data) else { throw UpdateError.invalidSignature }
        let manifest=try JSONDecoder().decode(UpdateManifest.self,from:data)
        guard ReleaseVersion(manifest.version) != nil,manifest.build>0,manifest.repository==repository,
              manifest.artifact=="WindowNest-\(manifest.version)-universal.zip",manifest.sha256.count==64,
              manifest.sha256.allSatisfy({"0123456789abcdef".contains($0)}),manifest.bytes>0,manifest.bytes<=80*1024*1024 else { throw UpdateError.invalidManifest }
        return manifest
    }
    static func downloadURL(_ string:String,tag:String,name:String)throws->URL {
        guard let url=URL(string:string),url.scheme=="https",url.host=="github.com",url.user==nil,url.password==nil,
              url.path=="/\(repository)/releases/download/\(tag)/\(name)",url.query==nil else { throw UpdateError.invalidManifest }
        return url
    }
    static func verifyArchive(_ file:URL,manifest:UpdateManifest)throws {
        let size=(try file.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 0
        guard size==manifest.bytes,size<=80*1024*1024 else { throw UpdateError.invalidArchive }
        let digest=SHA256.hash(data:try Data(contentsOf:file,options:.mappedIfSafe)).map { String(format:"%02x",$0) }.joined()
        guard digest==manifest.sha256 else { throw UpdateError.invalidArchive }
    }
}
enum UpdateError:LocalizedError {
    case invalidSignature,invalidManifest,invalidArchive,noRelease,systemTooOld,installation(String)
    var errorDescription:String? {
        switch self {
        case .invalidSignature:return "更新签名核验未通过，已停止更新。"
        case .invalidManifest:return "更新信息不完整或来源不匹配。"
        case .invalidArchive:return "安装包校验未通过，已保留当前版本。"
        case .noRelease:return "GitHub 上暂时没有正式发行版本。"
        case .systemTooOld:return "新版需要更高版本的 macOS。"
        case .installation(let reason):return reason
        }
    }
}
struct GitHubRelease:Decodable {
    struct Asset:Decodable { let name:String;let browser_download_url:String;let size:Int }
    let tag_name:String
    let draft:Bool
    let prerelease:Bool
    let assets:[Asset]
}
struct VerifiedUpdate {
    let manifest:UpdateManifest
    let downloadURL:URL
}
enum UpdateFeed {
    static func session()->URLSession {
        let config=URLSessionConfiguration.ephemeral;config.urlCache=nil;config.httpCookieStorage=nil
        config.timeoutIntervalForRequest=20;config.timeoutIntervalForResource=180
        return URLSession(configuration:config)
    }
    static func data(_ url:URL,session:URLSession,maximum:Int)async throws->Data {
        var request=URLRequest(url:url);request.setValue("application/vnd.github+json",forHTTPHeaderField:"Accept")
        request.setValue("WindowNest-update-check",forHTTPHeaderField:"User-Agent")
        let (data,response)=try await session.data(for:request)
        guard let response=response as? HTTPURLResponse,response.statusCode==200,data.count<=maximum else {
            if (response as? HTTPURLResponse)?.statusCode==404 { throw UpdateError.noRelease };throw UpdateError.invalidManifest
        }
        return data
    }
    static func latest()async throws->VerifiedUpdate {
        let session=session();defer { session.finishTasksAndInvalidate() }
        let release=try JSONDecoder().decode(GitHubRelease.self,from:await data(UpdatePolicy.latestURL,session:session,maximum:1024*1024))
        guard !release.draft,!release.prerelease,ReleaseVersion(release.tag_name) != nil,
              let manifestAsset=release.assets.first(where:{$0.name=="update-manifest.json"}),
              let signatureAsset=release.assets.first(where:{$0.name=="update-manifest.sig"}) else { throw UpdateError.invalidManifest }
        let manifestURL=try UpdatePolicy.downloadURL(manifestAsset.browser_download_url,tag:release.tag_name,name:manifestAsset.name)
        let signatureURL=try UpdatePolicy.downloadURL(signatureAsset.browser_download_url,tag:release.tag_name,name:signatureAsset.name)
        let manifestData=try await data(manifestURL,session:session,maximum:128*1024)
        let signature=try await data(signatureURL,session:session,maximum:1024)
        let manifest=try UpdatePolicy.verified(manifestData,signature:signature)
        guard release.tag_name=="v"+manifest.version,let archive=release.assets.first(where:{$0.name==manifest.artifact}),archive.size==manifest.bytes else { throw UpdateError.invalidManifest }
        return VerifiedUpdate(manifest:manifest,downloadURL:try UpdatePolicy.downloadURL(archive.browser_download_url,tag:release.tag_name,name:archive.name))
    }
}
