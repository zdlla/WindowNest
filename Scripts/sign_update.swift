import Foundation
import CryptoKit
import Darwin

umask(0o077)
let args=CommandLine.arguments
let keyURL=URL(fileURLWithPath:args[2])
if args[1] == "init" {
    try FileManager.default.createDirectory(at:keyURL.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
    let key:Curve25519.Signing.PrivateKey
    if FileManager.default.fileExists(atPath:keyURL.path) { key=try .init(rawRepresentation:Data(contentsOf:keyURL)) }
    else { key = .init();try key.rawRepresentation.write(to:keyURL,options:.atomic);chmod(keyURL.path,0o600) }
    let publicKey=key.publicKey.rawRepresentation.base64EncodedString()
    try (publicKey+"\n").write(to:URL(fileURLWithPath:args[3]),atomically:true,encoding:.utf8)
    print(publicKey)
} else if args[1] == "sign" {
    let key=try Curve25519.Signing.PrivateKey(rawRepresentation:Data(contentsOf:keyURL))
    let signature=try key.signature(for:Data(contentsOf:URL(fileURLWithPath:args[3])))
    try (signature.base64EncodedString()+"\n").write(to:URL(fileURLWithPath:args[4]),atomically:true,encoding:.utf8)
    print("Signed update manifest")
} else { exit(2) }
