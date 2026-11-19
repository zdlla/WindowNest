import Foundation
import CryptoKit

@main struct UpdatePolicyTests {
    static func main() throws {
        let key=Curve25519.Signing.PrivateKey(),publicKey=key.publicKey.rawRepresentation.base64EncodedString()
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("WindowNest-UpdateTest-\(UUID())")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let archive=root.appendingPathComponent("archive.zip"),payload=Data("owned update fixture".utf8)
        try payload.write(to:archive)
        let digest=SHA256.hash(data:payload).map { String(format:"%02x",$0) }.joined()
        let manifest=UpdateManifest(version:"0.20.0",build:48,repository:UpdatePolicy.repository,minimumSystemVersion:"14.0",artifact:"WindowNest-0.20.0-universal.zip",sha256:digest,bytes:payload.count,notes:"Fixture")
        let data=try JSONEncoder().encode(manifest)
        let signature=Data(try key.signature(for:data).base64EncodedString().utf8)
        let verified=try UpdatePolicy.verified(data,signature:signature,publicKey:publicKey)
        precondition(verified.version=="0.20.0")
        try UpdatePolicy.verifyArchive(archive,manifest:verified)
        func rejects(_ operation:()throws->Void) { do { try operation();preconditionFailure("Accepted invalid update") } catch {} }
        rejects { _=try UpdatePolicy.verified(data+Data(" ".utf8),signature:signature,publicKey:publicKey) }
        rejects { _=try UpdatePolicy.verified(data,signature:signature) }
        try Data("tampered".utf8).write(to:archive)
        rejects { try UpdatePolicy.verifyArchive(archive,manifest:verified) }
        let good="https://github.com/zdlla/WindowNest/releases/download/v0.20.0/WindowNest-0.20.0-universal.zip"
        _=try UpdatePolicy.downloadURL(good,tag:"v0.20.0",name:manifest.artifact)
        for bad in [good.replacingOccurrences(of:"https:",with:"http:"),good.replacingOccurrences(of:"github.com",with:"other.example"),good+"?redirect=1",good.replacingOccurrences(of:"zdlla/WindowNest",with:"other/WindowNest")] {
            rejects { _=try UpdatePolicy.downloadURL(bad,tag:"v0.20.0",name:manifest.artifact) }
        }
        precondition(ReleaseVersion("0.20.0")!>ReleaseVersion("0.19.9")!)
        precondition(ReleaseVersion("0.20.10")!>ReleaseVersion("0.20.9")!)
        precondition(ReleaseVersion("v0.20.0")==ReleaseVersion("0.20.0"))
        for invalid in ["0.20","1..0","1.0.0-beta","../1.0.0","1.2.-1"] { precondition(ReleaseVersion(invalid)==nil) }
        print("Passed version ordering, signed manifests, wrong-key/tamper rejection, archive hashes and pinned release URLs")
    }
}
