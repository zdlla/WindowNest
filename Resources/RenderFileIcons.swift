// Offline build asset generation. Runtime loads only the bundled 96px PNGs.
import AppKit
import Foundation

let source=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
let destination=URL(fileURLWithPath:CommandLine.arguments[2],isDirectory:true)
try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
let extensions="7z ai bmp css csv doc docx epub gif gz heic html image jpg js json key md mov mp3 mp4 pages pdf png ppt pptx psd py rar rtf svg tar tiff txt wav xls xlsx xml zip".split(separator:" ").map(String.init)
for ext in extensions {
    let icon:String,hex:String
    if ["bmp","gif","heic","image","jpg","png","psd","svg","tiff","ai"].contains(ext) { icon="file-image";hex="#31985C" }
    else if ["csv","xls","xlsx"].contains(ext) { icon="file-spreadsheet";hex="#21815C" }
    else if ["key","ppt","pptx"].contains(ext) { icon="file-chart-column";hex="#D4791A" }
    else if ["7z","gz","rar","tar","zip"].contains(ext) { icon="file-archive";hex="#8554C8" }
    else if ["mp3","wav"].contains(ext) { icon="file-music";hex="#7455BD" }
    else if ["mov","mp4"].contains(ext) { icon="file-video-camera";hex="#BD5A43" }
    else if ["css","html","js","json","py","xml"].contains(ext) { icon="file-code";hex="#5C697E" }
    else { icon="file-text";hex=ext == "pdf" ? "#CA3B42" : ["doc","docx","pages"].contains(ext) ? "#3579C6" : "#697180" }
    var svg=try String(contentsOf:source.appendingPathComponent(icon+".svg"),encoding:.utf8).replacingOccurrences(of:"currentColor",with:hex)
    if let first=svg.range(of:"<path ") { svg.insert(contentsOf:"fill=\"#ffffff\" ",at:first.upperBound) }
    guard let original=NSImage(data:Data(svg.utf8)),
          let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:96,pixelsHigh:96,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),
          let context=NSGraphicsContext(bitmapImageRep:bitmap) else { fatalError("Cannot render selected Lucide asset") }
    let value=UInt32(hex.dropFirst(),radix:16)!
    let tint=NSColor(calibratedRed:CGFloat((value>>16)&255)/255,green:CGFloat((value>>8)&255)/255,blue:CGFloat(value&255)/255,alpha:1)
    NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=context
    context.imageInterpolation = .high
    NSColor.clear.setFill();NSRect(x:0,y:0,width:96,height:96).fill(using:.copy)
    original.draw(in:NSRect(x:8,y:8,width:80,height:80))
    tint.setFill();NSBezierPath(roundedRect:NSRect(x:20,y:4,width:56,height:20),xRadius:5,yRadius:5).fill()
    let text=(ext == "image" ? "IMG" : ext.uppercased()) as NSString
    let attributes:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:11,weight:.bold),.foregroundColor:NSColor.white]
    let size=text.size(withAttributes:attributes)
    text.draw(at:NSPoint(x:(96-size.width)/2,y:7),withAttributes:attributes)
    NSGraphicsContext.restoreGraphicsState()
    guard let data=bitmap.representation(using:.png,properties:[:]) else { fatalError("Cannot encode bundled asset") }
    try data.write(to:destination.appendingPathComponent(ext+".png"),options:.atomic)
}
print("Rendered \(extensions.count) file-type PNGs from selected Lucide SVGs")
