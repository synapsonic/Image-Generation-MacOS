import SwiftUI
import Combine

@MainActor
final class EditorState: ObservableObject {
    @Published var selectedLayerID: UUID?
    @Published var prompt = ""
    @Published var negativePrompt = ""
    @Published var selectedModel = "OpenAI Image"
    @Published var zoom: Double = 0.72
    @Published var seed = "Random"
    @Published var isGenerating = false
    @Published var generationError: String?
    @Published var layers: [SceneLayer] = []
    @Published var baseImage: NSImage?
    @Published var history: [LayerVersion] = []
    @Published var showMaskOverlay = true
    @Published var selectionMode = false
    @Published var selectionRadius: Double = 0.18
    @Published var segmentationTolerance: Double = 0.30
    @Published var isSegmenting = false
    @Published var compareBefore = false
    private var undoStack: [(UUID, NSImage?, String)] = []
    private var redoStack: [(UUID, NSImage?, String)] = []
    private let segmentationProvider: any SegmentationProvider = LocalRegionSegmentationProvider()

    func findLayer(id: UUID, in nodes: [SceneLayer]? = nil) -> SceneLayer? {
        for node in nodes ?? layers { if node.id == id { return node }; if let hit = findLayer(id: id, in: node.children) { return hit } }
        return nil
    }
    func select(_ layer: SceneLayer) { selectedLayerID = layer.id; prompt = layer.prompt; selectedModel = layer.model }
    func addLayer() { let node = SceneLayer(name: "New AI Layer", icon: "sparkles", prompt: "Describe this layer…", mask: LayerMask(shape: .center)); layers.append(node); select(node) }
    func selectObject(at point: CGPoint) {
        guard let source = compositeImage ?? baseImage else { return }
        isSegmenting = true
        generationError = nil
        let parentID = selectedLayerID
        Task {
            do {
                let result = try await segmentationProvider.segment(.init(image: source, point: point, tolerance: segmentationTolerance))
                var mask = LayerMask(shape: .full, inset: 0, feather: 0.04, centerX: point.x, centerY: point.y)
                mask.bitmap = result.maskImage
                let node = SceneLayer(name: "Smart selection", icon: "wand.and.stars", prompt: "Describe how this selected object should change…", kind: .subject, mask: mask)
                if let id = parentID, let parent = findLayer(id: id) { parent.children.append(node); parent.objectWillChange.send() }
                else if let root = layers.first { root.children.append(node); root.objectWillChange.send() }
                else { layers.append(node) }
                select(node); selectionMode = false; objectWillChange.send()
            } catch { generationError = error.localizedDescription }
            isSegmenting = false
        }
    }
    var compositeImage: NSImage? {
        if compareBefore, let id=selectedLayerID, let layer=findLayer(id:id), let previous=layer.versions.dropLast().last?.image { return previous }
        return LayerCompositor.render(base: baseImage, roots: layers)
    }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    func undo() { guard let action=undoStack.popLast(), let layer=findLayer(id:action.0) else{return}; redoStack.append((layer.id,layer.image,layer.prompt)); layer.image=action.1; layer.prompt=action.2; prompt=layer.prompt; objectWillChange.send() }
    func redo() { guard let action=redoStack.popLast(), let layer=findLayer(id:action.0) else{return}; undoStack.append((layer.id,layer.image,layer.prompt)); layer.image=action.1; layer.prompt=action.2; prompt=layer.prompt; objectWillChange.send() }
    func restore(_ version: LayerVersion) { guard let id=selectedLayerID, let layer=findLayer(id:id) else{return}; undoStack.append((id,layer.image,layer.prompt)); redoStack.removeAll(); layer.image=version.image; layer.prompt=version.prompt; prompt=version.prompt; objectWillChange.send() }
    func generateInitial(provider: AIProvider) { generate(provider: provider, initial: true) }
    func regenerate(provider: AIProvider) { generate(provider: provider, initial: layers.isEmpty) }

    private func generate(provider: AIProvider, initial: Bool) {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isGenerating = true; generationError = nil
        let requestedPrompt = prompt
        Task {
            do {
                let result: GeneratedImage
                if !initial, let id=selectedLayerID, let layer=findLayer(id:id), let mask=layer.mask.bitmap, let canvas=compositeImage {
                    result = try await AIImageService.edit(prompt: requestedPrompt, image: canvas, mask: mask, provider: provider)
                } else { result = try await AIImageService.generate(prompt: requestedPrompt, provider: provider) }
                let version = LayerVersion(image: result.image, prompt: requestedPrompt, provider: provider, createdAt: Date())
                if initial || layers.isEmpty {
                    baseImage = result.image
                    layers = SceneGraphBuilder.build(from: requestedPrompt, baseImage: result.image)
                    history.append(version)
                    if let root = layers.first { root.versions.append(version); select(root) }
                } else if let id = selectedLayerID, let layer = findLayer(id: id) {
                    undoStack.append((id,layer.image,layer.prompt)); redoStack.removeAll()
                    layer.prompt = requestedPrompt; layer.image = result.image; layer.versions.append(version); history.append(version)
                    if let first = layers.first, layer === first { baseImage = result.image }
                    objectWillChange.send()
                }
            } catch { generationError = error.localizedDescription }
            isGenerating = false
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var app: AppState
    @StateObject private var editor = EditorState()
    var body: some View {
        VStack(spacing: 0) { topBar; Divider(); HSplitView { layersPanel.frame(minWidth: 220, idealWidth: 260, maxWidth: 360); canvasPanel.frame(minWidth: 500); inspectorPanel.frame(minWidth: 280, idealWidth: 320, maxWidth: 400) }; Divider(); historyBar }
        .frame(minWidth: 1100, minHeight: 700).background(Color(nsColor: .windowBackgroundColor)).preferredColorScheme(.dark)
        .sheet(isPresented: $app.showSettings) { ProviderSettingsView().environmentObject(app) }
    }
    private var topBar: some View { HStack(spacing: 14) { Image(systemName:"sparkles.rectangle.stack.fill").foregroundStyle(.purple); Text("LayerAI").font(.headline); Divider().frame(height:18); Text("Untitled.aiimg").foregroundStyle(.secondary); Spacer(); Button{editor.undo()}label:{Image(systemName:"arrow.uturn.backward")}.keyboardShortcut("z",modifiers:.command).disabled(!editor.canUndo); Button{editor.redo()}label:{Image(systemName:"arrow.uturn.forward")}.keyboardShortcut("z",modifiers:[.command,.shift]).disabled(!editor.canRedo); Button("Export"){}.buttonStyle(.bordered); Button{app.showSettings=true}label:{Image(systemName:"gearshape")}.buttonStyle(.plain) }.padding(.horizontal,14).frame(height:48) }
    private var layersPanel: some View { VStack(spacing:0) { header("LAYERS", trailing: AnyView(Button(action:editor.addLayer){Image(systemName:"plus")}.buttonStyle(.plain))); if editor.layers.isEmpty { ContentUnavailableView("No scene yet", systemImage:"square.3.layers.3d", description:Text("Enter a scene prompt and generate it.")) } else { ScrollView { LazyVStack(alignment:.leading,spacing:2) { ForEach(editor.layers){ LayerRow(node:$0, depth:0, editor:editor) } }.padding(8) } }; Divider(); HStack { Button(action:editor.addLayer){Image(systemName:"plus")}; Spacer(); Text("Recursive scene graph").font(.caption2).foregroundStyle(.secondary) }.buttonStyle(.plain).padding(10) }.background(Color(nsColor:.controlBackgroundColor).opacity(0.55)) }
    private var canvasPanel: some View { ZStack { Color(nsColor:.underPageBackgroundColor).opacity(0.45); CanvasGrid().opacity(0.25); VStack { HStack { Button { editor.selectionMode.toggle() } label: { Label(editor.selectionMode ? "Click an object…" : "Select Object", systemImage: editor.selectionMode ? "scope" : "cursorarrow.click.2") }.buttonStyle(.borderedProminent).tint(editor.selectionMode ? .orange : .purple).disabled(displayedImage == nil); if editor.selectionMode { Text(editor.isSegmenting ? "Analyzing pixels…" : "Click an object: Local Smart Select follows connected similar pixels").font(.caption).foregroundStyle(.secondary) }; Spacer(); Toggle("Before",isOn:$editor.compareBefore).toggleStyle(.button).disabled(editor.selectedLayerID == nil) }.padding(14); Spacer() }; ZStack { RoundedRectangle(cornerRadius:4).fill(.black); if let image = displayedImage { GeometryReader { geo in ZStack { Image(nsImage:image).resizable().scaledToFit().frame(maxWidth:.infinity,maxHeight:.infinity); if editor.showMaskOverlay, let id=editor.selectedLayerID, let layer=editor.findLayer(id:id), layer.kind != .group { MaskOverlay(mask:layer.mask).allowsHitTesting(false) }; if editor.selectionMode { Color.clear.contentShape(Rectangle()).gesture(SpatialTapGesture().onEnded { value in let p=CGPoint(x:max(0,min(1,value.location.x/geo.size.width)),y:max(0,min(1,value.location.y/geo.size.height))); editor.selectObject(at:p) }).overlay { Image(systemName:"scope").font(.system(size:30)).foregroundStyle(.orange).allowsHitTesting(false) } } } } } else { VStack(spacing:12){Image(systemName:"sparkles").font(.system(size:52)).foregroundStyle(.secondary); Text("Describe your first scene").font(.title2); Text("LayerAI will generate the image and create its editable scene graph.").font(.caption).foregroundStyle(.secondary)} } }.aspectRatio(16/10,contentMode:.fit).frame(maxWidth:780).scaleEffect(editor.zoom).shadow(radius:24); VStack { Spacer(); HStack { Button{editor.zoom=max(0.25,editor.zoom-0.1)}label:{Image(systemName:"minus")}; Text("\(Int(editor.zoom*100))%").font(.caption.monospacedDigit()); Button{editor.zoom=min(2,editor.zoom+0.1)}label:{Image(systemName:"plus")} }.buttonStyle(.plain).padding(10).background(.ultraThinMaterial,in:Capsule()).padding(.bottom,16) } } }
    private var displayedImage: NSImage? { editor.compositeImage }
    private var inspectorPanel: some View { VStack(spacing:0) { header("AI INSPECTOR", trailing:nil); ScrollView { VStack(alignment:.leading,spacing:16) { if let id=editor.selectedLayerID, let layer=editor.findLayer(id:id) { Label(layer.name,systemImage:layer.icon).font(.headline); Text("\(layer.children.count) child layers • \(layer.versions.count) versions").font(.caption).foregroundStyle(.secondary) } else { Text("NEW COMPOSITION").font(.caption.bold()).foregroundStyle(.secondary) }; section("PROMPT") { TextEditor(text:$editor.prompt).scrollContentBackground(.hidden).padding(8).frame(minHeight:120).background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:8)) }; section("MODEL") { Picker("",selection:$editor.selectedModel){Text("OpenAI Image").tag("OpenAI Image");Text("FLUX").tag("FLUX");Text("Gemini Image").tag("Gemini Image")}.labelsHidden() }; section("LAYER") { if let id=editor.selectedLayerID, let layer=editor.findLayer(id:id) { LayerInspectorControls(layer: layer, editor: editor) } }; section("NEGATIVE PROMPT") { TextField("Things to avoid…",text:$editor.negativePrompt).textFieldStyle(.roundedBorder) }; Button { editor.regenerate(provider:app.provider) } label: { HStack { if editor.isGenerating { ProgressView().controlSize(.small) } else { Image(systemName:"sparkles") }; Text(editor.layers.isEmpty ? "Generate layered scene" : "Regenerate selected layer").fontWeight(.semibold); Spacer() }.padding(.vertical,7) }.buttonStyle(.borderedProminent).tint(.purple).disabled(editor.isGenerating || editor.prompt.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty); if !editor.layers.isEmpty { Text("A regenerated child gets its own image/version while the rest of the scene graph is preserved. Pixel-perfect masked compositing is the next engine stage.").font(.caption).foregroundStyle(.secondary) }; HStack { Image(systemName:app.provider.icon); Text(app.provider.rawValue); Spacer(); Button("Change"){app.showSettings=true}.buttonStyle(.plain).foregroundStyle(.purple) }.font(.caption).foregroundStyle(.secondary); if let error=editor.generationError { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) } }.padding(14) } }.background(Color(nsColor:.controlBackgroundColor).opacity(0.55)) }
    private var historyBar: some View { HStack { Text("VERSIONS").font(.caption2.bold()).foregroundStyle(.secondary); ScrollView(.horizontal,showsIndicators:false) { HStack { if let id=editor.selectedLayerID, let layer=editor.findLayer(id:id) { ForEach(layer.versions) { item in Button { editor.restore(item) } label: { Image(nsImage:item.image).resizable().scaledToFill().frame(width:54,height:34).clipped().clipShape(RoundedRectangle(cornerRadius:5)) }.buttonStyle(.plain).help("Restore: \(item.prompt)") } } } }; Spacer(); Text("⌘Z Undo • ⇧⌘Z Redo").font(.caption).foregroundStyle(.secondary) }.padding(.horizontal,12).frame(height:54) }
    private func header(_ title:String,trailing:AnyView?)->some View { HStack { Text(title).font(.caption2.bold()).tracking(1.3).foregroundStyle(.secondary); Spacer(); if let trailing { trailing } }.padding(.horizontal,12).frame(height:38).background(.black.opacity(0.08)) }
    private func section<C:View>(_ title:String,@ViewBuilder content:()->C)->some View { VStack(alignment:.leading,spacing:7){Text(title).font(.caption2.bold()).foregroundStyle(.secondary);content()} }
}

struct LayerRow: View { @ObservedObject var node: SceneLayer; let depth:Int; @ObservedObject var editor:EditorState; @State private var expanded=true
    var body: some View { VStack(alignment:.leading,spacing:1) { HStack(spacing:6) { if !node.children.isEmpty { Button{expanded.toggle()}label:{Image(systemName:expanded ? "chevron.down":"chevron.right").font(.system(size:9)).frame(width:12)}.buttonStyle(.plain) } else { Color.clear.frame(width:12,height:12) }; Image(systemName:node.icon).frame(width:17); Text(node.name).font(.system(size:12.5)); Spacer(); if !node.versions.isEmpty { Text("\(node.versions.count)").font(.caption2).padding(.horizontal,5).background(.white.opacity(0.08),in:Capsule()) }; Button { node.isVisible.toggle(); editor.objectWillChange.send() } label: { Image(systemName:node.isVisible ? "eye":"eye.slash").font(.system(size:10)).foregroundStyle(.secondary) }.buttonStyle(.plain) }.padding(.leading,CGFloat(depth)*15).padding(.horizontal,6).frame(height:29).contentShape(Rectangle()).background(editor.selectedLayerID==node.id ? Color.purple.opacity(0.42):Color.clear,in:RoundedRectangle(cornerRadius:5)).onTapGesture{editor.select(node)}; if expanded { ForEach(node.children){LayerRow(node:$0,depth:depth+1,editor:editor)} } } }
}
struct LayerInspectorControls: View {
    @ObservedObject var layer: SceneLayer
    @ObservedObject var editor: EditorState

    var body: some View {
        Toggle("Visible", isOn: $layer.isVisible)
        HStack {
            Text("Opacity")
            Slider(value: $layer.opacity, in: 0...1)
            Text("\(Int(layer.opacity * 100))%").monospacedDigit().frame(width: 38)
        }
        Picker("Mask", selection: Binding(
            get: { layer.mask.shape },
            set: { layer.mask.shape = $0; layer.objectWillChange.send(); editor.objectWillChange.send() }
        )) {
            ForEach(LayerMaskShape.allCases) { Text($0.rawValue).tag($0) }
        }
        if layer.mask.shape != .full {
            HStack {
                Text("Inset")
                Slider(value: Binding(
                    get: { layer.mask.inset },
                    set: { layer.mask.inset = $0; layer.objectWillChange.send(); editor.objectWillChange.send() }
                ), in: 0.02...0.4)
            }
        }
        HStack {
            Text("Smart select tolerance")
            Slider(value: $editor.segmentationTolerance, in: 0.08...0.85)
        }
        Toggle("Show mask overlay", isOn: $editor.showMaskOverlay)
    }
}

struct CanvasGrid:View { var body:some View { Canvas { context,size in var path=Path(); let step:CGFloat=24; stride(from:0,through:size.width,by:step).forEach{x in path.move(to:.init(x:x,y:0));path.addLine(to:.init(x:x,y:size.height))}; stride(from:0,through:size.height,by:step).forEach{y in path.move(to:.init(x:0,y:y));path.addLine(to:.init(x:size.width,y:y))}; context.stroke(path,with:.color(.secondary.opacity(0.13)),lineWidth:0.5) } } }
#Preview { ContentView().environmentObject(AppState()) }

struct MaskOverlay: View {
    let mask: LayerMask
    var body: some View { GeometryReader { geo in
        if let bitmap = mask.bitmap {
            Image(nsImage: bitmap).resizable().scaledToFit().frame(width: geo.size.width, height: geo.size.height)
                .opacity(0.42).blendMode(.screen).overlay(Rectangle().stroke(.purple.opacity(0.75), lineWidth: 1))
        } else {
            let insetX=geo.size.width*mask.inset, insetY=geo.size.height*mask.inset
            Group {
                switch mask.shape {
                case .full: Rectangle()
                case .ellipse: Ellipse().inset(by: min(insetX,insetY))
                case .center: RoundedRectangle(cornerRadius:24).padding(.horizontal,insetX).padding(.vertical,insetY)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        Color.purple.opacity(0.9),
                        style: StrokeStyle(lineWidth: 2, dash: [7, 5])
                    )
            }
            .background(Color.purple.opacity(0.06))
        }
    }}
}
