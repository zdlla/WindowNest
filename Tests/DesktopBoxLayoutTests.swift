import Foundation
import CoreGraphics

@main struct DesktopBoxLayoutTests {
    static func main() {
        let laptop=CGRect(x:0,y:24,width:1440,height:850)
        let external=CGRect(x:1440,y:24,width:2560,height:1400)
        let original=CGRect(x:3200,y:1000,width:700,height:320)
        precondition(DesktopBoxLayout.fitted(original,screens:[laptop,external]) == original)
        let recovered=DesktopBoxLayout.fitted(original,screens:[laptop])
        precondition(laptop.contains(recovered) && recovered.size == original.size)
        let collapsed=DesktopBoxLayout.visibleFrame(recovered,collapsed:true)
        precondition(collapsed.height == 48 && collapsed.maxY == recovered.maxY && collapsed.width == recovered.width)
        precondition(DesktopBoxLayout.expandedFrame(collapsed,rememberedHeight:recovered.height,collapsed:true) == recovered)
        let movedBar=collapsed.offsetBy(dx:30,dy:-40)
        let expandedAfterMoving=DesktopBoxLayout.expandedFrame(movedBar,rememberedHeight:recovered.height,collapsed:true)
        precondition(expandedAfterMoving.maxY == movedBar.maxY && expandedAfterMoving.height == recovered.height)
        precondition(laptop.contains(DesktopBoxLayout.fitted(expandedAfterMoving,screens:[laptop])))
        let leftDisplay=CGRect(x:-1920,y:-200,width:1920,height:1080)
        let left=DesktopBoxLayout.fitted(CGRect(x:-1800,y:200,width:800,height:300),screens:[leftDisplay,laptop])
        precondition(leftDisplay.contains(left))
        let unplugged=DesktopBoxLayout.fitted(left,screens:[laptop]);precondition(laptop.contains(unplugged))
        let oversized=DesktopBoxLayout.fitted(CGRect(x:8000,y:-500,width:4000,height:2000),screens:[laptop])
        precondition(oversized == laptop)
        let partial=DesktopBoxLayout.fitted(CGRect(x:1400,y:800,width:700,height:320),screens:[laptop])
        precondition(laptop.contains(partial))
        let tiny=CGRect(x:0,y:0,width:300,height:150)
        precondition(DesktopBoxLayout.fitted(original,screens:[tiny]) == tiny)
        let text:CGFloat=195
        let threshold:CGFloat=20+(text+24+8+12)*2+10
        precondition(DesktopBoxLayout.columns(width:threshold-1,textWidth:text,iconWidth:24)==1)
        precondition(DesktopBoxLayout.columns(width:threshold,textWidth:text,iconWidth:24)==2)
        precondition(DesktopBoxLayout.columns(width:2000,textWidth:text,iconWidth:24)==2)
        for width in stride(from:100,through:2000,by:10) {
            let count=DesktopBoxLayout.columns(width:CGFloat(width),textWidth:text,iconWidth:32)
            if count==2 { precondition((CGFloat(width)-30)/2-32-8-12 >= text) }
        }
        print("Passed unplug/reconfigure, negative-coordinate display, oversize recovery and 15-character column threshold checks")
    }
}
