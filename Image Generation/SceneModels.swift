import Foundation
import AppKit
import Combine

enum LayerKind: String, Codable { case group, image, subject, background, effect }

enum LayerMaskShape: String, CaseIterable, Identifiable {
    case full = "Full canvas", ellipse = "Ellipse", center = "Center region"
    var id: String { rawValue }
}

struct LayerMask {
    var shape: LayerMaskShape = .full
    var inset: Double = 0.12
    var feather: Double = 0.08
    // Normalized canvas coordinates (0...1). Enables click-to-select masks.
    var centerX: Double = 0.5
    var centerY: Double = 0.5
    var bitmap: NSImage? = nil
}

struct LayerVersion: Identifiable {
    let id = UUID()
    let image: NSImage
    let prompt: String
    let provider: AIProvider
    let createdAt: Date
}

final class SceneLayer: ObservableObject, Identifiable {
    let id: UUID
    @Published var name: String
    @Published var icon: String
    @Published var prompt: String
    @Published var model: String
    @Published var isVisible: Bool
    @Published var opacity: Double
    @Published var image: NSImage?
    @Published var versions: [LayerVersion]
    @Published var children: [SceneLayer]
    @Published var mask: LayerMask
    let kind: LayerKind

    init(id: UUID = UUID(), name: String, icon: String = "square.3.layers.3d", prompt: String = "", model: String = "OpenAI Image", isVisible: Bool = true, opacity: Double = 1, image: NSImage? = nil, versions: [LayerVersion] = [], kind: LayerKind = .image, children: [SceneLayer] = [], mask: LayerMask = LayerMask()) {
        self.id=id; self.name=name; self.icon=icon; self.prompt=prompt; self.model=model; self.isVisible=isVisible
        self.opacity=opacity; self.image=image; self.versions=versions; self.kind=kind; self.children=children; self.mask=mask
    }
}

enum SceneGraphBuilder {
    static func build(from prompt: String, baseImage: NSImage) -> [SceneLayer] {
        let lower=prompt.lowercased(); var subjects:[SceneLayer]=[]
        if lower.contains("person") || lower.contains("woman") || lower.contains("man") || lower.contains("character") {
            subjects.append(SceneLayer(name:"Character",icon:"person.crop.rectangle",prompt:"Main character from the composition, preserve identity and pose",kind:.subject,children:[
                SceneLayer(name:"Face",icon:"face.smiling",prompt:"Face and facial details, preserve identity",kind:.subject,mask:LayerMask(shape:.ellipse,inset:0.32,feather:0.08)),
                SceneLayer(name:"Hair",icon:"wind",prompt:"Hair of the character",kind:.subject,mask:LayerMask(shape:.center,inset:0.22,feather:0.08)),
                SceneLayer(name:"Clothes",icon:"tshirt",prompt:"Character clothing and outfit",kind:.subject,mask:LayerMask(shape:.center,inset:0.16,feather:0.08))
            ],mask:LayerMask(shape:.center,inset:0.1,feather:0.08)))
        } else { subjects.append(SceneLayer(name:"Main subject",icon:"viewfinder",prompt:"Primary subject of: \(prompt)",kind:.subject,mask:LayerMask(shape:.center,inset:0.12,feather:0.08))) }
        let background=SceneLayer(name:"Background",icon:"mountain.2",prompt:"Background of: \(prompt)",kind:.background,children:[
            SceneLayer(name:"Sky / Environment",icon:"cloud",prompt:"Sky and distant environment",kind:.background),
            SceneLayer(name:"Architecture / Terrain",icon:"building.2",prompt:"Background architecture or terrain",kind:.background)
        ])
        let atmosphere=SceneLayer(name:"Atmosphere",icon:"cloud.fog",prompt:"Lighting, atmosphere, fog and global ambience",kind:.effect)
        return [SceneLayer(name:"Scene",icon:"photo.on.rectangle.angled",prompt:prompt,image:baseImage,kind:.group,children:subjects+[background,atmosphere])]
    }
}

enum LayerCompositor {
    static func render(base: NSImage?, roots: [SceneLayer]) -> NSImage? {
        guard let base else { return nil }
        let size=base.size
        let output=NSImage(size:size)
        output.lockFocus()
        base.draw(in:NSRect(origin:.zero,size:size))
        for root in roots { drawChildren(root.children, in:NSRect(origin:.zero,size:size)) }
        output.unlockFocus(); return output
    }
    private static func drawChildren(_ nodes:[SceneLayer], in rect:NSRect) {
        for node in nodes where node.isVisible {
            if let image=node.image {
                NSGraphicsContext.saveGraphicsState()
                if let bitmap = node.mask.bitmap {
                    if let cgMask = bitmap.cgImage(forProposedRect: nil, context: nil, hints: nil) { NSGraphicsContext.current?.cgContext.clip(to: rect, mask: cgMask) }
                } else { maskPath(node.mask, rect:rect).addClip() }
                image.draw(in:rect,from:.zero,operation:.sourceOver,fraction:node.opacity)
                NSGraphicsContext.restoreGraphicsState()
            }
            drawChildren(node.children,in:rect)
        }
    }
    static func maskPath(_ mask:LayerMask, rect:NSRect)->NSBezierPath {
        switch mask.shape {
        case .full: return NSBezierPath(rect:rect)
        case .ellipse:
            let w = rect.width * max(0.08, 1 - mask.inset * 2)
            let h = rect.height * max(0.08, 1 - mask.inset * 2)
            let cx = rect.minX + rect.width * mask.centerX
            let cy = rect.minY + rect.height * (1 - mask.centerY)
            return NSBezierPath(ovalIn: NSRect(x: cx-w/2, y: cy-h/2, width: w, height: h))
        case .center:
            let w = rect.width * max(0.08, 1 - mask.inset * 2)
            let h = rect.height * max(0.08, 1 - mask.inset * 2)
            let cx = rect.minX + rect.width * mask.centerX
            let cy = rect.minY + rect.height * (1 - mask.centerY)
            let r = NSRect(x: cx-w/2, y: cy-h/2, width: w, height: h)
            return NSBezierPath(roundedRect:r,xRadius:rect.width*0.05,yRadius:rect.width*0.05)
        }
    }
}
