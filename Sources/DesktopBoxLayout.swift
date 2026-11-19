import Foundation
import CoreGraphics

enum DesktopBoxLayout {
    static func visibleFrame(_ expanded:CGRect,collapsed:Bool)->CGRect {
        guard collapsed else { return expanded }
        let height=min(48,expanded.height)
        return CGRect(x:expanded.minX,y:expanded.maxY-height,width:expanded.width,height:height)
    }
    static func expandedFrame(_ visible:CGRect,rememberedHeight:CGFloat,collapsed:Bool)->CGRect {
        guard collapsed else { return visible }
        return CGRect(x:visible.minX,y:visible.maxY-rememberedHeight,width:visible.width,height:rememberedHeight)
    }
    static func fitted(_ frame:CGRect, screens:[CGRect]) -> CGRect {
        let screens=screens.filter { !$0.isEmpty && !$0.isNull && !$0.isInfinite }
        guard let first=screens.first else { return frame }
        let safe=frame.isNull || frame.isInfinite || !frame.origin.x.isFinite || !frame.origin.y.isFinite ? CGRect(x:first.minX,y:first.minY,width:700,height:320) : frame
        func area(_ screen:CGRect)->CGFloat { let r=screen.intersection(safe);return r.isNull ? 0 : r.width*r.height }
        let best=screens.max { a,b in
            if area(a) != area(b) { return area(a)<area(b) }
            return hypot(a.midX-safe.midX,a.midY-safe.midY)>hypot(b.midX-safe.midX,b.midY-safe.midY)
        } ?? first
        let width=min(best.width,max(360,safe.width.isFinite ? safe.width : 700))
        let height=min(best.height,max(180,safe.height.isFinite ? safe.height : 320))
        return CGRect(x:min(max(best.minX,safe.minX),best.maxX-width),y:min(max(best.minY,safe.minY),best.maxY-height),width:width,height:height)
    }
    static func columns(width:CGFloat,textWidth:CGFloat,iconWidth:CGFloat)->Int {
        // 10pt outside padding; each cell has a 15-character label, icon,
        // 8pt icon gap and 6pt padding on either side. Never squeeze the label.
        let cell=max(1,textWidth)+iconWidth+8+12
        return width >= 20+cell*2+10 ? 2 : 1
    }
}
