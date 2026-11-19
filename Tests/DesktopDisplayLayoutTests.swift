import AppKit

@main struct DesktopDisplayLayoutTests {
    static func main() throws {
        let laptop=DesktopDisplay(id:"built-in",frame:CGRect(x:0,y:0,width:1440,height:900),visibleFrame:CGRect(x:0,y:24,width:1440,height:850),scale:2)
        let external=DesktopDisplay(id:"external-stable-uuid",frame:CGRect(x:-2560,y:0,width:2560,height:1440),visibleFrame:CGRect(x:-2560,y:24,width:2560,height:1390),scale:2)
        let single=DesktopDisplayEnvironment(displays:[laptop])
        let extended=DesktopDisplayEnvironment(displays:[laptop,external])
        var mirrored=external;mirrored.mirroredTo=laptop.id
        let mirror=DesktopDisplayEnvironment(displays:[laptop,mirrored])
        precondition(Set([single.key,extended.key,mirror.key]).count==3)
        precondition(extended.key==DesktopDisplayEnvironment(displays:[external,laptop]).key)
        var dockChanged=laptop;dockChanged=DesktopDisplay(id:laptop.id,frame:laptop.frame,visibleFrame:CGRect(x:0,y:100,width:1400,height:750),scale:laptop.scale)
        precondition(single.key==DesktopDisplayEnvironment(displays:[dockChanged]).key)
        var memory=DesktopBoxLayoutMemory();let id=UUID()
        let a=CGRect(x:100,y:400,width:600,height:300),b=CGRect(x:-2400,y:700,width:1000,height:500),c=CGRect(x:250,y:200,width:500,height:240)
        memory.remember(a,for:id,in:single);memory.remember(b,for:id,in:extended);memory.remember(c,for:id,in:mirror)
        // Fitting on unplug must never rewrite the outgoing external profile.
        memory.remember(DesktopBoxLayout.fitted(b,screens:single.screens),for:id,in:single)
        precondition(memory.frame(for:id,in:extended)==b && memory.frame(for:id,in:mirror)==c)
        memory.remember(a,for:id,in:single)
        let restored=try JSONDecoder().decode(DesktopBoxLayoutMemory.self,from:JSONEncoder().encode(memory))
        precondition(restored.frame(for:id,in:single)==a && restored.frame(for:id,in:extended)==b && restored.frame(for:id,in:mirror)==c)
        precondition(restored.frame(for:UUID(),in:single)==nil)
        print("Passed single/extended/mirrored display keys, order stability, work-area changes, isolated placement profiles and restart persistence")
    }
}
