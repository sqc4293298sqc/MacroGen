import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers

/// 建模编程（iOS 对齐安卓四步）：草图 → 建模 → 出图 → 加工
struct StudioScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var spec = PartSpec()
    @State private var step = 0
    @State private var code = ""
    @State private var showResult = false
    @State private var opGenerated = false
    @State private var showOpCode = false
    @State private var opCodeTitle = ""
    @State private var opCodeText = ""
    @State private var opCodeCache: [String: String] = [:]
    @State private var opCacheSpecs: [String: PartSpec] = [:]

    // 2D 刀路检查图层
    @State private var cam2DStock = true
    @State private var cam2DPart = true
    @State private var cam2DSketch = false
    @State private var cam2DToolpath = true
    @State private var cam2DRapid = true
    @State private var cam2DPaths: [TPSeg] = []
    @State private var cam2DLayerOnly = false
    @State private var cam2DLayerZ = 0.0
    @State private var cam2DZoom = 1.0
    @State private var cam2DZoomBase = 1.0
    @State private var cam2DPanX = 0.0
    @State private var cam2DPanY = 0.0
    @State private var cam2DPanStart: CGSize = .zero

    // 3D 视角
    @State private var yaw = 0.78
    @State private var pitch = 0.62
    @State private var zoom = 1.0
    @State private var zoomBase = 1.0
    @State private var panX = 0.0
    @State private var panY = 0.0
    @State private var viewPanMode = false
    @State private var lastDrag: CGSize = .zero

    // 3D 指针
    @State private var ptrX = 0.0
    @State private var ptrY = 0.0
    @State private var hasPtr = false
    @State private var tapOnModel = false
    @State private var stepShapeEditID: UUID? = nil
    @State private var stepShapeEditBackup: PartShape? = nil

    @State private var showRotate = false
    @State private var showScale = false
    @State private var showOpSheet = false
    @State private var opSheetName = ""
    @State private var showFeatCommand = false
    @State private var featDraft: PartFeat? = nil
    @State private var featEditID: UUID? = nil
    @State private var gridStep = 10.0
    @State private var snapGrid = false
    @State private var snapVertex = false
    @State private var showModelGrid = true
    @State private var modelViewName = "等轴"
    @State private var lastTapAt: Date = .distantPast
    @State private var dragFeatID: UUID? = nil
    @State private var showDimEdit = false
    @State private var dimEditTitle = ""
    @State private var dimEditText = ""
    @State private var dimTarget: DimTarget = .none
    @State private var sketchSidePanel: SketchSidePanel = .none
    @State private var drawInner = false
    @State private var innerDraft: [ContourNode] = []
    @State private var undoStack: [PartSpec] = []
    @State private var redoStack: [PartSpec] = []

    // Digit 式界面状态
    @State private var modelPanel: StudioModelPanel = .none
    @State private var modelFilter: ModelSelectionFilter = .all
    @State private var bodyVisible = true
    @State private var selectedTreeID: String? = nil
    @State private var hiddenTreeIDs: Set<String> = []
    @State private var treeFeatOnly = false
    @State private var selectedNode: Int? = nil
    @State private var selectedSegIndex: Int? = nil
    @State private var selectedSegB: Int? = nil
    @State private var constraintPickMode = false
    @State private var continuousDraw = true
    @State private var autoConstrain = true
    @State private var gridAuto = true
    @State private var sketchFixed = false
    @State private var sectionOn = false
    @State private var sectionAxis: SectionAxis = .z
    @State private var sectionT = 0.45
    @State private var sectionReverse = false
    @State private var sectionHandles = true
    @State private var sectionLines = true
    @State private var measureOn = false
    @State private var measureTarget: MeasureTarget = .point
    @State private var pickedPoints: [ModelPickPoint] = []
    @State private var pickedEdges: [ModelPickEdge] = []
    @State private var pickedFaces: [ModelPickFace] = []
    @State private var pickedHole: ModelPickHole? = nil
    @State private var measurePickHint = "点/边/面：连点两个对象测距；体/复合：看属性"
    @State private var pickTolerance = 22.0
    @State private var pickToleranceByTarget: [String: Double] = [:]
    @State private var measureHost: UIHostingController<AnyView>? = nil
    @State private var showConstraintBadges = true
    @State private var calibratingPick = false
    @State private var calibrationSample: PickCalibration? = nil
    @State private var bodyHighlight = false
    @State private var drawingExportURL: URL?
    @State private var dxfExportURL: URL?
    @State private var material: StudioMaterial = .aluminum
    @State private var toastText: String = ""
    @State private var showToast = false
    @State private var arrayCount = 6
    @State private var arrayRadius = 36.0
    @State private var toolLibrary: [ToolRecord] = ToolLibraryStore.load()

    // 拍照图纸
    @State private var showPhotoMenu = false
    @State private var showDXFImporter = false
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var pendingScanImage: UIImage?
    @State private var showCrop = false
    @State private var scanning = false
    @State private var scanResult: DrawingScanResult?
    @State private var scanError: String?

    private enum DimTarget: Equatable {
        case none, rectL, rectW, rectR, circleD, slotL, slotW
        case nodeLen(Int), nodeAngle(Int), nodeR(Int), freeCircleD
    }

    private enum StudioModelPanel: Equatable {
        case none, tree, body, extrude, steps, section, measure, display, tools
    }

    private enum ModelSelectionFilter: String, CaseIterable, Identifiable {
        case all = "全部", feat = "特征", step = "台阶", sketch = "草图"
        var id: String { rawValue }
    }

    private enum SketchSidePanel: Hashable {
        case none, tools, params, dim, angle
    }

    private enum SectionAxis: String, CaseIterable, Identifiable {
        case x = "X", y = "Y", z = "Z"
        var id: String { rawValue }
    }

    private enum MeasureTarget: String, CaseIterable, Identifiable {
        case point = "点", edge = "边", face = "面", pointFace = "点-面", pointEdge = "点-边", edgeFace = "边-面", circle = "圆/弧", angle = "角", body = "体", compound = "复合"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .point: return "smallcircle.filled.circle"
            case .edge: return "line.diagonal"
            case .face: return "square.on.square"
            case .pointFace: return "square.and.line.vertical.and.square"
            case .pointEdge: return "ruler"
            case .edgeFace: return "square.dashed"
            case .circle: return "circle"
            case .angle: return "angle"
            case .body: return "cube"
            case .compound: return "circle.grid.2x2"
            }
        }
    }

    private struct ModelPickEdge: Identifiable, Equatable {
        var id: String
        var a: CGPoint
        var b: CGPoint
        var z: Double
        var z2: Double? = nil
        var distance: Double = 0
        /// 非 0 表示这段是圆弧，值为半径
        var arcR: Double = 0
        var zEnd: Double { z2 ?? z }
    }

    private struct ModelPickFace: Identifiable, Equatable {
        var id: String
        var name: String
        var z: Double
        var area: Double
        var center: CGPoint
        var nx: Double = 0
        var ny: Double = 0
        var nz: Double = 1
        /// 面的真实边界多边形（模型坐标）；空 = 只按无限平面算
        var boundary: [ModelPickPoint] = []
    }

    private struct ModelPickHole: Identifiable, Equatable {
        var id: String
        var name: String
        var x: Double
        var y: Double
        var z: Double
        var dia: Double
        var depth: Double
        var through: Bool
        var isPocket: Bool
        var w: Double = 0
        var h: Double = 0
        var bottomZ: Double = 0
        var onBottom: Bool = false
    }

    private struct ModelPickPoint: Equatable {
        var x: Double
        var y: Double
        var z: Double
    }
    private struct PickCalibration: Equatable {
        var point: CGPoint
        var nearestEdge: ModelPickEdge?
        var edgeDistances: [Double]
        var hole: ModelPickHole?
        var face: ModelPickFace?
    }


    private enum StudioMaterial: String, CaseIterable, Identifiable {
        case abs = "ABS", aluminum = "铝合金", steel = "钢", brass = "黄铜"
        var id: String { rawValue }
        var density: Double {
            switch self {
            case .abs: return 1.04
            case .aluminum: return 2.70
            case .steel: return 7.85
            case .brass: return 8.90
            }
        }
        var pricePerKg: Double {
            switch self {
            case .abs: return 20
            case .aluminum: return 28
            case .steel: return 12
            case .brass: return 65
            }
        }
    }

    private struct StudioTreeItem: Identifiable {
        var id: String
        var index: Int
        var title: String
        var icon: String
        var detail: String
        var canMove: Bool
        var canDelete: Bool
        var suppressed: Bool = false
    }

    init() {
        if let saved = ProjectStore.load() {
            _spec = State(initialValue: saved)
        } else {
            var s = PartSpec()
            // 第一次打开是空白网格，不预放圆/矩形
            s.template = .free
            s.nodes = []
            s.innerLoops = []
            s.feats = []
            _spec = State(initialValue: s)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            studioHeader
            studioStepBar

            if step == 0 {
                sketchPage
            } else if step == 1 {
                modelPage
            } else {
                Form {
                    if step == 2 { drawingPage } else { camPage }
                }
            }
        }
        .background(Color(red: 0.955, green: 0.965, blue: 0.985))
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .navigationDestination(isPresented: $showResult) {
            PartResultView(code: code)
        }
        .onChange(of: spec) { _ in
            opGenerated = false
            // 2D 刀路只在加工页需要；草图/建模页每改一个尺寸就全量重算会明显卡顿。
            if step == 3 { cam2DPaths = PartProg.toolpaths2D(spec) }
            ProjectStore.save(spec)
        }
        .onChange(of: step) { v in
            if v != 1 && stepShapeEditID != nil { cancelStepShapeEdit() }
            if v == 3 { cam2DPaths = PartProg.toolpaths2D(spec) }
        }
        .onAppear {
            cam2DPaths = PartProg.toolpaths2D(spec)
            pickTolerance = storedTolerance(for: measureTarget)
        }
        .onDisappear {
            dismissMeasureSheet()
        }
        .fileImporter(isPresented: $showDXFImporter,
                      allowedContentTypes: [
                        UTType(filenameExtension: "dxf") ?? .data,
                        UTType(filenameExtension: "svg") ?? .data,
                        UTType(filenameExtension: "plt") ?? .data,
                        UTType(filenameExtension: "hpgl") ?? .data,
                        .data
                      ],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { importVector(url) }
            case .failure:
                showToastView("轮廓文件选择失败")
            }
        }
        .sheet(isPresented: $showOpCode) {
            NavigationStack {
                ScrollView {
                    TextEditor(text: $opCodeText)
                        .font(.system(size: 11, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .frame(maxWidth: .infinity, minHeight: 420, alignment: .topLeading)
                        .padding(8)
                    Text("当前查看的程序可直接改字、复制或分享；改动只影响这次导出的文本，不会反写参数。")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }
                .navigationTitle(opCodeTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        ShareLink(item: opCodeText) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        Button("关闭") { showOpCode = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showRotate) {
            TransformSheet(spec: $spec, rotate: true, onUndo: { pushUndo() })
        }
        .sheet(isPresented: $showScale) {
            TransformSheet(spec: $spec, rotate: false, onUndo: { pushUndo() })
        }
        .sheet(isPresented: $showFeatCommand) {
            if let draft = featDraft {
                FeatCommandSheet(
                    feat: Binding(get: { featDraft ?? draft }, set: { featDraft = $0 }),
                    hostZ: PartProg.hostZ(spec, draft),
                    isNew: featEditID == nil,
                    onApply: { applyFeatDraft(close: false) },
                    onConfirm: { applyFeatDraft(close: true) },
                    onCancel: { cancelFeatCommand() }
                )
            }
        }
        .sheet(isPresented: $showOpSheet) {
            OpParamsSheet(spec: $spec, op: opSheetName)
        }
        .confirmationDialog("拍照图纸", isPresented: $showPhotoMenu, titleVisibility: .visible) {
            Button("拍照") { openCamera() }
            Button("从相册选") { showPhotoPicker = true }
            Button("取消", role: .cancel) { }
        } message: {
            Text("拍正视图/俯视图，图上带尺寸或比例尺最准；识别后请先核对尺寸")
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker { image in
                showCamera = false
                pendingScanImage = image
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    showCrop = true
                }
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { newItem in
            guard let item = newItem else { return }
            Task { @MainActor in
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    scanError = "相册图片读取失败，换一张试试"
                    return
                }
                photoItem = nil
                pendingScanImage = image
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    showCrop = true
                }
            }
        }
        .sheet(isPresented: $showCrop) {
            if let image = pendingScanImage {
                DrawingCropView(
                    image: image,
                    onCrop: { cropped in
                        showCrop = false
                        pendingScanImage = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            startScan(cropped)
                        }
                    },
                    onCancel: {
                        showCrop = false
                        pendingScanImage = nil
                    })
            }
        }
        .sheet(item: $scanResult) { result in
            DrawingScanPreviewView(
                result: result,
                onUse: { updated in adoptScan(updated) },
                onRetry: { showPhotoMenu = true })
        }
        .alert("识别失败", isPresented: Binding(
            get: { scanError != nil },
            set: { if !$0 { scanError = nil } }
        )) {
            Button("知道了") { scanError = nil }
        } message: {
            Text(scanError ?? "")
        }
        .alert("改尺寸", isPresented: $showDimEdit) {
            TextField("数值", text: $dimEditText).keyboardType(.decimalPad)
            Button("确定") { applyDimEdit() }
            Button("取消", role: .cancel) { }
        } message: {
            Text(dimEditTitle + "：输入新的毫米值 / 角度值")
        }
        .overlay(alignment: .bottom) {
            if showToast {
                Text(toastText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Color.black.opacity(0.78)))
                    .padding(.bottom, 58)
                    .transition(.opacity)
            }
        }
        .overlay {
            if scanning {
                ZStack {
                    Color.black.opacity(0.25).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("正在识别图纸：轮廓 / 尺寸 / 圆孔")
                            .font(.system(size: 14, weight: .semibold))
                        Text("请稍等，识别完先核对尺寸再采用")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(22)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    // MARK: - 顶部工具栏（Digit 式两级）

    private var studioHeader: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.white.opacity(0.92)))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text("建模编程")
                    .font(.system(size: 16, weight: .bold))
                Text("UG 式 · 参数化 2.5D")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button { undoSketch() } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.white.opacity(0.92)))
            }
            .buttonStyle(.plain)
            .disabled(undoStack.isEmpty)
            .opacity(undoStack.isEmpty ? 0.35 : 1)

            Button { redoSketch() } label: {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.white.opacity(0.92)))
            }
            .buttonStyle(.plain)
            .disabled(redoStack.isEmpty)
            .opacity(redoStack.isEmpty ? 0.35 : 1)

            Menu {
                Button { showPhotoMenu = true } label: {
                    Label("拍照图纸", systemImage: "camera.viewfinder")
                }
                Button { showDXFImporter = true } label: {
                    Label("导入 DXF / SVG / PLT", systemImage: "square.and.arrow.down")
                }
                Button("保存工程") {
                    ProjectStore.save(spec)
                    showToastView("工程已保存，下次打开自动恢复")
                }
                Button("适合窗口") { setView(0.78, 0.62) }
                Button("完成草图") { step = 1 }
                Button("清空草图", role: .destructive) { clearSketch() }
                Button("回到工具箱") { dismiss() }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.white.opacity(0.92)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    private var studioStepBar: some View {
        HStack(spacing: 4) {
            ForEach(0..<4, id: \.self) { i in
                Button { step = i } label: {
                    HStack(spacing: 5) {
                        Text("\(i + 1)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(step == i ? .white : studioBlue)
                            .frame(width: 17, height: 17)
                            .background(Circle().fill(step == i ? studioBlue : studioBlue.opacity(0.10)))
                        Text(stepTitle(i))
                            .font(.system(size: 12, weight: step == i ? .bold : .regular))
                            .foregroundStyle(step == i ? studioBlue : .primary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 9)
                            .fill(step == i ? Color.white : Color.clear)
                            .shadow(color: step == i ? .black.opacity(0.08) : .clear, radius: 4, y: 2)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.55)))
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    private func stepTitle(_ i: Int) -> String {
        ["草图", "建模", "出图", "加工"][min(max(i, 0), 3)]
    }

    private var studioBlue: Color { Color(red: 0.15, green: 0.35, blue: 0.86) }
    private var bodyTint: Color { Color(red: 0.28, green: 0.33, blue: 0.39) }

    /// 实体基色（RGB 0...1）：按当前材料给金属/塑料底色
    private var metalBaseRGB: (Double, Double, Double) {
        switch material {
        case .aluminum: return (0.70, 0.75, 0.80)
        case .steel:    return (0.44, 0.49, 0.55)
        case .brass:    return (0.74, 0.56, 0.24)
        case .abs:      return (0.80, 0.79, 0.74)
        }
    }

    /// 金属高光强度：钢最亮、铝次之、黄铜暖高光、ABS 只留很弱的塑料反光
    private var metalSpecularStrength: Double {
        switch material {
        case .aluminum: return 0.88
        case .steel:    return 0.94
        case .brass:    return 0.80
        case .abs:      return 0.22
        }
    }


    // MARK: - 1 草图

    private var sketchPage: some View {
        ZStack(alignment: .topLeading) {
            GeometryReader { geo in
                Canvas { context, size in
                    drawSketch(context: context, size: size)
                }
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in moveSketchNode(value.location, size: geo.size) }
                        .onEnded { _ in dragNode = nil }
                )
                .simultaneousGesture(SpatialTapGesture().onEnded { v in
                    sketchSidePanel = .none
                    if isTemplateTool(sketchTool) {
                        placeTemplate(sketchTool, at: v.location, size: geo.size)
                    } else if isDrawTool(sketchTool) || drawInner {
                        addPointAt(v.location, size: geo.size)
                    } else {
                        selectSketchNode(at: v.location, size: geo.size)
                    }
                })
                .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { v in
                    pickDim(at: v.location, size: geo.size)
                })
                .background(Color.white)
            }

            HStack(alignment: .top, spacing: 0) {
                sketchLeftRail
                Spacer(minLength: 0)
                if selectedSegIndex != nil || constraintPickMode || sketchSidePanel == .dim || sketchSidePanel == .angle {
                    sketchConstraintRail
                } else {
                    sketchConstraintHintPill
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            VStack(spacing: 6) {
                Spacer()
                if editPreviewSpec != nil {
                    sketchEditPreviewBar
                        .padding(.horizontal, 8)
                }
                sketchBottomBar
            }

            if sketchSidePanel != .none {
                HStack(alignment: .top, spacing: 0) {
                    sketchSidePanelView
                    Spacer(minLength: 0)
                }
                .padding(.leading, 76)
                .padding(.top, 8)
            }
        }
    }

    private var sketchLeftRail: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 3) {
                railButton("拍图", "camera.viewfinder", active: false) { showPhotoMenu = true }
                railButton("选择", "cursorarrow", active: sketchTool.isEmpty && !drawInner) {
                    sketchTool = ""
                    refPoints.removeAll()
                    drawInner = false
                }
                railButton("直线", "line.diagonal", active: sketchTool == "直线") { selectSketchTool("直线") }
                railButton("矩形", "rectangle", active: sketchTool == "矩形") { selectSketchTool("矩形") }
                railButton("圆", "circle", active: sketchTool == "圆") { selectSketchTool("圆") }
                railButton("圆弧", "arrow.turn.up.left", active: sketchTool == "圆弧") { selectSketchTool("圆弧") }

                Divider().padding(.vertical, 2)
                railButton("更多", "square.grid.2x2", active: sketchSidePanel == .tools) {
                    sketchSidePanel = sketchSidePanel == .tools ? .none : .tools
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
        }
        .frame(width: 62)
        .frame(maxHeight: 430)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 132))
        .overlay(RoundedRectangle(cornerRadius: 132).stroke(Color.white.opacity(0.85), lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }

    private var sketchConstraintHintPill: some View {
        Button {
            constraintPickMode = true
            showToastView("先点一条线段；右侧约束栏会出现")
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "pin")
                    .font(.system(size: 16, weight: .semibold))
                Text("约束")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(studioBlue)
            .frame(width: 46, height: 70)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.85), lineWidth: 1))
            .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
    }

    private var sketchConstraintRail: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 3) {
                railButton("选段", "cursorarrow.rays", active: constraintPickMode) {
                    constraintPickMode.toggle()
                    if constraintPickMode {
                        sketchTool = ""
                        refPoints.removeAll()
                        showToastView("选段模式：点第一段 A，再点第二段 B；约束按钮按选段计算")
                    } else {
                        selectedSegIndex = nil
                        selectedSegB = nil
                        showToastView("已退出选段模式")
                    }
                }
                railButton("尺寸", "ruler", active: sketchSidePanel == .dim) {
                    sketchSidePanel = sketchSidePanel == .dim ? .none : .dim
                }
                railButton("角度", "angle", active: sketchSidePanel == .angle) {
                    sketchSidePanel = sketchSidePanel == .angle ? .none : .angle
                }
                railButton("水平", "line.3.horizontal", active: false) { addSketchConstraint(.horizontal) }
                railButton("竖直", "line.3.horizontal.decrease", active: false) { addSketchConstraint(.vertical) }
                railButton("固定", "pin", active: sketchFixed) { sketchFixed.toggle() }
                railButton("重合", "circle.circle", active: false) { addSketchConstraint(.coincident) }
                railButton("中点", "smallcircle.filled.circle", active: false) { addSketchConstraint(.midpoint) }
                railButton("平行", "equal", active: false) { addSketchConstraint(.parallel) }
                railButton("垂直", "plus", active: false) { addSketchConstraint(.perpendicular) }
                railButton("相切", "circle.dashed", active: false) { addSketchConstraint(.tangent) }
                railButton("同心", "circle.and.line.horizontal", active: false) { addSketchConstraint(.concentric) }
                railButton("等长", "equal.circle", active: false) { addSketchConstraint(.equal) }
                railButton("取消固定", "xmark.circle", active: false) {
                    sketchFixed = false
                    showToastView("已取消固定状态")
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
        }
        .frame(width: 62)
        .frame(maxHeight: 560)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 132))
        .overlay(RoundedRectangle(cornerRadius: 132).stroke(Color.white.opacity(0.85), lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }

    private var sketchEditPreviewBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 1) {
                Text("预览：\(pendingEditTool ?? "编辑")")
                    .font(.system(size: 12, weight: .bold))
                Text("\(editPreviewInfo) · 蓝虚线是应用后的轮廓")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("取消") { cancelEditPreview() }
                .font(.system(size: 11, weight: .semibold))
                .buttonStyle(.bordered)
            Button("应用") { confirmEditPreview() }
                .font(.system(size: 11, weight: .bold))
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.8), lineWidth: 1))
    }

    private var editPreviewInfo: String {
        switch pendingEditTool ?? "" {
        case "圆角": return "R \(ncf(filletR))"
        case "倒角": return "C \(ncf(chamferC))"
        case "偏置": return "距离 \(ncf(offsetD))"
        case "移动": return "DX \(ncf(moveDX))  DY \(ncf(moveDY))"
        case "延伸": return "延伸 10 mm"
        case "水平约束": return "所有点同一 Y"
        case "修剪": return "去掉末尾点/段"
        case "围栏修剪", "区域修剪": return "按框选区域保留"
        case "镜像": return "左右镜像"
        case "打断": return "末段中点打断"
        default: return "确认后替换当前草图"
        }
    }

    private var selectionHint: String {
        if let a = selectedSegIndex {
            let b = selectedSegB.map { "；B 段 \($0 + 1)" } ?? ""
            return "已选 A 段 \(a + 1)\(b) · 编辑/约束只作用于选段"
        }
        return isTemplateTool(sketchTool) ? "点画布放置 · 连续点继续放"
             : (isDrawTool(sketchTool) || drawInner ? "连续落点 · 点画布添加" : "点线段选段 · 双击改尺寸")
    }

    private var sketchBottomBar: some View {
        HStack(spacing: 8) {
            Menu {
                Button("自动（5 mm）") { gridAuto = true; gridStep = 5 }
                Button("5 mm") { gridAuto = false; gridStep = 5 }
                Button("10 mm") { gridAuto = false; gridStep = 10 }
                Button("20 mm") { gridAuto = false; gridStep = 20 }
                Button("50 mm") { gridAuto = false; gridStep = 50 }
            } label: {
                Label("网格 \(Int(gridStep)) mm · \(gridAuto ? "自动" : "手动")", systemImage: "grid")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Capsule().fill(Color.white.opacity(0.92)))
            }
            .buttonStyle(.plain)

            Button { continuousDraw.toggle() } label: {
                Label(continuousDraw ? "连续绘制已开" : "连续绘制",
                      systemImage: continuousDraw ? "infinity.circle.fill" : "infinity.circle")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Capsule().fill(continuousDraw ? studioBlue.opacity(0.12) : Color.white.opacity(0.92)))
                    .foregroundStyle(continuousDraw ? studioBlue : .secondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Text(selectionHint)
                .font(.system(size: 10))
                .foregroundColor(selectedSegIndex == nil ? Color.secondary : studioBlue)

            Button { step = 1 } label: {
                Label("完成草图", systemImage: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Capsule().fill(studioBlue))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.72))
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private var sketchSidePanelView: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(sketchPanelTitle).font(.system(size: 16, weight: .bold))
                    Text(sketchPanelSubtitle).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { sketchSidePanel = .none } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color(.secondarySystemBackground)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 13)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if sketchSidePanel == .tools || sketchSidePanel == .params {
                Picker("", selection: $sketchSidePanel) {
                    Text("工具").tag(SketchSidePanel.tools)
                    Text("参数").tag(SketchSidePanel.params)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 13)
                .padding(.bottom, 8)
            }

            Group {
                switch sketchSidePanel {
                case .tools:
                    AnyView(sketchToolGridPanel)
                case .params:
                    AnyView(
                        Form { sketchControls }
                            .listStyle(.plain)
                            .scrollContentBackground(.hidden)
                            .background(Color.white)
                    )
                case .dim:
                    AnyView(sketchDimPanel)
                case .angle:
                    AnyView(sketchAnglePanel)
                case .none:
                    AnyView(EmptyView())
                }
            }
        }
        .frame(width: 268)
        .frame(maxHeight: 540)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.97)))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white, lineWidth: 1))
        .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var sketchPanelTitle: String {
        switch sketchSidePanel {
        case .tools: return "草图工具"
        case .params: return "草图参数"
        case .dim: return "尺寸"
        case .angle: return "角度"
        case .none: return ""
        }
    }

    private var sketchPanelSubtitle: String {
        switch sketchSidePanel {
        case .tools: return "\(sketchToolCount) 项 · 点画布连续绘制"
        case .params: return "外形 / 内轮廓 / 阵列参数"
        case .dim: return "外形与分段长度 · 点一项改值"
        case .angle: return "顶点夹角 · 点一项改值"
        case .none: return ""
        }
    }

    private var sketchToolGridPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("绘制").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach(drawToolNames, id: \.self) { name in
                        sketchToolChip(name)
                    }
                }

                Text("编辑").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach(editToolNames, id: \.self) { name in
                        sketchToolChip(name)
                    }
                }

                Divider()

                Text("内轮廓").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Button { addInner(.circle) } label: { Label("内圆", systemImage: "circle") }
                    Button { addInner(.rect) } label: { Label("内方", systemImage: "rectangle") }
                    Button {
                        toggleInnerDraw()
                        sketchSidePanel = .none
                    } label: {
                        Label(drawInner ? "完成手画" : "手画", systemImage: "pencil.tip")
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .buttonStyle(.bordered)
                if drawInner {
                    Button("完成这个内轮廓") { finishInner(); sketchSidePanel = .none }
                        .font(.system(size: 12, weight: .bold))
                }

                Button { sketchSidePanel = .params } label: {
                    Label("尺寸 / 内轮廓 / 阵列参数", systemImage: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 13)
            .padding(.bottom, 14)
        }
    }

    private func sketchToolChip(_ name: String) -> some View {
        Button {
            selectSketchTool(name)
            sketchSidePanel = .none
        } label: {
            Text(name)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(sketchTool == name ? studioBlue.opacity(0.14) : Color(.secondarySystemBackground)))
                .foregroundStyle(sketchTool == name ? studioBlue : .primary)
        }
        .buttonStyle(.plain)
    }

    private var sketchDimPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                switch spec.template {
                case .rect:
                    dimRow("长 L", spec.rectL, .rectL)
                    dimRow("宽 W", spec.rectW, .rectW)
                    dimRow("四角 R", spec.rectR, .rectR)
                case .circle:
                    dimRow("直径 Ø", spec.circleD, .circleD)
                case .slot:
                    dimRow("槽长 L", spec.slotL, .slotL)
                    dimRow("槽宽 W", spec.slotW, .slotW)
                case .free:
                    if let c = sketchFreeCircle {
                        dimRow("直径 Ø", c.r * 2, .freeCircleD)
                        Text("识别为整圆：只按直径标注，不再拆成多段。")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    } else {
                        Text("手绘轮廓：外形尺寸按下面每段长度控制。")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }

                if spec.nodes.count > 1, sketchFreeCircle == nil {
                    Divider().padding(.vertical, 2)
                    Text("分段长度").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    ForEach(0..<spec.nodes.count, id: \.self) { i in
                        let a = spec.nodes[i]
                        let c = spec.nodes[(i + 1) % spec.nodes.count]
                        dimRow("第 \(i + 1) 段", hypot(c.x - a.x, c.y - a.y), .nodeLen(i))
                    }
                }
                Text("也可以直接在画布上双击尺寸改值。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 13)
            .padding(.bottom, 14)
        }
    }

    private var sketchAnglePanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                switch spec.template {
                case .rect:
                    Text("矩形：四角由外形约束保持 90°。")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                case .circle:
                    Text("圆 / 椭圆：角度由圆心、半径和起始角决定。")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                case .slot:
                    Text("槽：两端圆弧按槽宽自动保持 R=W/2。")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                case .free:
                    if sketchFreeCircle != nil {
                        Text("识别为整圆：角度由圆心和半径决定，不需要逐点夹角。")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }

                if spec.nodes.count > 2, sketchFreeCircle == nil {
                    Text("顶点夹角").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    ForEach(0..<spec.nodes.count, id: \.self) { i in
                        dimRow("点 \(i + 1) 夹角", vertexAngle(spec.nodes, i), .nodeAngle(i), unit: "°")
                    }
                } else if spec.template == .free {
                    Text("至少画 3 个点后，这里会列出每个顶点的夹角。")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }

                if spec.nodes.count > 1 && spec.template == .free {
                    Divider().padding(.vertical, 2)
                    Text("圆弧半径").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    ForEach(0..<spec.nodes.count, id: \.self) { i in
                        if spec.nodes[i].kind != .line {
                            dimRow("点 \(i + 1) 半径", spec.nodes[i].r, .nodeR(i))
                        }
                    }
                }
                Text("点一项即可改；画布上双击顶点也能改角度。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 13)
            .padding(.bottom, 14)
        }
    }

    private func dimRow(_ title: String, _ value: Double, _ target: DimTarget, unit: String = "mm") -> some View {
        Button {
            openDimEdit(target, title, value)
        } label: {
            HStack {
                Text(title).font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(ncf(value)) \(unit)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(studioBlue)
                Image(systemName: "pencil")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground).opacity(0.75)))
        }
        .buttonStyle(.plain)
        .disabled(target == .none)
    }

    private func openDimEdit(_ target: DimTarget, _ title: String, _ value: Double) {
        guard target != .none else { return }
        dimTarget = target
        dimEditTitle = "改 " + title
        dimEditText = String(format: "%.2f", value)
        showDimEdit = true
    }

    private func railButton(_ title: String, _ icon: String, active: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 52, height: 43)
            .foregroundStyle(active ? studioBlue : Color(red: 0.27, green: 0.30, blue: 0.36))
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(active ? studioBlue.opacity(0.13) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func openCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            scanError = "这台设备没有可用相机，请从相册选图纸"
            return
        }
        showPhotoMenu = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            showCamera = true
        }
    }

    private func startScan(_ image: UIImage) {
        scanError = nil
        scanning = true
        Task { @MainActor in
            do {
                let result = try await DrawingScanner.scan(image)
                scanning = false
                scanResult = result
            } catch {
                scanning = false
                scanError = error.localizedDescription
            }
        }
    }

    private func adoptScan(_ result: DrawingScanResult) {
        pushUndo()
        spec = result.spec
        step = 0
        selectedNode = nil
        selectedTreeID = nil
        modelPanel = .none
        sketchSidePanel = .dim
        sketchTool = ""
        refPoints.removeAll()
        drawInner = false
        scanResult = nil
        showToastView("已采用识别结果：\(result.summary)")
    }

    private func showToastView(_ text: String) {
        toastText = text
        withAnimation(.easeOut(duration: 0.15)) { showToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeIn(duration: 0.2)) { showToast = false }
        }
    }

    private var activeTemplateTool: String? {
        if isTemplateTool(sketchTool) { return sketchTool }
        if sketchTool.isEmpty, isTemplateTool(lastShapeTool),
           spec.template == .free, !spec.nodes.isEmpty {
            return lastShapeTool
        }
        return nil
    }

    private func scheduleTemplateRebuild() {
        guard activeTemplateTool != nil, spec.nodes.count >= 3 else { return }
        templateRebuildToken += 1
        let token = templateRebuildToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            guard token == templateRebuildToken else { return }
            rebuildLastTemplate()
        }
    }

    private func rebuildLastTemplate() {
        templateRebuildToken += 1
        guard let name = activeTemplateTool ?? (isTemplateTool(lastShapeTool) ? lastShapeTool : nil),
              spec.nodes.count >= 3 else {
            showToastView("当前没有可更新的模板轮廓")
            return
        }
        let xs = spec.nodes.map(\.x), ys = spec.nodes.map(\.y)
        guard let mnx = xs.min(), let mxx = xs.max(),
              let mny = ys.min(), let mxy = ys.max() else { return }
        let cx = (mnx + mxx) / 2, cy = (mny + mxy) / 2
        let local = templateLocalNodes(name,
                                       L: max(spec.rectL, 20),
                                       W: max(spec.rectW, 12),
                                       D: max(spec.circleD, 20),
                                       R: spec.rectR)
        guard local.count >= 3 else { return }
        pushUndo()
        spec.constraints.removeAll()
        spec.nodes = local.map { ContourNode(x: $0.x + cx, y: $0.y + cy) }
        spec.template = .free
        showToastView("\(name) 已按参数更新，约束已清空")
    }

    @ViewBuilder
    private var sketchControls: some View {
        Section("当前工具参数") {
            if let t = activeTemplateTool {
                Text("\(t) · 输入停止 0.45 秒自动重建，也可点“更新轮廓”")
                    .font(.caption).foregroundStyle(.secondary)
                switch t {
                case "矩形", "中心矩形":
                    autoNumRow("长 L (mm)", $spec.rectL)
                    autoNumRow("宽 W (mm)", $spec.rectW)
                case "圆角矩形":
                    autoNumRow("长 L (mm)", $spec.rectL)
                    autoNumRow("宽 W (mm)", $spec.rectW)
                    autoNumRow("圆角 R (mm)", $spec.rectR)
                case "圆", "多边形", "五角星", "样条曲线":
                    autoNumRow("直径 D (mm)", $spec.circleD)
                case "椭圆", "槽", "平行四边形":
                    autoNumRow("长 L (mm)", $spec.rectL)
                    autoNumRow("宽 W (mm)", $spec.rectW)
                default:
                    EmptyView()
                }
                Button("按这组尺寸更新轮廓") { rebuildLastTemplate() }
                    .font(.system(size: 13, weight: .semibold))
            } else if ["直线", "多段线", "三点圆", "圆弧", "点"].contains(sketchTool) {
                Text("\(sketchTool)：自由绘制，在画布上点起点/下一点；单段长度和角度在“尺寸/角度”面板里改。")
                    .font(.caption).foregroundStyle(.secondary)
            } else if isEditTool(sketchTool) {
                Text("编辑工具：选中后先在画布蓝虚线预览，再点底部“应用”。参数在下方“编辑参数”。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("选一个模板工具（矩形/圆/槽…）后，这里显示该工具的实际尺寸参数。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }

        Section("草图约束") {
            let issues = constraintIssues
            HStack {
                Text("已加 \(spec.constraints.count) 条").font(.system(size: 13, weight: .semibold))
                Spacer()
                if !issues.isEmpty {
                    Text("过约束/冲突").font(.system(size: 11, weight: .bold)).foregroundStyle(.red)
                }
                if !spec.constraints.isEmpty {
                    Button("清空") { clearSketchConstraints() }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.red)
                }
            }
            if spec.constraints.isEmpty {
                Text("右侧约束按钮添加后，拖动节点会按约束自动求解；改模板尺寸会清空约束。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Toggle("自动约束（水平 / 竖直 / 共点）", isOn: $autoConstrain)
                .font(.system(size: 12))
            if spec.template == .free {
                Button {
                    autoConstrainSketch()
                } label: {
                    Label("扫描当前轮廓，自动加约束", systemImage: "wand.and.stars")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            Toggle("显示约束图标", isOn: $showConstraintBadges)
                .font(.system(size: 12))
            ForEach(issues, id: \.self) { issue in
                Text(issue)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(spec.constraints) { c in
                HStack {
                    Text(c.symbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 18)
                        .background(RoundedRectangle(cornerRadius: 5).fill(studioBlue))
                    Text(c.label).font(.system(size: 12))
                    Spacer()
                    Button {
                        pushUndo()
                        spec.constraints.removeAll { $0.id == c.id }
                    } label: {
                        Image(systemName: "trash").foregroundStyle(.red)
                    }
                }
            }
            if !spec.constraints.isEmpty {
                Button("重新求解") { solveSketchConstraints() }
                    .font(.system(size: 12, weight: .semibold))
            }
        }

        Section("加内轮廓") {
            HStack {
                Button { addInner(.circle) } label: { Label("内圆", systemImage: "circle") }
                Spacer()
                Button { addInner(.rect) } label: { Label("内方", systemImage: "rectangle") }
                Spacer()
                Button {
                    toggleInnerDraw()
                } label: {
                    Label(drawInner ? "完成手画" : "手画内轮廓", systemImage: "pencil.tip")
                }
            }
            .font(.system(size: 12, weight: .semibold))
            if drawInner {
                Button("完成这个内轮廓") { finishInner() }
                    .font(.system(size: 13, weight: .bold))
                Text("在画布上连续点，画完点“完成这个内轮廓”。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if spec.innerLoops.isEmpty {
                Text("还没有内轮廓。内圆/内方/手画内轮廓都会叠在外形里，建模时自动挖切。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }

        Section("外形尺寸（拉伸）") {
            switch spec.template {
            case .rect:
                numRow("长 L (mm)", $spec.rectL)
                numRow("宽 W (mm)", $spec.rectW)
                numRow("四角 R（0=直角）", $spec.rectR)
            case .circle:
                numRow("直径 D (mm)", $spec.circleD)
            case .slot:
                numRow("槽总长 L（含圆弧）", $spec.slotL)
                numRow("槽宽 W", $spec.slotW)
            case .free:
                EmptyView()
            }
            numRow("零件厚度 H（拉伸高度）", $spec.height)
            numRow("顶面余量 (mm)", $spec.topStock)
        }

        Section("草图视图") {
            HStack {
                Text("网格大小").font(.system(size: 13))
                Spacer()
                Picker("", selection: $gridStep) {
                    Text("5 mm").tag(5.0)
                    Text("10 mm").tag(10.0)
                    Text("20 mm").tag(20.0)
                    Text("50 mm").tag(50.0)
                }
                .labelsHidden()
            }
            Toggle("对象捕捉（吸附节点）", isOn: $snapVertex)
            Toggle("网格吸附", isOn: $snapGrid)
        }

        Section {
            DisclosureGroup("编辑参数（圆角 / 倒角 / 框选 / 移动）") {
                Text("修剪/延伸/打断按当前轮廓的末段处理；圆角/倒角/偏置对整条外轮廓生效。")
                    .font(.caption).foregroundStyle(.secondary)
                numRow("圆角 R (mm)", $filletR)
                numRow("倒角 C (mm)", $chamferC)
                HStack(spacing: 6) {
                    miniNum("X0", $trimX0)
                    miniNum("Y0", $trimY0)
                    miniNum("X1", $trimX1)
                    miniNum("Y1", $trimY1)
                }
                Button("按这个方框围栏修剪") { pushUndo(); regionTrim() }
                    .font(.system(size: 13, weight: .semibold))
                HStack(spacing: 6) {
                    miniNum("dx", $moveDX)
                    miniNum("dy", $moveDY)
                    Button("移动轮廓") { pushUndo(); moveOuter() }
                        .font(.system(size: 13, weight: .semibold))
                }
                numRow("偏置距离 (mm)", $offsetD)
                HStack(spacing: 6) {
                    Stepper("行 \(arrayRows)", value: $arrayRows, in: 1...6)
                    Stepper("列 \(arrayCols)", value: $arrayCols, in: 1...6)
                }
                HStack(spacing: 6) {
                    miniNum("阵列 dx", $arrayDX)
                    miniNum("阵列 dy", $arrayDY)
                }
                Button("阵列内轮廓") { arrayInner() }
                    .font(.system(size: 13, weight: .semibold))
                Button("矩形阵列外轮廓为增料层") { arrayOuterAsBosses(circular: false) }
                    .font(.system(size: 13, weight: .semibold))
                Button("圆形阵列外轮廓为增料层") { arrayOuterAsBosses(circular: true) }
                    .font(.system(size: 13, weight: .semibold))
                HStack(spacing: 6) {
                    Stepper("圆阵 \(arrayCount) 个", value: $arrayCount, in: 2...12)
                    miniNum("R", $arrayRadius)
                }
                Button("圆形阵列内轮廓") { circularArrayInner() }
                    .font(.system(size: 13, weight: .semibold))
            }
        }

        Section("内轮廓列表") {
            if spec.innerLoops.isEmpty {
                Text("还没有内轮廓。点上面的「内圆」或「内方」，就会在外形里加一个可挖的孔/型腔。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach($spec.innerLoops) { $l in
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        TextField("名称", text: $l.name)
                            .font(.system(size: 13, weight: .semibold))
                            .textFieldStyle(.roundedBorder)
                        Picker("", selection: $l.template) {
                            ForEach(ContourTemplate.allCases) { t in Text(t.rawValue).tag(t) }
                        }
                        .labelsHidden()
                        Button {
                            spec.innerLoops.removeAll { $0.id == l.id }
                        } label: {
                            Image(systemName: "trash").foregroundStyle(.red)
                        }
                    }
                    HStack(spacing: 6) {
                        miniNum("X", $l.cx)
                        miniNum("Y", $l.cy)
                        switch l.template {
                        case .circle:
                            miniNum("Ø", $l.circleD)
                        case .rect:
                            miniNum("长", $l.rectL)
                            miniNum("宽", $l.rectW)
                            miniNum("R", $l.rectR)
                        case .slot:
                            miniNum("长", $l.slotL)
                            miniNum("宽", $l.slotW)
                        case .free:
                            Text("自由轮廓在下方的节点里编辑").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Toggle("挖穿（通孔/通腔）", isOn: $l.through)
                    if !l.through {
                        HStack {
                            Text("挖深").font(.system(size: 12))
                            TextField("0", value: $l.depth, format: .number)
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                                .frame(width: 70)
                            Text("mm").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                }
            }
        }

        if spec.template == .free {
            Section("自由轮廓节点（末点自动连回起点）") {
                ForEach(spec.nodes.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("点 \(i + 1)").font(.system(size: 13, weight: .semibold))
                            Spacer()
                            if spec.nodes.count > 1 {
                                Button {
                                    pushUndo()
                                    spec.constraints.removeAll()
                                    spec.nodes.remove(at: i)
                                } label: {
                                    Image(systemName: "minus.circle").foregroundStyle(.red)
                                }
                            }
                        }
                        HStack(spacing: 6) {
                            miniNum("X", Binding(get: { spec.nodes[i].x }, set: { spec.nodes[i].x = $0 }))
                            miniNum("Y", Binding(get: { spec.nodes[i].y }, set: { spec.nodes[i].y = $0 }))
                            Picker("", selection: Binding(get: { spec.nodes[i].kind }, set: { spec.nodes[i].kind = $0 })) {
                                ForEach(ContourKind.allCases) { k in
                                    Text(k.rawValue).tag(k)
                                }
                            }
                            .labelsHidden()
                            if spec.nodes[i].kind != .line {
                                miniNum("R", Binding(get: { spec.nodes[i].r }, set: { spec.nodes[i].r = $0 }))
                            }
                        }
                    }
                }
                Button {
                    addNode()
                } label: {
                    Label("加节点", systemImage: "plus.circle")
                }
            }
        }
    }

    @State private var dragNode: Int? = nil
    @State private var sketchTool: String = ""
    @State private var lastShapeTool: String = "矩形"
    @State private var templateRebuildToken = 0
    @State private var refPoints: [CGPoint] = []
    @State private var pendingEditTool: String? = nil
    @State private var editPreviewSpec: PartSpec? = nil
    @State private var filletR = 5.0
    @State private var chamferC = 3.0
    @State private var trimX0 = -20.0
    @State private var trimY0 = -20.0
    @State private var trimX1 = 20.0
    @State private var trimY1 = 20.0
    @State private var moveDX = 10.0
    @State private var moveDY = 0.0
    @State private var offsetD = 5.0
    @State private var arrayRows = 2
    @State private var arrayCols = 1
    @State private var arrayDX = 50.0
    @State private var arrayDY = 0.0

    private var drawToolNames: [String] {
        ["直线", "多段线", "矩形", "中心矩形", "圆角矩形", "圆", "三点圆", "圆弧",
         "椭圆", "多边形", "五角星", "样条曲线", "槽", "平行四边形", "点"]
    }

    private var editToolNames: [String] {
        ["修剪", "围栏修剪", "区域修剪", "圆角", "倒角", "偏置", "镜像",
         "阵列", "水平约束", "移动", "旋转", "缩放", "延伸", "打断"]
    }

    private var sketchToolCount: Int { drawToolNames.count + editToolNames.count }

    private func toolRow(_ name: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(name)
                    .font(.system(size: 14, weight: active ? .bold : .regular))
                    .foregroundStyle(active ? Color.orange : Color.primary)
                Spacer()
                if active {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.orange)
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func selectSketchTool(_ name: String) {
        if isDrawTool(name) || isTemplateTool(name) { constraintPickMode = false }
        if !isEditTool(name) && name != "多段线" {
            selectedSegIndex = nil
            selectedSegB = nil
        }
        switch name {
        case "三点圆":
            sketchTool = "三点圆"; refPoints.removeAll(); return
        case "圆弧":
            sketchTool = "圆弧"; refPoints.removeAll(); return
        case "点":
            sketchTool = "点"; refPoints.removeAll(); return
        case "旋转":
            showRotate = true; return
        case "缩放":
            showScale = true; return
        case "阵列":
            arrayInner(); return
        default:
            break
        }
        if isTemplateTool(name) {
            selectTemplateTool(name)
            return
        }
        if isEditTool(name) {
            beginEditPreview(name)
            return
        }
        pushUndo()
        sketchTool = ""
        switch name {
        case "直线":
            makeLine()
        case "多段线":
            makePolyline()
        case "矩形", "中心矩形":
            spec.template = .rect; spec.nodes = []
        case "圆角矩形":
            spec.template = .rect; spec.nodes = []; spec.rectR = max(spec.rectR, 8)
        case "圆":
            spec.template = .circle; spec.nodes = []
        case "椭圆":
            makeEllipse()
        case "多边形":
            makePolygon(6)
        case "五角星":
            makeStar()
        case "样条曲线":
            makeSpline()
        case "槽":
            spec.template = .slot; spec.nodes = []
        case "平行四边形":
            makeParallelogram()
        case "修剪":
            trimLast()
        case "围栏修剪", "区域修剪":
            regionTrim()
        case "圆角":
            filletOuter(filletR)
        case "倒角":
            chamferOuter(chamferC)
        case "偏置":
            offsetOuter(offsetD)
        case "镜像":
            mirrorOuter()
        case "水平约束":
            constrain(horizontal: true)
        case "移动":
            moveOuter()
        case "延伸":
            extendLast(10)
        case "打断":
            breakLast()
        default:
            break
        }
    }

    private func pushUndo() {
        undoStack.append(spec)
        if undoStack.count > 30 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    private func undoSketch() {
        guard let last = undoStack.popLast() else { return }
        redoStack.append(spec)
        if redoStack.count > 30 { redoStack.removeFirst() }
        spec = last
        sketchTool = ""
        refPoints.removeAll()
        drawInner = false
        innerDraft.removeAll()
        selectedNode = nil
    }

    private func redoSketch() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(spec)
        spec = next
        sketchTool = ""
        refPoints.removeAll()
        drawInner = false
        innerDraft.removeAll()
        selectedNode = nil
    }

    private func clearSketch() {
        pushUndo()
        lastShapeTool = ""
        spec.constraints.removeAll()
        spec.template = .free
        spec.nodes = []
        spec.innerLoops = []
        spec.feats = []
        sketchTool = ""
        refPoints.removeAll()
        drawInner = false
        innerDraft.removeAll()
        selectedNode = nil
    }

    private func moveSketchNode(_ loc: CGPoint, size: CGSize) {
        guard !sketchFixed else { return }
        guard spec.template == .free, !spec.nodes.isEmpty else { return }
        let b = sketchBBox()
        let k = sketchScale(b: b, size: size)
        if dragNode == nil {
            var best = 26.0
            for (i, n) in spec.nodes.enumerated() {
                let sx = size.width / 2 + (n.x - b.midX) * k
                let sy = size.height / 2 - (n.y - b.midY) * k
                let d = hypot(Double(loc.x) - sx, Double(loc.y) - sy)
                if d < best { best = d; dragNode = i }
            }
            if dragNode != nil { pushUndo() }
        }
        guard let i = dragNode, i < spec.nodes.count else { return }
        selectedNode = i
        var nx = b.midX + (Double(loc.x) - Double(size.width) / 2) / k
        var ny = b.midY - (Double(loc.y) - Double(size.height) / 2) / k
        if snapGrid, gridStep > 0.01 {
            nx = round(nx / gridStep) * gridStep
            ny = round(ny / gridStep) * gridStep
        }
        spec.nodes[i].x = nx
        spec.nodes[i].y = ny
        solveSketchConstraints()
    }

    private func selectSketchNode(at loc: CGPoint, size: CGSize) {
        guard spec.template == .free, !spec.nodes.isEmpty else {
            showToastView("当前是模板轮廓，点“更多”可转成自由轮廓")
            return
        }
        let b = sketchBBox()
        let k = sketchScale(b: b, size: size)
        func screen(_ n: ContourNode) -> CGPoint {
            CGPoint(x: size.width / 2 + (n.x - b.midX) * k,
                    y: size.height / 2 - (n.y - b.midY) * k)
        }
        var bestNode = 26.0
        var nodeIndex: Int? = nil
        for (i, n) in spec.nodes.enumerated() {
            let q = screen(n)
            let d = hypot(Double(loc.x) - Double(q.x), Double(loc.y) - Double(q.y))
            if d < bestNode { bestNode = d; nodeIndex = i }
        }
        var bestSeg = 14.0
        var segIndex: Int? = nil
        let count = spec.nodes.count
        if count > 1 {
            for i in 0..<count {
                let a = screen(spec.nodes[i])
                let c = screen(spec.nodes[(i + 1) % count])
                let d = distanceToSegment(loc, a, c)
                if d < bestSeg { bestSeg = d; segIndex = i }
            }
        }
        // 靠近端点先锁点，其次才选段：UG 里点过滤和边过滤分开
        if let i = nodeIndex, bestNode < 10 {
            selectedNode = i
            selectedSegIndex = nil
            selectedSegB = nil
            showToastView("已选中点 \(i + 1)")
            return
        }
        // 靠近线段时优先选段
        if let s = segIndex, bestNode > 18 || bestSeg < 8 {
            if constraintPickMode {
                if selectedSegIndex == nil {
                    selectedSegIndex = s
                    showToastView("已选 A 段 \(s + 1)；再点一段作为 B")
                } else if selectedSegB == nil, s != selectedSegIndex {
                    selectedSegB = s
                    showToastView("已选 B 段 \(s + 1)；点约束按钮")
                } else {
                    selectedSegIndex = s
                    selectedSegB = nil
                    showToastView("已重选 A 段 \(s + 1)")
                }
            } else {
                selectedSegIndex = s
                selectedNode = nil
                selectedSegB = nil
                showToastView("已选中第 \(s + 1) 段")
            }
            return
        }
        if let i = nodeIndex {
            selectedNode = i
            selectedSegIndex = nil
            selectedSegB = nil
            showToastView("已选中点 \(i + 1)")
        } else {
            selectedNode = nil
            selectedSegIndex = nil
            selectedSegB = nil
        }
    }

    private func drawSketch(context: GraphicsContext, size: CGSize) {
        var ctx = context
        let b = sketchBBox()
        let k = sketchScale(b: b, size: size)
        let ox = size.width / 2, oy = size.height / 2

        func P(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: ox + (x - b.midX) * k, y: oy - (y - b.midY) * k)
        }

        // 网格（默认 10mm，可切 5/20/50）
        let stepMM = max(gridStep, 1)
        let halfW = Double(size.width) / 2 / k
        let halfH = Double(size.height) / 2 / k
        var gx = floor((b.midX - halfW) / stepMM) * stepMM
        while gx <= b.midX + halfW {
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: ox + (gx - b.midX) * k, y: 0))
                p.addLine(to: CGPoint(x: ox + (gx - b.midX) * k, y: size.height))
            }, with: .color(Color(.systemGray5)), lineWidth: 0.6)
            gx += stepMM
        }
        var gy = floor((b.midY - halfH) / stepMM) * stepMM
        while gy <= b.midY + halfH {
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: 0, y: oy - (gy - b.midY) * k))
                p.addLine(to: CGPoint(x: size.width, y: oy - (gy - b.midY) * k))
            }, with: .color(Color(.systemGray5)), lineWidth: 0.6)
            gy += stepMM
        }

        // 直线/多段线刚落下第一个点时只是“落点”，不能把单节点当成整圆画出来
        let singleLinePoint = spec.nodes.count == 1 && ["直线", "多段线"].contains(sketchTool)
        if !singleLinePoint {
            if let c = sketchFreeCircle {
                let center = P(c.cx, c.cy)
                let rr = c.r * k
                ctx.stroke(Path(ellipseIn: CGRect(x: center.x - rr, y: center.y - rr,
                                                  width: rr * 2, height: rr * 2)),
                           with: .color(.orange), lineWidth: 2)
            } else {
                let segs = ContourGeo.segments(ContourGeo.buildNodes(sketchDrawSpec()))
                var path = Path()
                if let f = segs.first {
                    path.move(to: P(f.p0.x, f.p0.y))
                }
                for s in segs {
                    if s.isArc {
                        // 用折线近似显示圆弧
                        let flat = ContourGeo.flatten([s], arcStep: 24)
                        for q in flat.dropFirst() { path.addLine(to: P(q.x, q.y)) }
                    } else {
                        path.addLine(to: P(s.p1.x, s.p1.y))
                    }
                }
                ctx.stroke(path, with: .color(.orange), lineWidth: 2)
            }
        }

        // 选中的草图段：A 绿色，B 蓝色；编辑/约束优先作用于它们
        if spec.template == .free, spec.nodes.count > 1 {
            func segPath(_ i: Int) -> Path {
                let a = spec.nodes[i], b = spec.nodes[(i + 1) % spec.nodes.count]
                var pth = Path()
                pth.move(to: P(a.x, a.y))
                if b.kind != .line {
                    let seg = ContourSeg(p0: CGPoint(x: a.x, y: a.y),
                                         p1: CGPoint(x: b.x, y: b.y),
                                         kind: b.kind, r: b.r, full: false)
                    for q in ContourGeo.flatten([seg], arcStep: 24).dropFirst() {
                        pth.addLine(to: P(Double(q.x), Double(q.y)))
                    }
                } else {
                    pth.addLine(to: P(b.x, b.y))
                }
                return pth
            }
            if let a = selectedSegIndex {
                ctx.stroke(segPath(a), with: .color(.green), lineWidth: 4)
            }
            if let b = selectedSegB, b != selectedSegIndex {
                ctx.stroke(segPath(b), with: .color(studioBlue), lineWidth: 4)
            }
        }

        // 同一张草图上的内轮廓（挖孔 / 型腔）
        for l in spec.innerLoops {
            let d = PartProg.drawForLoop(l, spec, depth: l.through ? spec.height + 1 : l.depth,
                                         dia: max(spec.pocketDia, 1), hNo: spec.pocketTool)
            let segs = ContourGeo.segments(ContourGeo.buildNodes(d))
            var lp = Path()
            if let f = segs.first {
                lp.move(to: P(f.p0.x + l.cx, f.p0.y + l.cy))
            }
            for sg in segs {
                if sg.isArc {
                    let flat = ContourGeo.flatten([sg], arcStep: 24)
                    for q in flat.dropFirst() { lp.addLine(to: P(q.x + l.cx, q.y + l.cy)) }
                } else {
                    lp.addLine(to: P(sg.p1.x + l.cx, sg.p1.y + l.cy))
                }
            }
            ctx.stroke(lp, with: .color(.red),
                       style: StrokeStyle(lineWidth: 1.6, dash: [5, 4]))
            let c = P(l.cx, l.cy)
            let text: String
            switch l.template {
            case .circle: text = "Ø" + ncf(l.circleD)
            case .rect: text = ncf(l.rectL) + "×" + ncf(l.rectW)
            case .slot: text = ncf(l.slotL) + "×" + ncf(l.slotW)
            case .free: text = l.name
            }
            ctx.draw(Text(text).font(.system(size: 9, weight: .semibold)).foregroundColor(.red),
                     at: CGPoint(x: c.x, y: c.y - 10))
        }

        // 识别/新增的孔、圆腔、方腔也叠在草图上，方便先核对位置和尺寸
        for f in spec.feats where !hiddenTreeIDs.contains("feat-\(f.id.uuidString)")
            && !(showFeatCommand && featEditID == f.id) {
            let c = P(f.x, f.y)
            if f.kind == .hole {
                let r = max(2, f.dia / 2 * k)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                         with: .color(Color.red.opacity(0.10)))
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                           with: .color(.red), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                ctx.draw(Text("Ø\(ncf(f.dia))").font(.system(size: 8, weight: .semibold)).foregroundColor(.red),
                         at: CGPoint(x: c.x, y: c.y - r - 8))
            } else {
                let w = max(3, f.w * k), h = max(3, f.h * k)
                let rect = CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
                ctx.stroke(Path(roundedRect: rect, cornerRadius: 1),
                           with: .color(.red), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                ctx.draw(Text("\(ncf(f.w))×\(ncf(f.h))").font(.system(size: 8, weight: .semibold)).foregroundColor(.red),
                         at: CGPoint(x: c.x, y: c.y - h / 2 - 8))
            }
        }

        if drawInner, innerDraft.count > 1 {
            var dp = Path()
            dp.move(to: P(innerDraft[0].x, innerDraft[0].y))
            for q in innerDraft.dropFirst() { dp.addLine(to: P(q.x, q.y)) }
            ctx.stroke(dp, with: .color(.orange), style: StrokeStyle(lineWidth: 1.8, dash: [5, 4]))
        }

        // 参考点 / 三点圆用的点
        for (i, rp) in refPoints.enumerated() {
            let q = P(Double(rp.x), Double(rp.y))
            ctx.fill(Path(ellipseIn: CGRect(x: q.x - 4, y: q.y - 4, width: 8, height: 8)),
                     with: .color(.purple))
            ctx.draw(Text("\(i + 1)").font(.system(size: 8)).foregroundColor(.purple),
                     at: CGPoint(x: q.x + 8, y: q.y - 8))
        }

        // 自由轮廓节点（识别为圆时不再画 32 个节点）
        if spec.template == .free, sketchFreeCircle == nil {
            for (i, n) in spec.nodes.enumerated() {
                let q = P(n.x, n.y)
                let selected = (selectedNode == i)
                ctx.fill(Path(ellipseIn: CGRect(x: q.x - (selected ? 6 : 4), y: q.y - (selected ? 6 : 4),
                                                width: selected ? 12 : 8, height: selected ? 12 : 8)),
                         with: .color(selected ? .orange : .blue))
                if selected {
                    ctx.stroke(Path(ellipseIn: CGRect(x: q.x - 10, y: q.y - 10, width: 20, height: 20)),
                               with: .color(.orange.opacity(0.6)), lineWidth: 1.5)
                }
            }
        }

        // 约束图标：贴在关联几何旁，冲突约束显示红色
        if showConstraintBadges {
            var badgeSlots: [String: Int] = [:]
            for c in spec.constraints {
                guard let a = constraintAnchor(c) else { continue }
                let base = P(a.0, a.1)
                let key = "\(Int(base.x / 18))-\(Int(base.y / 18))"
                let slot = badgeSlots[key, default: 0]
                badgeSlots[key] = slot + 1
                let pos = CGPoint(x: base.x + 12 + CGFloat(slot % 3) * 16,
                                  y: base.y - 12 - CGFloat(slot / 3) * 16)
                let bad = constraintResidual(c) > constraintTolerance(c)
                let rect = CGRect(x: pos.x - 8, y: pos.y - 8, width: 16, height: 16)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 5),
                         with: .color(bad ? Color.red : studioBlue))
                ctx.draw(Text(c.symbol).font(.system(size: 8, weight: .bold)).foregroundColor(.white),
                         at: pos)
            }
        }

        // 尺寸标注
        switch spec.template {
        case .rect:
            drawDim(ctx, from: P(-spec.rectL / 2, -spec.rectW / 2 - 14), to: P(spec.rectL / 2, -spec.rectW / 2 - 14),
                    text: "L " + ncf(spec.rectL))
            drawDim(ctx, from: P(-spec.rectL / 2 - 14, -spec.rectW / 2), to: P(-spec.rectL / 2 - 14, spec.rectW / 2),
                    text: "W " + ncf(spec.rectW))
        case .circle:
            drawDim(ctx, from: P(-spec.circleD / 2, 0), to: P(spec.circleD / 2, 0),
                    text: "Ø" + ncf(spec.circleD))
        case .slot:
            drawDim(ctx, from: P(-spec.slotL / 2, -spec.slotW / 2 - 12), to: P(spec.slotL / 2, -spec.slotW / 2 - 12),
                    text: "L " + ncf(spec.slotL))
        case .free:
            if let c = sketchFreeCircle {
                drawDim(ctx, from: P(c.cx - c.r, c.cy), to: P(c.cx + c.r, c.cy),
                        text: "Ø" + ncf(c.r * 2))
                let center = P(c.cx, c.cy)
                ctx.stroke(Path { p in
                    p.move(to: CGPoint(x: center.x - 6, y: center.y))
                    p.addLine(to: CGPoint(x: center.x + 6, y: center.y))
                    p.move(to: CGPoint(x: center.x, y: center.y - 6))
                    p.addLine(to: CGPoint(x: center.x, y: center.y + 6))
                }, with: .color(.blue.opacity(0.65)), lineWidth: 1)
            } else {
                let nodes = spec.nodes
                if nodes.count > 1 {
                    let minX = nodes.map(\.x).min() ?? 0
                    let maxX = nodes.map(\.x).max() ?? 0
                    let minY = nodes.map(\.y).min() ?? 0
                    let maxY = nodes.map(\.y).max() ?? 0
                    drawDim(ctx, from: P(minX, minY - 16), to: P(maxX, minY - 16),
                            text: "包络 " + ncf(maxX - minX))
                    drawDim(ctx, from: P(minX - 16, minY), to: P(minX - 16, maxY),
                            text: "包络 " + ncf(maxY - minY))
                    for i in 0..<nodes.count {
                        let a = nodes[i]
                        let c = nodes[(i + 1) % nodes.count]
                        let len = hypot(c.x - a.x, c.y - a.y)
                        let mid = P((a.x + c.x) / 2, (a.y + c.y) / 2)
                        ctx.draw(Text(String(format: "%.1f", len)).font(.system(size: 9)).foregroundColor(.blue),
                                 at: CGPoint(x: mid.x, y: mid.y - 10))
                    }
                    for i in nodes.indices {
                        let deg = vertexAngle(nodes, i)
                        let q = P(nodes[i].x, nodes[i].y)
                        ctx.draw(Text(String(format: "%.0f°", deg)).font(.system(size: 8)).foregroundColor(.purple),
                                 at: CGPoint(x: q.x + 12, y: q.y + 10))
                        if nodes[i].kind != .line {
                            let a = nodes[i], c = nodes[(i + 1) % nodes.count]
                            let mid = P((a.x + c.x) / 2, (a.y + c.y) / 2)
                            ctx.draw(Text("R" + ncf(a.r)).font(.system(size: 8)).foregroundColor(.green),
                                     at: CGPoint(x: mid.x, y: mid.y + 9))
                        }
                    }
                }
            }
        }

        if let preview = editPreviewSpec {
            for l in preview.innerLoops
                where spec.innerLoops.first(where: { $0.id == l.id }) != l {
                let d = PartProg.drawForLoop(l, preview,
                                             depth: l.through ? preview.height + 1 : l.depth,
                                             dia: max(preview.pocketDia, 1), hNo: preview.pocketTool)
                let segs = ContourGeo.segments(ContourGeo.buildNodes(d))
                var lp = Path()
                if let f = segs.first { lp.move(to: P(f.p0.x + l.cx, f.p0.y + l.cy)) }
                for sg in segs {
                    if sg.isArc {
                        let flat = ContourGeo.flatten([sg], arcStep: 24)
                        for q in flat.dropFirst() { lp.addLine(to: P(q.x + l.cx, q.y + l.cy)) }
                    } else {
                        lp.addLine(to: P(sg.p1.x + l.cx, sg.p1.y + l.cy))
                    }
                }
                ctx.stroke(lp, with: .color(Color.blue.opacity(0.85)),
                           style: StrokeStyle(lineWidth: 1.6, dash: [5, 3]))
            }
            for f in preview.feats
                where spec.feats.first(where: { $0.id == f.id }) != f {
                let c = P(f.x, f.y)
                if f.kind == .rectPocket {
                    let w = max(3, f.w * k), h = max(3, f.h * k)
                    let rect = CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
                    ctx.stroke(Path(roundedRect: rect, cornerRadius: 1),
                               with: .color(Color.blue.opacity(0.85)),
                               style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                } else {
                    let rr = max(2, f.dia / 2 * k)
                    ctx.stroke(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2)),
                               with: .color(Color.blue.opacity(0.85)),
                               style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
            }
            let segs = ContourGeo.segments(ContourGeo.buildNodes(sketchDrawSpec(preview)))
            var pp = Path()
            if let f = segs.first { pp.move(to: P(f.p0.x, f.p0.y)) }
            for sg in segs {
                if sg.isArc {
                    let flat = ContourGeo.flatten([sg], arcStep: 24)
                    for q in flat.dropFirst() { pp.addLine(to: P(q.x, q.y)) }
                } else {
                    pp.addLine(to: P(sg.p1.x, sg.p1.y))
                }
            }
            ctx.stroke(pp, with: .color(Color.blue.opacity(0.95)),
                       style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
            ctx.draw(Text("预览").font(.system(size: 9, weight: .bold)).foregroundColor(.blue),
                     at: CGPoint(x: size.width - 34, y: 18))
        }
    }

    private func drawDim(_ ctx: GraphicsContext, from: CGPoint, to: CGPoint, text: String) {
        var p = Path()
        p.move(to: from)
        p.addLine(to: to)
        ctx.stroke(p, with: .color(.blue), lineWidth: 0.8)
        ctx.draw(Text(text).font(.system(size: 10, weight: .medium)).foregroundColor(.blue),
                 at: CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2 - 9))
    }

    private func vertexAngle(_ nodes: [ContourNode], _ i: Int) -> Double {
        guard nodes.count > 2 else { return 0 }
        let cur = nodes[i]
        let prev = nodes[(i + nodes.count - 1) % nodes.count]
        let next = nodes[(i + 1) % nodes.count]
        let ux = prev.x - cur.x, uy = prev.y - cur.y
        let vx = next.x - cur.x, vy = next.y - cur.y
        let lu = hypot(ux, uy), lv = hypot(vx, vy)
        guard lu > 1e-9, lv > 1e-9 else { return 0 }
        let dot = max(-1.0, min(1.0, (ux * vx + uy * vy) / (lu * lv)))
        return acos(dot) * 180 / Double.pi
    }

    private func pickDim(at loc: CGPoint, size: CGSize) {
        let b = sketchBBox()
        let k = sketchScale(b: b, size: size)
        let ox = Double(size.width) / 2, oy = Double(size.height) / 2
        func P(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: ox + (x - Double(b.midX)) * k, y: oy - (y - Double(b.midY)) * k)
        }
        var hits: [(DimTarget, CGPoint, String, Double)] = []
        switch spec.template {
        case .rect:
            hits.append((.rectL, P(0, -spec.rectW / 2 - 14), "长 L", spec.rectL))
            hits.append((.rectW, P(-spec.rectL / 2 - 14, 0), "宽 W", spec.rectW))
        case .circle:
            hits.append((.circleD, P(0, 0), "直径 Ø", spec.circleD))
        case .slot:
            hits.append((.slotL, P(0, -spec.slotW / 2 - 12), "槽长 L", spec.slotL))
        case .free:
            if let c = sketchFreeCircle {
                hits.append((.freeCircleD, P(c.cx, c.cy), "直径 Ø", c.r * 2))
            } else {
                let nodes = spec.nodes
                if nodes.count > 1 {
                    for i in nodes.indices {
                        let a = nodes[i], c = nodes[(i + 1) % nodes.count]
                        let mid = P((a.x + c.x) / 2, (a.y + c.y) / 2 - 10 / k)
                        hits.append((.nodeLen(i), mid, "第 \(i + 1) 段长度", hypot(c.x - a.x, c.y - a.y)))
                    }
                    for i in nodes.indices {
                        let q = P(nodes[i].x, nodes[i].y)
                        hits.append((.nodeAngle(i), CGPoint(x: q.x + 12, y: q.y + 10), "点 \(i + 1) 角度", vertexAngle(nodes, i)))
                    }
                    for i in nodes.indices where nodes[i].kind != .line {
                        let a = nodes[i], c = nodes[(i + 1) % nodes.count]
                        let mid = P((a.x + c.x) / 2, (a.y + c.y) / 2)
                        hits.append((.nodeR(i), CGPoint(x: mid.x, y: mid.y + 9), "点 \(i + 1) 圆弧 R", nodes[i].r))
                    }
                }
            }
        }
        var best: (DimTarget, String, Double)? = nil
        var bestD = 30.0
        for h in hits {
            let d = hypot(Double(loc.x) - Double(h.1.x), Double(loc.y) - Double(h.1.y))
            if d < bestD { bestD = d; best = (h.0, h.2, h.3) }
        }
        guard let b2 = best else { return }
        dimTarget = b2.0
        dimEditTitle = "改 " + b2.1
        dimEditText = String(format: "%.2f", b2.2)
        showDimEdit = true
    }

    private func applyDimEdit() {
        guard let v = Double(dimEditText), v.isFinite else { return }
        switch dimTarget {
        case .rectL:
            if v > 0.1 { spec.rectL = v }
        case .rectW:
            if v > 0.1 { spec.rectW = v }
        case .rectR:
            if v >= 0 { spec.rectR = v }
        case .circleD:
            if v > 0.1 { spec.circleD = v }
        case .freeCircleD:
            guard let c = sketchFreeCircle, v > 0.1 else { return }
            let scale = v / (c.r * 2)
            for i in spec.nodes.indices {
                spec.nodes[i].x = c.cx + (spec.nodes[i].x - c.cx) * scale
                spec.nodes[i].y = c.cy + (spec.nodes[i].y - c.cy) * scale
            }
            spec.circleD = v
        case .slotL:
            if v > 0.1 { spec.slotL = v }
        case .slotW:
            if v > 0.1 { spec.slotW = v }
        case .nodeLen(let i):
            guard spec.nodes.count > 1, v > 0.05 else { return }
            let a = spec.nodes[i]
            let c = spec.nodes[(i + 1) % spec.nodes.count]
            let dx = c.x - a.x, dy = c.y - a.y
            let len = hypot(dx, dy)
            guard len > 1e-6 else { return }
            let nx = a.x + dx / len * v
            let ny = a.y + dy / len * v
            let j = (i + 1) % spec.nodes.count
            spec.nodes[j].x = nx
            spec.nodes[j].y = ny
        case .nodeAngle(let i):
            guard spec.nodes.count > 2 else { return }
            let cur = spec.nodes[i]
            let prev = spec.nodes[(i + spec.nodes.count - 1) % spec.nodes.count]
            let next = spec.nodes[(i + 1) % spec.nodes.count]
            let old = vertexAngle(spec.nodes, i)
            let delta = (v - old) * Double.pi / 180
            let ux = prev.x - cur.x, uy = prev.y - cur.y
            let vx = next.x - cur.x, vy = next.y - cur.y
            let cross = ux * vy - uy * vx
            let sign = cross >= 0 ? 1.0 : -1.0
            let ca = cos(delta * sign), sa = sin(delta * sign)
            let j = (i + 1) % spec.nodes.count
            spec.nodes[j].x = cur.x + vx * ca - vy * sa
            spec.nodes[j].y = cur.y + vx * sa + vy * ca
        case .nodeR(let i):
            if v > 0.01 { spec.nodes[i].r = v }
        case .none:
            break
        }
        solveSketchConstraints()
    }

    private func sketchDrawSpec(_ source: PartSpec? = nil) -> DrawSpec {
        let s = source ?? spec
        var d = DrawSpec()
        d.template = s.template
        d.rectL = s.rectL
        d.rectW = s.rectW
        d.rectR = s.rectR
        d.circleD = s.circleD
        d.slotL = s.slotL
        d.slotW = s.slotW
        d.nodes = s.nodes
        return d
    }

    /// 用“圆”工具在画布上放置的圆，会以多段节点保存；这里识别出真正的圆，
    /// 显示和标注都按圆处理，避免出现一串 9.8 / 169° 的分段标签。
    private var sketchFreeCircle: (cx: Double, cy: Double, r: Double)? {
        guard spec.template == .free, spec.nodes.count >= 12 else { return nil }
        let n = Double(spec.nodes.count)
        let cx = spec.nodes.reduce(0) { $0 + $1.x } / n
        let cy = spec.nodes.reduce(0) { $0 + $1.y } / n
        let radii = spec.nodes.map { hypot($0.x - cx, $0.y - cy) }
        guard let minR = radii.min(), let maxR = radii.max(), minR > 0.1 else { return nil }
        let avg = radii.reduce(0, +) / n
        let tolerance = max(0.12, avg * 0.02)
        guard maxR - minR <= tolerance else { return nil }
        return (cx, cy, avg)
    }

    private func sketchBBox() -> CGRect {
        var d = sketchDrawSpec()
        if d.template == .free && d.nodes.isEmpty {
            d.template = .rect
        }
        let pts = ContourGeo.flatten(ContourGeo.segments(ContourGeo.buildNodes(d)))
        guard let f = pts.first else { return CGRect(x: -80, y: -60, width: 160, height: 120) }
        var mnx = f.x, mxx = f.x, mny = f.y, mxy = f.y
        for q in pts {
            mnx = min(mnx, q.x); mxx = max(mxx, q.x)
            mny = min(mny, q.y); mxy = max(mxy, q.y)
        }
        // 画布视野至少 160×120，避免只画一个点时比例突然放大
        let cw = max(mxx - mnx, 160)
        let ch = max(mxy - mny, 120)
        let cx = (mnx + mxx) / 2
        let cy = (mny + mxy) / 2
        return CGRect(x: cx - cw / 2, y: cy - ch / 2, width: cw, height: ch)
    }

    private func sketchScale(b: CGRect, size: CGSize) -> Double {
        min((Double(size.width) - 60) / max(Double(b.width), 1),
            (Double(size.height) - 60) / max(Double(b.height), 1))
    }

    private func fillRectNodes() {
        spec.constraints.removeAll()
        let d = sketchDrawSpec()
        var nodes = ContourGeo.buildNodes(d)
        if nodes.isEmpty {
            nodes = [
                ContourNode(x: -spec.rectL / 2, y: -spec.rectW / 2),
                ContourNode(x: spec.rectL / 2, y: -spec.rectW / 2),
                ContourNode(x: spec.rectL / 2, y: spec.rectW / 2),
                ContourNode(x: -spec.rectL / 2, y: spec.rectW / 2)
            ]
        }
        spec.nodes = nodes
        spec.template = .free
    }

    private func addNode() {
        if spec.template != .free { fillRectNodes() }
        let last = spec.nodes.last ?? ContourNode(x: 0, y: 0)
        spec.nodes.append(ContourNode(x: last.x + 20, y: last.y))
    }

    private func makeLine() {
        sketchTool = "直线"
        lastShapeTool = ""
        spec.constraints.removeAll()
        spec.nodes = []
        spec.template = .free
        refPoints.removeAll()
    }

    private func makePolyline() {
        sketchTool = "多段线"
        lastShapeTool = ""
        spec.constraints.removeAll()
        spec.nodes = []
        spec.template = .free
        refPoints.removeAll()
    }

    private func toggleInnerDraw() {
        if drawInner {
            if innerDraft.count >= 3 {
                finishInner()
                showToastView("手画内轮廓已加入")
            } else {
                drawInner = false
                innerDraft.removeAll()
                sketchTool = ""
                showToastView("已结束手画：点数不足 3 个，未生成内轮廓")
            }
        } else {
            drawInner = true
            innerDraft.removeAll()
            sketchTool = "多段线"
            showToastView("在画布上连续点，画完再点一次“完成手画”")
        }
    }

    private func finishInner() {
        guard innerDraft.count >= 3 else { return }
        pushUndo()
        let cx = innerDraft.reduce(0.0) { $0 + $1.x } / Double(innerDraft.count)
        let cy = innerDraft.reduce(0.0) { $0 + $1.y } / Double(innerDraft.count)
        var l = SketchLoop(template: .free)
        l.name = "内轮廓"
        l.cx = cx
        l.cy = cy
        l.nodes = innerDraft.map { ContourNode(x: $0.x - cx, y: $0.y - cy) }
        l.through = true
        l.depth = spec.height
        spec.innerLoops.append(l)
        innerDraft.removeAll()
        drawInner = false
        sketchTool = ""
    }

    private func isDrawTool(_ tool: String) -> Bool {
        ["直线", "多段线", "三点圆", "圆弧", "点"].contains(tool)
    }

    private func addPointAt(_ loc: CGPoint, size: CGSize) {
        let b = sketchBBox()
        let k = sketchScale(b: b, size: size)
        let x = b.midX + (Double(loc.x) - Double(size.width) / 2) / k
        let y = b.midY - (Double(loc.y) - Double(size.height) / 2) / k
        var px = x, py = y
        if snapGrid, gridStep > 0.01 {
            px = round(px / gridStep) * gridStep
            py = round(py / gridStep) * gridStep
        }
        var snappedNodeIndex: Int? = nil
        if (snapVertex || autoConstrain), !spec.nodes.isEmpty,
           let nearIdx = spec.nodes.indices.min(by: {
               hypot(spec.nodes[$0].x - px, spec.nodes[$0].y - py)
                   < hypot(spec.nodes[$1].x - px, spec.nodes[$1].y - py)
           }),
           hypot(spec.nodes[nearIdx].x - px, spec.nodes[nearIdx].y - py) < (snapVertex ? 8 : 3) {
            px = spec.nodes[nearIdx].x
            py = spec.nodes[nearIdx].y
            snappedNodeIndex = nearIdx
        }
        if drawInner {
            if innerDraft.isEmpty || hypot(px - innerDraft.last!.x, py - innerDraft.last!.y) > 0.2 {
                pushUndo()
                innerDraft.append(ContourNode(x: px, y: py))
            }
            return
        }
        if sketchTool == "点" || sketchTool == "三点圆" || sketchTool == "圆弧" {
            refPoints.append(CGPoint(x: px, y: py))
            if sketchTool == "三点圆" && refPoints.count >= 3 {
                threePointCircle()
                sketchTool = ""
                refPoints.removeAll()
            }
            if sketchTool == "圆弧" && refPoints.count >= 3 {
                threePointArc()
                sketchTool = ""
                refPoints.removeAll()
            }
            return
        }
        let previousIndex = spec.nodes.count - 1
        if spec.nodes.isEmpty {
            pushUndo()
            spec.nodes.append(ContourNode(x: px, y: py))
        } else if let last = spec.nodes.last, hypot(px - last.x, py - last.y) > 0.2 {
            // 自动吸附近水平/竖直，先把坐标拉正，再加约束
            if autoConstrain {
                let tol = autoConstraintTolerance
                if abs(py - last.y) <= tol && abs(px - last.x) > tol {
                    py = last.y
                } else if abs(px - last.x) <= tol && abs(py - last.y) > tol {
                    px = last.x
                }
            }
            pushUndo()
            spec.nodes.append(ContourNode(x: px, y: py))
            let newIndex = spec.nodes.count - 1
            if autoConstrain {
                if previousIndex >= 0 {
                    let a = spec.nodes[previousIndex], b = spec.nodes[newIndex]
                    if abs(a.y - b.y) <= autoConstraintTolerance && abs(a.x - b.x) > autoConstraintTolerance {
                        addAutoConstraint(.horizontal, a: previousIndex, b: newIndex)
                    } else if abs(a.x - b.x) <= autoConstraintTolerance && abs(a.y - b.y) > autoConstraintTolerance {
                        addAutoConstraint(.vertical, a: previousIndex, b: newIndex)
                    }
                }
                if let snappedNodeIndex, snappedNodeIndex != newIndex {
                    addAutoConstraint(.coincident, a: snappedNodeIndex, b: newIndex)
                }
                solveSketchConstraints()
            }
        }
        selectedNode = spec.nodes.isEmpty ? nil : spec.nodes.count - 1
        if !continuousDraw { sketchTool = "" }
    }

    private func isEditTool(_ tool: String) -> Bool {
        ["修剪", "围栏修剪", "区域修剪", "圆角", "倒角", "偏置", "镜像",
         "水平约束", "移动", "延伸", "打断"].contains(tool)
    }

    private func requestEditTool(_ name: String) {
        beginEditPreview(name)
    }

    private func beginEditPreview(_ name: String) {
        guard isEditTool(name) else { return }
        let saved = spec
        applyEditOperation(name)
        let candidate = spec
        spec = saved
        pendingEditTool = name
        editPreviewSpec = candidate
        sketchTool = name
    }

    private func cancelEditPreview() {
        editPreviewSpec = nil
        pendingEditTool = nil
        sketchTool = ""
    }

    private func confirmEditPreview() {
        guard let candidate = editPreviewSpec else { return }
        let name = pendingEditTool ?? "编辑"
        pushUndo()
        spec = candidate
        editPreviewSpec = nil
        pendingEditTool = nil
        sketchTool = ""
        selectedNode = nil
        selectedSegIndex = nil
        selectedSegB = nil
        showToastView("已应用\(name)")
    }

    private func applyEditOperation(_ name: String) {
        switch name {
        case "修剪": trimSelected()
        case "围栏修剪", "区域修剪": regionTrim()
        case "圆角": filletSelected(filletR)
        case "倒角": chamferSelected(chamferC)
        case "偏置": offsetSelected(offsetD)
        case "镜像": mirrorSelected()
        case "水平约束": constrain(horizontal: true)
        case "移动": moveSelected()
        case "延伸": extendSelected(10)
        case "打断": breakSelected()
        default: break
        }
    }

    /// 当前选段；没有选段时返回 nil，让旧算法按整条轮廓处理
    private func targetSegment() -> Int? {
        guard spec.template == .free, spec.nodes.count > 2,
              let i = selectedSegIndex, i >= 0, i < spec.nodes.count else { return nil }
        return i
    }

    private func trimSelected() {
        guard let i = targetSegment() else {
            if let node = selectedNode, spec.nodes.count > 2 {
                spec.nodes.remove(at: node)
                selectedNode = nil
                return
            }
            trimLast()
            return
        }
        // 闭合轮廓删掉选中段的终点，前后段自动接起来；相当于 UG 的单段修剪近似
        let remove = (i + 1) % spec.nodes.count
        spec.nodes.remove(at: remove)
        selectedSegIndex = nil
        selectedSegB = nil
    }

    private func extendSelected(_ d: Double) {
        guard let i = targetSegment() else { extendLast(d); return }
        let n = spec.nodes.count
        let a = spec.nodes[i], b = spec.nodes[(i + 1) % n]
        let dx = b.x - a.x, dy = b.y - a.y
        let len = hypot(dx, dy)
        guard len > 1e-6 else { return }
        let idx = (i + 1) % n
        spec.nodes[idx].x = b.x + dx / len * d
        spec.nodes[idx].y = b.y + dy / len * d
    }

    private func breakSelected() {
        guard let i = targetSegment() else { breakLast(); return }
        let n = spec.nodes.count
        let a = spec.nodes[i], b = spec.nodes[(i + 1) % n]
        let mid = ContourNode(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2,
                              kind: .line, r: b.r)
        spec.nodes.insert(mid, at: min(i + 1, spec.nodes.count))
        selectedSegIndex = nil
        selectedSegB = nil
    }

    private func offsetSelected(_ d: Double) {
        guard let i = targetSegment() else { offsetOuter(d); return }
        let n = spec.nodes.count
        let a = spec.nodes[i], b = spec.nodes[(i + 1) % n]
        let dx = b.x - a.x, dy = b.y - a.y
        let len = hypot(dx, dy)
        guard len > 1e-6 else { return }
        let nx = dy / len, ny = -dx / len
        spec.nodes[i].x += nx * d; spec.nodes[i].y += ny * d
        let bi = (i + 1) % n
        spec.nodes[bi].x += nx * d; spec.nodes[bi].y += ny * d
        spec.constraints.removeAll()
    }

    private func moveSelected() {
        guard let i = targetSegment() else { moveOuter(); return }
        let n = spec.nodes.count
        spec.nodes[i].x += moveDX; spec.nodes[i].y += moveDY
        let bi = (i + 1) % n
        spec.nodes[bi].x += moveDX; spec.nodes[bi].y += moveDY
        spec.constraints.removeAll()
    }

    private func mirrorSelected() {
        guard let i = targetSegment() else { mirrorOuter(); return }
        let b = sketchBBox()
        let midX = Double(b.midX)
        let n = spec.nodes.count
        spec.nodes[i].x = midX * 2 - spec.nodes[i].x
        let bi = (i + 1) % n
        spec.nodes[bi].x = midX * 2 - spec.nodes[bi].x
        spec.constraints.removeAll()
    }

    private func filletSelected(_ r: Double) {
        guard let node = selectedNode, spec.nodes.count > 2, r > 0.01 else {
            filletOuter(r)
            return
        }
        let n = spec.nodes.count
        let curr = spec.nodes[node]
        let prev = spec.nodes[(node - 1 + n) % n]
        let next = spec.nodes[(node + 1) % n]
        guard curr.kind == .line, prev.kind == .line, next.kind == .line else {
            filletOuter(r)
            return
        }
        let u1x = prev.x - curr.x, u1y = prev.y - curr.y
        let u2x = next.x - curr.x, u2y = next.y - curr.y
        let l1 = hypot(u1x, u1y), l2 = hypot(u2x, u2y)
        guard l1 > 1e-6, l2 > 1e-6 else { return }
        let dot = max(-1, min(1, (u1x * u2x + u1y * u2y) / (l1 * l2)))
        let theta = acos(dot)
        guard theta > 0.05, theta < 3.09 else { return }
        let tangent = r / tan(theta / 2)
        guard tangent < l1 * 0.95, tangent < l2 * 0.95 else { return }
        let p1 = ContourNode(x: curr.x + u1x / l1 * tangent,
                             y: curr.y + u1y / l1 * tangent, kind: .line)
        let p2 = ContourNode(x: curr.x + u2x / l2 * tangent,
                             y: curr.y + u2y / l2 * tangent, kind: .cw, r: r)
        spec.nodes[node] = p1
        spec.nodes.insert(p2, at: min(node + 1, spec.nodes.count))
        selectedNode = node
        selectedSegIndex = nil
        spec.constraints.removeAll()
    }

    private func chamferSelected(_ c: Double) {
        guard let node = selectedNode, spec.nodes.count > 2, c > 0.01 else {
            chamferOuter(c)
            return
        }
        let n = spec.nodes.count
        let curr = spec.nodes[node]
        let prev = spec.nodes[(node - 1 + n) % n]
        let next = spec.nodes[(node + 1) % n]
        guard curr.kind == .line, prev.kind == .line, next.kind == .line else {
            chamferOuter(c)
            return
        }
        let u1x = prev.x - curr.x, u1y = prev.y - curr.y
        let u2x = next.x - curr.x, u2y = next.y - curr.y
        let l1 = hypot(u1x, u1y), l2 = hypot(u2x, u2y)
        guard l1 > 1e-6, l2 > 1e-6, c < l1 * 0.95, c < l2 * 0.95 else { return }
        let p1 = ContourNode(x: curr.x + u1x / l1 * c,
                             y: curr.y + u1y / l1 * c, kind: .line)
        let p2 = ContourNode(x: curr.x + u2x / l2 * c,
                             y: curr.y + u2y / l2 * c, kind: .line)
        spec.nodes[node] = p1
        spec.nodes.insert(p2, at: min(node + 1, spec.nodes.count))
        selectedNode = node
        selectedSegIndex = nil
        spec.constraints.removeAll()
    }

    private func isTemplateTool(_ tool: String) -> Bool {
        ["矩形", "中心矩形", "圆角矩形", "圆", "椭圆", "多边形", "五角星",
         "样条曲线", "槽", "平行四边形"].contains(tool)
    }

    private func selectTemplateTool(_ name: String) {
        selectedSegIndex = nil
        selectedSegB = nil
        sketchTool = name
        lastShapeTool = name
        refPoints.removeAll()
        drawInner = false
        showToastView("\(name) 已选：点画布放置，连续点可继续移放")
    }

    private func templateLocalNodes(_ name: String, L: Double, W: Double, D: Double, R: Double) -> [ContourNode] {
        var local: [ContourNode] = []
        switch name {
        case "矩形", "中心矩形":
            local = [
                ContourNode(x: -L / 2, y: -W / 2),
                ContourNode(x: L / 2, y: -W / 2),
                ContourNode(x: L / 2, y: W / 2),
                ContourNode(x: -L / 2, y: W / 2)
            ]
        case "圆角矩形":
            let rr = min(max(R, 0), min(L, W) / 2)
            if rr <= 0.1 {
                local = [
                    ContourNode(x: -L / 2, y: -W / 2),
                    ContourNode(x: L / 2, y: -W / 2),
                    ContourNode(x: L / 2, y: W / 2),
                    ContourNode(x: -L / 2, y: W / 2)
                ]
            } else {
                func arc(_ cx: Double, _ cy: Double, _ a0: Double, _ a1: Double) {
                    for i in 0...5 {
                        let a = a0 + (a1 - a0) * Double(i) / 5
                        local.append(ContourNode(x: cx + rr * cos(a), y: cy + rr * sin(a)))
                    }
                }
                arc(L / 2 - rr, -W / 2 + rr, 0, -Double.pi / 2)
                arc(-L / 2 + rr, -W / 2 + rr, -Double.pi / 2, -Double.pi)
                arc(-L / 2 + rr, W / 2 - rr, Double.pi, Double.pi / 2)
                arc(L / 2 - rr, W / 2 - rr, Double.pi / 2, 0)
            }
        case "圆":
            let r = D / 2
            local = (0..<32).map { i in
                let a = Double(i) / 32 * 2 * Double.pi
                return ContourNode(x: r * cos(a), y: r * sin(a))
            }
        case "椭圆":
            let rx = L / 2, ry = W / 2
            local = (0..<32).map { i in
                let a = Double(i) / 32 * 2 * Double.pi
                return ContourNode(x: rx * cos(a), y: ry * sin(a))
            }
        case "多边形":
            let r = D / 2
            local = (0..<6).map { i in
                let a = Double(i) / 6 * 2 * Double.pi + Double.pi / 2
                return ContourNode(x: r * cos(a), y: r * sin(a))
            }
        case "五角星":
            let R = D / 2, rr = R * 0.42
            local = (0..<10).map { i in
                let a = Double(i) / 10 * 2 * Double.pi + Double.pi / 2
                return ContourNode(x: (i % 2 == 0 ? R : rr) * cos(a),
                                   y: (i % 2 == 0 ? R : rr) * sin(a))
            }
        case "样条曲线":
            let R = D / 2
            local = (0..<20).map { i in
                let a = Double(i) / 20 * 2 * Double.pi
                let r = R * (1 + 0.16 * sin(3 * a))
                return ContourNode(x: r * cos(a), y: r * sin(a))
            }
        case "槽":
            let r = W / 2, half = max(L / 2 - r, 0)
            for i in 0...6 {
                let a = -Double.pi / 2 + Double(i) / 6 * Double.pi
                local.append(ContourNode(x: half + r * cos(a), y: r * sin(a)))
            }
            for i in 0...6 {
                let a = Double.pi / 2 + Double(i) / 6 * Double.pi
                local.append(ContourNode(x: -half + r * cos(a), y: r * sin(a)))
            }
        case "平行四边形":
            let skew = W / 3
            local = [
                ContourNode(x: -L / 2 + skew, y: -W / 2),
                ContourNode(x: L / 2 + skew, y: -W / 2),
                ContourNode(x: L / 2 - skew, y: W / 2),
                ContourNode(x: -L / 2 - skew, y: W / 2)
            ]
        default:
            break
        }
        return local
    }

    private func placeTemplate(_ name: String, at loc: CGPoint, size: CGSize) {
        let b = sketchBBox()
        let k = sketchScale(b: b, size: size)
        var px = b.midX + (Double(loc.x) - Double(size.width) / 2) / k
        var py = b.midY - (Double(loc.y) - Double(size.height) / 2) / k
        if snapGrid, gridStep > 0.01 {
            px = round(px / gridStep) * gridStep
            py = round(py / gridStep) * gridStep
        }

        let local = templateLocalNodes(name,
                                       L: max(spec.rectL, 20),
                                       W: max(spec.rectW, 12),
                                       D: max(spec.circleD, 20),
                                       R: spec.rectR)
        guard local.count >= 3 else { return }
        lastShapeTool = name
        pushUndo()
        spec.constraints.removeAll()
        spec.nodes = local.map { ContourNode(x: $0.x + px, y: $0.y + py) }
        spec.template = .free
        selectedNode = nil
        showToastView("\(name) 已放在 X\(ncf(px)) Y\(ncf(py))")
        if !continuousDraw { sketchTool = "" }
    }

    private func makeEllipse() {
        let rx = max(spec.rectL, 20) / 2
        let ry = max(spec.rectW, 12) / 2
        spec.nodes = (0..<28).map { i in
            let a = Double(i) / 28 * 2 * Double.pi
            return ContourNode(x: rx * cos(a), y: ry * sin(a))
        }
        spec.template = .free
    }

    private func makePolygon(_ n: Int) {
        let r = max(spec.circleD, 20) / 2
        spec.nodes = (0..<n).map { i in
            let a = Double(i) / Double(n) * 2 * Double.pi + Double.pi / 2
            return ContourNode(x: r * cos(a), y: r * sin(a))
        }
        spec.template = .free
    }

    private func makeStar() {
        let R = max(spec.circleD, 20) / 2
        let r = R * 0.42
        spec.nodes = (0..<10).map { i in
            let a = Double(i) / 10 * 2 * Double.pi + Double.pi / 2
            let rr = i % 2 == 0 ? R : r
            return ContourNode(x: rr * cos(a), y: rr * sin(a))
        }
        spec.template = .free
    }

    private func makeParallelogram() {
        let L = max(spec.rectL, 20)
        let H = max(spec.rectW, 12)
        let skew = H / 3
        spec.nodes = [
            ContourNode(x: -L / 2 + skew, y: -H / 2),
            ContourNode(x: L / 2 + skew, y: -H / 2),
            ContourNode(x: L / 2 - skew, y: H / 2),
            ContourNode(x: -L / 2 - skew, y: H / 2)
        ]
        spec.template = .free
    }

    private func makeSpline() {
        let R = max(spec.circleD, 20) / 2
        spec.nodes = (0..<16).map { i in
            let a = Double(i) / 16 * 2 * Double.pi
            let rr = R * (1 + 0.16 * sin(3 * a))
            return ContourNode(x: rr * cos(a), y: rr * sin(a))
        }
        spec.template = .free
    }

    private func addInner(_ t: ContourTemplate) {
        pushUndo()
        let b = PartProg.bbox(spec)
        var l = SketchLoop(template: t)
        l.cx = Double(b.midX)
        l.cy = Double(b.midY)
        if t == .rect {
            l.rectL = min(30, max(8, Double(b.width) * 0.3))
            l.rectW = min(20, max(6, Double(b.height) * 0.3))
        } else {
            l.circleD = min(20, max(6, min(Double(b.width), Double(b.height)) * 0.25))
        }
        spec.innerLoops.append(l)
    }

    private func mirrorOuter() {
        if spec.template != .free { fillRectNodes() }
        for i in spec.nodes.indices { spec.nodes[i].x = -spec.nodes[i].x }
    }

    private func offsetOuter(_ d: Double) {
        if spec.template != .free { fillRectNodes() }
        let b = sketchBBox()
        for i in spec.nodes.indices {
            let dx = spec.nodes[i].x - b.midX
            let dy = spec.nodes[i].y - b.midY
            let len = max(hypot(dx, dy), 0.001)
            spec.nodes[i].x += dx / len * d
            spec.nodes[i].y += dy / len * d
        }
    }

    /// 外轮廓阵列：单实体不能出现多个独立外轮廓，所以把整圈外形复制成多个增料层。
    /// 每个副本是一层可继续编辑的凸台，能参与建模/刀路，不是只画在草图里的假预览。
    private func arrayOuterAsBosses(circular: Bool) {
        let baseShape = PartShape(spec)
        var copies: [PartStep] = []
        if circular {
            let n = max(2, arrayCount)
            for i in 1..<n {
                var s = PartStep()
                s.name = "外轮廓圆阵\(i + 1)"
                s.mode = .add
                s.z0 = 0
                s.height = 5
                s.shape = baseShape
                let a = Double(i) / Double(n) * 2 * Double.pi
                s.shape.cx = arrayRadius * cos(a)
                s.shape.cy = arrayRadius * sin(a)
                copies.append(s)
            }
        } else {
            let rows = max(1, arrayRows), cols = max(1, arrayCols)
            for r in 0..<rows {
                for c in 0..<cols where !(r == 0 && c == 0) {
                    var s = PartStep()
                    s.name = "外轮廓阵列\(r + 1)-\(c + 1)"
                    s.mode = .add
                    s.z0 = 0
                    s.height = 5
                    s.shape = baseShape
                    s.shape.cx = arrayDX * Double(c)
                    s.shape.cy = arrayDY * Double(r)
                    copies.append(s)
                }
            }
        }
        guard !copies.isEmpty else {
            showToastView("阵列行列/数量都为 1，没有可复制的轮廓")
            return
        }
        pushUndo()
        spec.steps.append(contentsOf: copies)
        modelPanel = .steps
        showToastView("已生成 \(copies.count) 个外轮廓增料层，可逐层改高度/轮廓")
    }

    private func arrayInner() {
        let base = spec.innerLoops
        guard !base.isEmpty else {
            showToastView("先加一个内圆/内方，再做线阵")
            return
        }
        pushUndo()
        for l in base {
            for r in 0..<max(arrayRows, 1) {
                for c in 0..<max(arrayCols, 1) {
                    if r == 0 && c == 0 { continue }
                    var n = l
                    n.id = UUID()
                    n.name = l.name + " 阵列\(r + 1)-\(c + 1)"
                    n.cx += arrayDX * Double(c)
                    n.cy += arrayDY * Double(r)
                    spec.innerLoops.append(n)
                }
            }
        }
    }

    // MARK: - 草图编辑算法

    private func outerPoints() -> [CGPoint] {
        var d = sketchDrawSpec()
        if d.template == .free && d.nodes.isEmpty { return [] }
        return ContourGeo.flatten(ContourGeo.segments(ContourGeo.buildNodes(d)))
    }

    private func setOuterPoints(_ pts: [CGPoint]) {
        spec.constraints.removeAll()
        spec.nodes = pts.map { ContourNode(x: Double($0.x), y: Double($0.y)) }
        spec.template = .free
    }

    private func trimLast() {
        spec.constraints.removeAll()
        if !spec.nodes.isEmpty {
            spec.nodes.removeLast()
        } else {
            let pts = outerPoints()
            if pts.count > 3 { setOuterPoints(Array(pts.dropLast())) }
        }
    }

    private func extendLast(_ d: Double) {
        if spec.template != .free { fillRectNodes() }
        guard spec.nodes.count >= 2 else { return }
        let a = spec.nodes[spec.nodes.count - 2]
        let b = spec.nodes[spec.nodes.count - 1]
        let len = hypot(b.x - a.x, b.y - a.y)
        guard len > 0.001 else { return }
        spec.nodes[spec.nodes.count - 1].x += (b.x - a.x) / len * d
        spec.nodes[spec.nodes.count - 1].y += (b.y - a.y) / len * d
    }

    private func breakLast() {
        if spec.template != .free { fillRectNodes() }
        guard spec.nodes.count >= 2 else { return }
        let a = spec.nodes[spec.nodes.count - 2]
        let b = spec.nodes[spec.nodes.count - 1]
        spec.nodes.insert(ContourNode(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), at: spec.nodes.count - 1)
    }

    private func addSketchConstraint(_ kind: SketchConstraintKind) {
        if spec.template != .free { fillRectNodes() }
        let n = spec.nodes.count
        guard n >= 3 else {
            showToastView("至少要有 3 个节点才能加约束")
            return
        }
        var c = SketchConstraint(kind: kind)
        let segA = selectedSegIndex
        let segB = selectedSegB
        switch kind {
        case .horizontal, .vertical:
            if let a = segA {
                c.a = a; c.b = (a + 1) % n
            } else {
                c.a = 0; c.b = n - 1
            }
        case .coincident:
            if let a = segA, let b = segB {
                c.a = a; c.b = (b + 1) % n
            } else {
                c.a = 0; c.b = n - 1
            }
        case .parallel, .perpendicular, .equal:
            if let a = segA, let b = segB, a != b {
                c.a = a; c.b = (a + 1) % n
                c.c = b; c.d = (b + 1) % n
            } else {
                guard n >= 3 else { return }
                c.a = max(0, n - 3); c.b = max(0, n - 2)
                c.c = max(0, n - 2); c.d = n - 1
            }
        case .midpoint:
            guard let i = selectedNode, i >= 0, i < n else {
                showToastView("先选一个节点，再加中点约束")
                return
            }
            c.a = i
        case .tangent:
            let idx = segA ?? (n - 1)
            guard spec.nodes[(idx + 1) % n].kind != .line else {
                showToastView("选中段不是圆弧：先把该段终点类型改成圆弧")
                return
            }
            c.a = idx
        case .concentric:
            guard !spec.innerLoops.isEmpty else {
                showToastView("先加内圆/内方，再加同心约束")
                return
            }
        }
        pushUndo()
        spec.constraints.append(c)
        solveSketchConstraints()
        let issues = constraintIssues
        showToastView(issues.isEmpty ? "已加约束：\(kind.rawValue)" : "已加约束：\(kind.rawValue)；存在冲突，请检查红色提示")
    }

    private func solveSketchConstraints() {
        guard spec.template == .free, spec.nodes.count >= 3 else { return }
        for _ in 0..<6 {
            for c in spec.constraints {
                applySketchConstraint(c)
            }
        }
    }

    private var autoConstraintTolerance: Double {
        max(0.2, min(1.5, gridStep * 0.15))
    }

    private func addAutoConstraint(_ kind: SketchConstraintKind, a: Int, b: Int,
                                   c: Int = 0, d: Int = 0) {
        let exists = spec.constraints.contains {
            $0.kind == kind && $0.a == a && $0.b == b && $0.c == c && $0.d == d
        }
        guard !exists else { return }
        spec.constraints.append(SketchConstraint(kind: kind, a: a, b: b, c: c, d: d))
    }

    /// 扫描当前自由轮廓：近水平/竖直的段自动拉正，闭合点自动加重合。
    private func autoConstrainSketch() {
        guard spec.template == .free, spec.nodes.count >= 3 else {
            showToastView("先画一个自由轮廓，再自动约束")
            return
        }
        pushUndo()
        let n = spec.nodes.count
        let tol = autoConstraintTolerance
        var added = 0
        for i in 0..<n {
            let j = (i + 1) % n
            let a = spec.nodes[i], b = spec.nodes[j]
            let dx = abs(b.x - a.x), dy = abs(b.y - a.y)
            if dy <= tol && dx > tol {
                spec.nodes[j].y = a.y
                addAutoConstraint(.horizontal, a: i, b: j)
                added += 1
            } else if dx <= tol && dy > tol {
                spec.nodes[j].x = a.x
                addAutoConstraint(.vertical, a: i, b: j)
                added += 1
            }
        }
        if n >= 4 {
            let f = spec.nodes[0], l = spec.nodes[n - 1]
            if hypot(f.x - l.x, f.y - l.y) <= tol * 2 {
                spec.nodes[n - 1].x = f.x
                spec.nodes[n - 1].y = f.y
                addAutoConstraint(.coincident, a: 0, b: n - 1)
                added += 1
            }
        }
        solveSketchConstraints()
        let issues = constraintIssues
        showToastView(added == 0
                      ? "没有发现可自动约束的水平/竖直/重合关系"
                      : "自动约束完成：新增 \(added) 条\(issues.isEmpty ? "" : "；有冲突请检查")")
    }

    private func applySketchConstraint(_ c: SketchConstraint) {
        let n = spec.nodes.count
        guard n >= 3 else { return }
        switch c.kind {
        case .horizontal:
            guard c.a < n, c.b < n else { return }
            spec.nodes[c.b].y = spec.nodes[c.a].y
        case .vertical:
            guard c.a < n, c.b < n else { return }
            spec.nodes[c.b].x = spec.nodes[c.a].x
        case .coincident:
            guard c.a < n, c.b < n else { return }
            spec.nodes[c.b].x = spec.nodes[c.a].x
            spec.nodes[c.b].y = spec.nodes[c.a].y
        case .parallel, .perpendicular:
            guard c.a < n, c.b < n, c.c < n, c.d < n else { return }
            let a = spec.nodes[c.a], b = spec.nodes[c.b]
            let cc = spec.nodes[c.c], d = spec.nodes[c.d]
            let ux = b.x - a.x, uy = b.y - a.y
            let vx = d.x - cc.x, vy = d.y - cc.y
            let lu = hypot(ux, uy), lv = hypot(vx, vy)
            guard lu > 1e-6, lv > 1e-6 else { return }
            let nx: Double, ny: Double
            if c.kind == .parallel {
                nx = ux / lu; ny = uy / lu
            } else {
                nx = -uy / lu; ny = ux / lu
            }
            spec.nodes[c.d].x = cc.x + nx * lv
            spec.nodes[c.d].y = cc.y + ny * lv
        case .equal:
            guard c.a < n, c.b < n, c.c < n, c.d < n else { return }
            let a = spec.nodes[c.a], b = spec.nodes[c.b]
            let cc = spec.nodes[c.c], d = spec.nodes[c.d]
            let ux = b.x - a.x, uy = b.y - a.y
            let vx = d.x - cc.x, vy = d.y - cc.y
            let lu = hypot(ux, uy), lv = hypot(vx, vy)
            guard lu > 1e-6, lv > 1e-6 else { return }
            spec.nodes[c.d].x = cc.x + vx / lv * lu
            spec.nodes[c.d].y = cc.y + vy / lv * lu
        case .midpoint:
            guard c.a < n else { return }
            let prev = spec.nodes[(c.a + n - 1) % n]
            let next = spec.nodes[(c.a + 1) % n]
            spec.nodes[c.a].x = (prev.x + next.x) / 2
            spec.nodes[c.a].y = (prev.y + next.y) / 2
        case .tangent:
            guard c.a < n, c.a >= 2 else { return }
            let i = c.a
            let p0 = spec.nodes[i - 1], p1 = spec.nodes[i]
            let seg = ContourSeg(p0: CGPoint(x: p0.x, y: p0.y),
                                 p1: CGPoint(x: p1.x, y: p1.y),
                                 kind: spec.nodes[i].kind,
                                 r: spec.nodes[i].r)
            let t = ContourGeo.tangent(seg)
            let d = hypot(Double(spec.nodes[i - 2].x - p0.x), Double(spec.nodes[i - 2].y - p0.y))
            guard d > 1e-6 else { return }
            spec.nodes[i - 2].x = p0.x - Double(t.x) * d
            spec.nodes[i - 2].y = p0.y - Double(t.y) * d
        case .concentric:
            let b = PartProg.bbox(spec)
            for i in spec.innerLoops.indices {
                spec.innerLoops[i].cx = Double(b.midX)
                spec.innerLoops[i].cy = Double(b.midY)
            }
        }
    }

    private func constraintTolerance(_ c: SketchConstraint) -> Double {
        switch c.kind {
        case .parallel, .perpendicular: return 0.02
        case .tangent: return 0.10
        default: return 0.05
        }
    }

    private func constraintResidual(_ c: SketchConstraint) -> Double {
        let n = spec.nodes.count
        guard n >= 3 else { return 0 }
        switch c.kind {
        case .horizontal:
            guard let first = spec.nodes.first else { return 0 }
            return spec.nodes.map { abs($0.y - first.y) }.max() ?? 0
        case .vertical:
            guard let first = spec.nodes.first else { return 0 }
            return spec.nodes.map { abs($0.x - first.x) }.max() ?? 0
        case .coincident:
            guard c.a < n, c.b < n else { return 0 }
            return hypot(Double(spec.nodes[c.a].x - spec.nodes[c.b].x),
                         Double(spec.nodes[c.a].y - spec.nodes[c.b].y))
        case .parallel, .perpendicular, .equal:
            guard c.a < n, c.b < n, c.c < n, c.d < n else { return 0 }
            let ux = spec.nodes[c.b].x - spec.nodes[c.a].x
            let uy = spec.nodes[c.b].y - spec.nodes[c.a].y
            let vx = spec.nodes[c.d].x - spec.nodes[c.c].x
            let vy = spec.nodes[c.d].y - spec.nodes[c.c].y
            let lu = hypot(ux, uy), lv = hypot(vx, vy)
            guard lu > 1e-6, lv > 1e-6 else { return 0 }
            if c.kind == .equal { return abs(lu - lv) }
            if c.kind == .parallel { return abs(ux * vy - uy * vx) / (lu * lv) }
            return abs(ux * vx + uy * vy) / (lu * lv)
        case .midpoint:
            guard c.a < n else { return 0 }
            let prev = spec.nodes[(c.a + n - 1) % n]
            let next = spec.nodes[(c.a + 1) % n]
            return hypot(Double(spec.nodes[c.a].x - (prev.x + next.x) / 2),
                         Double(spec.nodes[c.a].y - (prev.y + next.y) / 2))
        case .tangent:
            guard c.a < n, c.a >= 2 else { return 0 }
            let p0 = spec.nodes[c.a - 1], p1 = spec.nodes[c.a]
            let prev = spec.nodes[c.a - 2]
            let seg = ContourSeg(p0: CGPoint(x: p0.x, y: p0.y),
                                 p1: CGPoint(x: p1.x, y: p1.y),
                                 kind: spec.nodes[c.a].kind,
                                 r: spec.nodes[c.a].r)
            let t = ContourGeo.tangent(seg)
            let vx = prev.x - p0.x, vy = prev.y - p0.y
            let lv = hypot(vx, vy)
            guard lv > 1e-6 else { return 0 }
            return abs(vx * Double(t.y) - vy * Double(t.x))
        case .concentric:
            let b = PartProg.bbox(spec)
            return spec.innerLoops.map {
                hypot($0.cx - Double(b.midX), $0.cy - Double(b.midY))
            }.max() ?? 0
        }
    }

    private var constraintIssues: [String] {
        var out: [String] = []
        guard !spec.constraints.isEmpty else { return out }
        let hPairs = Set(spec.constraints.filter { $0.kind == .horizontal }
            .map { "\($0.a)-\($0.b)" })
        let vPairs = Set(spec.constraints.filter { $0.kind == .vertical }
            .map { "\($0.a)-\($0.b)" })
        if !hPairs.intersection(vPairs).isEmpty {
            out.append("过约束：同一段同时要求水平和竖直，轮廓会被压成一条线")
        }
        let pPairs = Set(spec.constraints.filter { $0.kind == .parallel }
            .map { "\($0.a)-\($0.b)-\($0.c)-\($0.d)" })
        let tPairs = Set(spec.constraints.filter { $0.kind == .perpendicular }
            .map { "\($0.a)-\($0.b)-\($0.c)-\($0.d)" })
        if !pPairs.intersection(tPairs).isEmpty {
            out.append("约束冲突：同两段同时要求平行和垂直")
        }
        var seen = Set<String>()
        for c in spec.constraints {
            let key = "\(c.kind.rawValue)-\(c.a)-\(c.b)-\(c.c)-\(c.d)"
            if !seen.insert(key).inserted {
                out.append("重复约束：\(c.label)，建议删除一条")
            }
        }
        for c in spec.constraints {
            let r = constraintResidual(c)
            if r > constraintTolerance(c) {
                out.append("约束未同时满足：\(c.label) 残差 \(ncf(r))")
            }
        }
        return Array(out.prefix(4))
    }

    private func constraintAnchor(_ c: SketchConstraint) -> (Double, Double)? {
        let n = spec.nodes.count
        guard n >= 3 else { return nil }
        switch c.kind {
        case .horizontal, .vertical:
            guard c.a < n, c.b < n, c.a != c.b else { return nil }
            let a = spec.nodes[c.a], b = spec.nodes[c.b]
            return ((a.x + b.x) / 2, (a.y + b.y) / 2)
        case .coincident:
            guard c.b < n else { return nil }
            return (spec.nodes[c.b].x, spec.nodes[c.b].y)
        case .parallel, .perpendicular, .equal:
            guard c.c < n, c.d < n else { return nil }
            return ((spec.nodes[c.c].x + spec.nodes[c.d].x) / 2,
                    (spec.nodes[c.c].y + spec.nodes[c.d].y) / 2)
        case .midpoint, .tangent:
            guard c.a < n else { return nil }
            return (spec.nodes[c.a].x, spec.nodes[c.a].y)
        case .concentric:
            if let l = spec.innerLoops.first { return (l.cx, l.cy) }
            let b = PartProg.bbox(spec)
            return (Double(b.midX), Double(b.midY))
        }
    }

    private func clearSketchConstraints() {
        guard !spec.constraints.isEmpty else { return }
        pushUndo()
        spec.constraints.removeAll()
        showToastView("已清空草图约束")
    }

    private func constrain(horizontal: Bool) {
        if spec.template != .free { fillRectNodes() }
        guard let f = spec.nodes.first else { return }
        for i in spec.nodes.indices {
            if horizontal { spec.nodes[i].y = f.y } else { spec.nodes[i].x = f.x }
        }
    }

    private func equalizeSegments() {
        if spec.template == .rect {
            spec.rectW = spec.rectL
            return
        }
        var pts = outerPoints()
        if pts.count > 3, let f = pts.first, let l = pts.last, hypot(f.x - l.x, f.y - l.y) < 0.01 {
            pts.removeLast()
        }
        guard pts.count >= 3 else { return }
        let n = pts.count
        var total = 0.0
        for i in 0..<n {
            let a = pts[i], b = pts[(i + 1) % n]
            total += hypot(Double(b.x - a.x), Double(b.y - a.y))
        }
        let avg = total / Double(n)
        var out = [pts[0]]
        for i in 0..<(n - 1) {
            let a = out[i]
            let b = pts[(i + 1) % n]
            let dx = Double(b.x - a.x), dy = Double(b.y - a.y)
            let len = hypot(dx, dy)
            guard len > 1e-6 else { continue }
            out.append(CGPoint(x: Double(a.x) + dx / len * avg,
                               y: Double(a.y) + dy / len * avg))
        }
        var nodes = out.map { ContourNode(x: Double($0.x), y: Double($0.y)) }
        let last = nodes[nodes.count - 1], first = nodes[0]
        let closing = hypot(Double(last.x - first.x), Double(last.y - first.y))
        if closing > 1e-6 {
            nodes.append(ContourNode(x: Double(first.x) + (Double(last.x - first.x)) / closing * avg,
                                     y: Double(first.y) + (Double(last.y - first.y)) / closing * avg))
        }
        if nodes.count >= 3 { spec.nodes = nodes; spec.template = .free }
    }

    private func snapLastToFirst() {
        if spec.template != .free { fillRectNodes() }
        guard spec.nodes.count > 2, let first = spec.nodes.first else { return }
        spec.nodes[spec.nodes.count - 1].x = first.x
        spec.nodes[spec.nodes.count - 1].y = first.y
        showToastView("末点已重合到起点")
    }

    private func centerSketch() {
        if spec.template != .free { fillRectNodes() }
        let b = sketchBBox()
        let cx = Double(b.midX), cy = Double(b.midY)
        for i in spec.nodes.indices {
            spec.nodes[i].x -= cx
            spec.nodes[i].y -= cy
        }
        for i in spec.innerLoops.indices {
            spec.innerLoops[i].cx -= cx
            spec.innerLoops[i].cy -= cy
        }
        for i in spec.feats.indices {
            spec.feats[i].x -= cx
            spec.feats[i].y -= cy
        }
        showToastView("轮廓已移到坐标中心")
    }

    /// 中点约束：把当前选中节点移到相邻两点的中点
    private func midpointConstraint() {
        if spec.template != .free { fillRectNodes() }
        let n = spec.nodes.count
        guard n >= 3 else {
            showToastView("至少要有 3 个节点才能做中点约束")
            return
        }
        guard let i = selectedNode, i >= 0, i < n else {
            showToastView("先在画布上选择一个节点，再点“中点”")
            return
        }
        let prev = spec.nodes[(i + n - 1) % n]
        let next = spec.nodes[(i + 1) % n]
        spec.nodes[i].x = (prev.x + next.x) / 2
        spec.nodes[i].y = (prev.y + next.y) / 2
        showToastView("节点 \(i + 1) 已移到相邻两点的中点")
    }

    /// 相切约束：调整相邻前一点，使进入圆弧前的那一段与圆弧相切
    private func tangentLastSegment() {
        if spec.template != .free { fillRectNodes() }
        let n = spec.nodes.count
        guard n >= 3 else {
            showToastView("至少要有 3 个点：前一点、圆弧起点、圆弧终点")
            return
        }
        let i = n - 1
        guard spec.nodes[i].kind != .line else {
            showToastView("末段不是圆弧：先把末点类型改成“圆弧 顺/逆”")
            return
        }
        let p0 = spec.nodes[i - 1], p1 = spec.nodes[i]
        let seg = ContourSeg(p0: CGPoint(x: p0.x, y: p0.y),
                             p1: CGPoint(x: p1.x, y: p1.y),
                             kind: spec.nodes[i].kind,
                             r: spec.nodes[i].r)
        let t = ContourGeo.tangent(seg)
        let d = hypot(Double(spec.nodes[i - 2].x - p0.x), Double(spec.nodes[i - 2].y - p0.y))
        guard d > 1e-6 else {
            showToastView("前一段太短，无法做相切")
            return
        }
        spec.nodes[i - 2].x = p0.x - Double(t.x) * d
        spec.nodes[i - 2].y = p0.y - Double(t.y) * d
        showToastView("已调整前一段，使其与末段圆弧相切")
    }

    private func makeParallel() {
        if spec.template != .free { fillRectNodes() }
        guard spec.nodes.count >= 3 else { return }
        let a = spec.nodes[spec.nodes.count - 3]
        let b = spec.nodes[spec.nodes.count - 2]
        let c = spec.nodes[spec.nodes.count - 1]
        let ux = b.x - a.x, uy = b.y - a.y
        let vx = c.x - b.x, vy = c.y - b.y
        let lu = hypot(ux, uy), lv = hypot(vx, vy)
        guard lu > 1e-6, lv > 1e-6 else { return }
        spec.nodes[spec.nodes.count - 1].x = b.x + ux / lu * lv
        spec.nodes[spec.nodes.count - 1].y = b.y + uy / lu * lv
        showToastView("末段已平行于前一段")
    }

    private func makePerpendicular() {
        if spec.template != .free { fillRectNodes() }
        guard spec.nodes.count >= 3 else { return }
        let a = spec.nodes[spec.nodes.count - 3]
        let b = spec.nodes[spec.nodes.count - 2]
        let c = spec.nodes[spec.nodes.count - 1]
        let ux = b.x - a.x, uy = b.y - a.y
        let vx = c.x - b.x, vy = c.y - b.y
        let lu = hypot(ux, uy), lv = hypot(vx, vy)
        guard lu > 1e-6, lv > 1e-6 else { return }
        spec.nodes[spec.nodes.count - 1].x = b.x - uy / lu * lv
        spec.nodes[spec.nodes.count - 1].y = b.y + ux / lu * lv
        showToastView("末段已垂直于前一段")
    }

    private func makeConcentric() {
        guard !spec.innerLoops.isEmpty else {
            showToastView("先加内圆/内方，再做同心")
            return
        }
        let b = PartProg.bbox(spec)
        for i in spec.innerLoops.indices {
            spec.innerLoops[i].cx = Double(b.midX)
            spec.innerLoops[i].cy = Double(b.midY)
        }
        showToastView("内轮廓已同心")
    }

    private func circularArrayInner() {
        let base = spec.innerLoops
        guard !base.isEmpty else {
            showToastView("先加一个内轮廓")
            return
        }
        pushUndo()
        let b = PartProg.bbox(spec)
        let cx = Double(b.midX), cy = Double(b.midY)
        for l in base {
            for i in 1..<max(arrayCount, 2) {
                let a = Double(i) / Double(max(arrayCount, 2)) * 2 * Double.pi
                var n = l
                n.id = UUID()
                n.name = l.name + " 圆阵\(i + 1)"
                n.cx = cx + arrayRadius * cos(a)
                n.cy = cy + arrayRadius * sin(a)
                spec.innerLoops.append(n)
            }
        }
    }

    private func regionTrim() {
        let pts = outerPoints()
        let x0 = min(trimX0, trimX1), x1 = max(trimX0, trimX1)
        let y0 = min(trimY0, trimY1), y1 = max(trimY0, trimY1)
        let kept = pts.filter { Double($0.x) < x0 || Double($0.x) > x1 || Double($0.y) < y0 || Double($0.y) > y1 }
        if kept.count >= 3 { setOuterPoints(kept) }
        else { showToastView("框选区域太大，修剪后不足 3 个点") }
    }

    private func moveOuter() {
        if spec.template != .free { fillRectNodes() }
        for i in spec.nodes.indices {
            spec.nodes[i].x += moveDX
            spec.nodes[i].y += moveDY
        }
        for i in spec.innerLoops.indices {
            spec.innerLoops[i].cx += moveDX
            spec.innerLoops[i].cy += moveDY
        }
        for i in spec.feats.indices {
            spec.feats[i].x += moveDX
            spec.feats[i].y += moveDY
        }
    }

    private func filletOuter(_ r: Double) {
        var pts = outerPoints()
        if pts.count > 3, let f = pts.first, let l = pts.last, hypot(f.x - l.x, f.y - l.y) < 0.01 {
            pts.removeLast()
        }
        guard pts.count >= 3, r > 0.01 else { return }
        let n = pts.count
        let area = ContourGeo.signedArea(pts)
        _ = area
        var nodes: [ContourNode] = []
        for i in 0..<n {
            let prev = pts[(i + n - 1) % n]
            let cur = pts[i]
            let next = pts[(i + 1) % n]
            let uin = norm(Double(prev.x - cur.x), Double(prev.y - cur.y))
            let uout = norm(Double(next.x - cur.x), Double(next.y - cur.y))
            guard uin.0 != 0 || uin.1 != 0, uout.0 != 0 || uout.1 != 0 else { continue }
            let dot = max(-1.0, min(1.0, uin.0 * uout.0 + uin.1 * uout.1))
            let theta = acos(dot)
            if theta < 0.05 || theta > 3.09 { continue }
            let tangent = r / tan(theta / 2)
            let e1 = hypot(Double(prev.x - cur.x), Double(prev.y - cur.y))
            let e2 = hypot(Double(next.x - cur.x), Double(next.y - cur.y))
            let d = min(tangent, min(e1, e2) * 0.45)
            let ax = Double(cur.x) + uin.0 * d
            let ay = Double(cur.y) + uin.1 * d
            let bx = Double(cur.x) + uout.0 * d
            let by = Double(cur.y) + uout.1 * d
            let cross = uin.0 * uout.1 - uin.1 * uout.0
            nodes.append(ContourNode(x: ax, y: ay, kind: .line, r: 0))
            nodes.append(ContourNode(x: bx, y: by, kind: cross < 0 ? .ccw : .cw, r: r))
        }
        if nodes.count >= 3 {
            spec.nodes = nodes
            spec.template = .free
        }
    }

    private func chamferOuter(_ c: Double) {
        var pts = outerPoints()
        if pts.count > 3, let f = pts.first, let l = pts.last, hypot(f.x - l.x, f.y - l.y) < 0.01 {
            pts.removeLast()
        }
        guard pts.count >= 3, c > 0.01 else { return }
        let n = pts.count
        var nodes: [ContourNode] = []
        for i in 0..<n {
            let prev = pts[(i + n - 1) % n]
            let cur = pts[i]
            let next = pts[(i + 1) % n]
            let uin = norm(Double(prev.x - cur.x), Double(prev.y - cur.y))
            let uout = norm(Double(next.x - cur.x), Double(next.y - cur.y))
            let e1 = hypot(Double(prev.x - cur.x), Double(prev.y - cur.y))
            let e2 = hypot(Double(next.x - cur.x), Double(next.y - cur.y))
            let d = min(c, min(e1, e2) * 0.45)
            nodes.append(ContourNode(x: Double(cur.x) + uin.0 * d, y: Double(cur.y) + uin.1 * d))
            nodes.append(ContourNode(x: Double(cur.x) + uout.0 * d, y: Double(cur.y) + uout.1 * d))
        }
        if nodes.count >= 3 {
            spec.nodes = nodes
            spec.template = .free
        }
    }

    private func threePointCircle() {
        guard refPoints.count >= 3 else { return }
        pushUndo()
        let a = refPoints[refPoints.count - 3]
        let b = refPoints[refPoints.count - 2]
        let c = refPoints[refPoints.count - 1]
        guard let circle = circleFrom(a, b, c) else { return }
        let n = 32
        spec.nodes = (0..<n).map { i in
            let ang = Double(i) / Double(n) * 2 * Double.pi
            return ContourNode(x: circle.0 + circle.2 * cos(ang), y: circle.1 + circle.2 * sin(ang))
        }
        spec.template = .free
    }

    private func threePointArc() {
        guard refPoints.count >= 3 else { return }
        pushUndo()
        let a = refPoints[refPoints.count - 3]
        let b = refPoints[refPoints.count - 2]
        let c = refPoints[refPoints.count - 1]
        guard let circle = circleFrom(a, b, c) else { return }
        let a0 = atan2(Double(a.y) - circle.1, Double(a.x) - circle.0)
        let am = atan2(Double(b.y) - circle.1, Double(b.x) - circle.0)
        let a1 = atan2(Double(c.y) - circle.1, Double(c.x) - circle.0)
        var sweep = a1 - a0
        while sweep <= -Double.pi { sweep += 2 * Double.pi }
        while sweep > Double.pi { sweep -= 2 * Double.pi }
        var mid = am - a0
        while mid <= -Double.pi { mid += 2 * Double.pi }
        while mid > Double.pi { mid -= 2 * Double.pi }
        if (sweep > 0) != (mid > 0) { sweep += sweep > 0 ? -2 * Double.pi : 2 * Double.pi }
        let n = 18
        spec.nodes = (0...n).map { i in
            let ang = a0 + sweep * Double(i) / Double(n)
            return ContourNode(x: circle.0 + circle.2 * cos(ang), y: circle.1 + circle.2 * sin(ang))
        }
        spec.template = .free
    }

    private func circleFrom(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> (Double, Double, Double)? {
        let ax = Double(a.x), ay = Double(a.y)
        let bx = Double(b.x), by = Double(b.y)
        let cx = Double(c.x), cy = Double(c.y)
        let d = 2 * (ax * (by - cy) + bx * (cy - ay) + cx * (ay - by))
        guard abs(d) > 1e-9 else { return nil }
        let ux = ((ax * ax + ay * ay) * (by - cy) + (bx * bx + by * by) * (cy - ay)
            + (cx * cx + cy * cy) * (ay - by)) / d
        let uy = ((ax * ax + ay * ay) * (cx - bx) + (bx * bx + by * by) * (ax - cx)
            + (cx * cx + cy * cy) * (bx - ax)) / d
        let r = hypot(ax - ux, ay - uy)
        return (ux, uy, r)
    }

    private func norm(_ x: Double, _ y: Double) -> (Double, Double) {
        let l = hypot(x, y)
        return l > 1e-9 ? (x / l, y / l) : (0, 0)
    }

    // MARK: - 2 建模

    private var modelPage: some View {
        ZStack(alignment: .topLeading) {
            GeometryReader { geo in
                Canvas { context, size in
                    drawModel(context: context, size: size)
                }
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            let travel = hypot(Double(g.translation.width), Double(g.translation.height))
                            guard travel > 3 else { return }
                            if viewPanMode {
                                panX += Double(g.translation.width - lastDrag.width)
                                panY += Double(g.translation.height - lastDrag.height)
                                lastDrag = g.translation
                                return
                            }
                            if tapOnModel && (modelFilter == .all || modelFilter == .feat) {
                                if dragFeatID == nil {
                                    let cam = modelCam(size: geo.size)
                                    var best = 40.0
                                    for f in spec.feats {
                                        let q = cam.p(f.x, f.y, PartProg.hostZ(spec, f))
                                        let d = hypot(Double(g.startLocation.x) - Double(q.x),
                                                      Double(g.startLocation.y) - Double(q.y))
                                        if d < best { best = d; dragFeatID = f.id }
                                    }
                                    if dragFeatID != nil { pushUndo() }
                                }
                                if let id = dragFeatID,
                                   let idx = spec.feats.firstIndex(where: { $0.id == id }) {
                                    let xy = modelXY(at: g.location, size: geo.size)
                                    spec.feats[idx].x = xy.0
                                    spec.feats[idx].y = xy.1
                                    hasPtr = true; ptrX = xy.0; ptrY = xy.1
                                    return
                                }
                            }
                            let dx = Double(g.translation.width - lastDrag.width)
                            let dy = Double(g.translation.height - lastDrag.height)
                            lastDrag = g.translation
                            yaw += dx * 0.012
                            let np = pitch - dy * 0.010
                            pitch = atan2(sin(np), cos(np))
                            modelViewName = "自由"
                        }
                        .onEnded { g in
                            let travel = hypot(Double(g.translation.width), Double(g.translation.height))
                            lastDrag = .zero
                            dragFeatID = nil
                            guard travel < 6 else { return }
                            let now = Date()
                            if now.timeIntervalSince(lastTapAt) < 0.35 {
                                lastTapAt = .distantPast
                                setView(0.78, 0.62)
                                showToastView("已回到等轴视角")
                                return
                            }
                            lastTapAt = now
                            if measureOn {
                                handleMeasureTap(at: g.location, size: geo.size)
                                return
                            }
                            if !tapOnModel && (modelFilter == .feat || modelFilter == .all) {
                                let cam = modelCam(size: geo.size)
                                var best = 32.0
                                var hit: PartFeat? = nil
                                for f in spec.feats {
                                    let q = cam.p(f.x, f.y, PartProg.hostZ(spec, f))
                                    let d = hypot(Double(g.location.x) - Double(q.x),
                                                  Double(g.location.y) - Double(q.y))
                                    if d < best { best = d; hit = f }
                                }
                                if let f = hit {
                                    selectedTreeID = "feat-\(f.id.uuidString)"
                                    modelPanel = .tree
                                    showToastView("已选中特征 \(f.kind.rawValue)，双击树可编辑")
                                    return
                                }
                            }
                            if !tapOnModel && modelFilter == .step {
                                let xy = modelXY(at: g.location, size: geo.size)
                                if let st = PartProg.stepAt(spec, xy.0, xy.1) {
                                    selectedTreeID = "step-\(st.id.uuidString)"
                                    modelPanel = .tree
                                    showToastView("已选中台阶 \(st.name)")
                                    return
                                }
                            }
                            if !tapOnModel && modelFilter == .sketch {
                                selectedTreeID = "sketch"
                                modelPanel = .tree
                                showToastView("已选中草图")
                                return
                            }
                            if let id = stepShapeEditID,
                               let idx = spec.steps.firstIndex(where: { $0.id == id }) {
                                var xy = modelXY(at: g.location, size: geo.size)
                                if snapGrid {
                                    xy.0 = (xy.0 / gridStep).rounded() * gridStep
                                    xy.1 = (xy.1 / gridStep).rounded() * gridStep
                                }
                                pushUndo()
                                spec.steps[idx].shape.template = .free
                                spec.steps[idx].shape.nodes.append(ContourNode(x: xy.0, y: xy.1))
                                spec.steps[idx].shape.cx = 0
                                spec.steps[idx].shape.cy = 0
                                ptrX = xy.0; ptrY = xy.1; hasPtr = true
                                showToastView("异形轮廓第 \(spec.steps[idx].shape.nodes.count) 点 X\(ncf(xy.0)) Y\(ncf(xy.1))")
                                return
                            }
                            guard tapOnModel else { return }
                            let xy = modelXY(at: g.location, size: geo.size)
                            ptrX = xy.0; ptrY = xy.1; hasPtr = true
                            showToastView("取点 X\(ncf(xy.0)) Y\(ncf(xy.1))")
                        }
                )
                .simultaneousGesture(MagnificationGesture()
                    .onChanged { v in zoom = min(3.0, max(0.4, zoomBase * Double(v))) }
                    .onEnded { _ in zoomBase = zoom }
                )
                .background(Color.white)
            }

            HStack(alignment: .top, spacing: 0) {
                modelLeftRail
                Spacer(minLength: 0)
                modelRightRail
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            if modelPanel == .none {
                viewCube
                    .padding(.trailing, 74)
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            VStack(spacing: 6) {
                Spacer()
                modelQuickBar
                modelBottomBar
            }

            if modelPanel != .none {
                HStack(alignment: .top, spacing: 0) {
                    modelPanelView
                    Spacer(minLength: 0)
                }
                .padding(.leading, 76)
                .padding(.top, 8)
            }

            if let id = stepShapeEditID,
               let idx = spec.steps.firstIndex(where: { $0.id == id }) {
                HStack(spacing: 8) {
                    Text("异形凸台：点模型顶面落点（\(spec.steps[idx].shape.nodes.count) 点）")
                        .font(.system(size: 10, weight: .semibold))
                    Button("撤销一点") {
                        if !spec.steps[idx].shape.nodes.isEmpty {
                            spec.steps[idx].shape.nodes.removeLast()
                        }
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .buttonStyle(.bordered)
                    Button("取消") { cancelStepShapeEdit() }
                        .font(.system(size: 10, weight: .semibold))
                        .buttonStyle(.bordered)
                    Button("完成") { finishStepShapeEdit() }
                        .font(.system(size: 10, weight: .bold))
                        .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 9).fill(.ultraThinMaterial))
                .padding(.top, 64)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    private var modelLeftRail: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 3) {
                railButton("草图", "pencil", active: false) {
                    if stepShapeEditID != nil { cancelStepShapeEdit() }
                    step = 0
                }
                railButton("拉伸", "arrow.up.right.square", active: modelPanel == .extrude) {
                    modelPanel = modelPanel == .extrude ? .none : .extrude
                }
                railButton("凸台", "square.stack.3d.up", active: modelPanel == .steps) {
                    modelPanel = modelPanel == .steps ? .none : .steps
                }
                railButton("孔", "circle.circle", active: false) {
                    beginFeat(.hole)
                }
                railButton("圆腔", "circle.dashed", active: false) {
                    beginFeat(.pocket)
                }
                railButton("方腔", "rectangle.dashed", active: false) {
                    beginFeat(.rectPocket)
                }
                railButton("更多", "square.grid.2x2", active: modelPanel == .tools) {
                    modelPanel = modelPanel == .tools ? .none : .tools
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
        }
        .frame(width: 62)
        .frame(maxHeight: 460)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 132))
        .overlay(RoundedRectangle(cornerRadius: 132).stroke(Color.white.opacity(0.85), lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }

    private var modelRightRail: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 3) {
                railButton("树", "list.bullet.indent", active: modelPanel == .tree) {
                    modelPanel = modelPanel == .tree ? .none : .tree
                }
                railButton("体", "cube", active: modelPanel == .body) {
                    modelPanel = modelPanel == .body ? .none : .body
                }
                railButton("剖切", "square.split.2x1", active: modelPanel == .section) {
                    modelPanel = modelPanel == .section ? .none : .section
                    if modelPanel == .section { sectionOn = true }
                }
                railButton("显示", "eye", active: modelPanel == .display) {
                    modelPanel = modelPanel == .display ? .none : .display
                }
                railButton("测量", "ruler", active: measureHost != nil) {
                    presentMeasureSheet()
                }
                railButton("适合", "arrow.up.left.and.arrow.down.right", active: false) {
                    setView(0.78, 0.62)
                    modelPanel = .none
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
        }
        .frame(width: 62)
        .frame(maxHeight: 460)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 132))
        .overlay(RoundedRectangle(cornerRadius: 132).stroke(Color.white.opacity(0.85), lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }

    private var viewCube: some View {
        VStack(spacing: 2) {
            Button { applyView("俯视", 0, 1.5) } label: {
                Text("顶").font(.system(size: 9, weight: .bold))
                    .frame(width: 44, height: 26)
                    .background(Color.white.opacity(0.85))
            }
            .buttonStyle(.plain)
            HStack(spacing: 2) {
                Button { applyView("正视", 0, 0) } label: {
                    Text("前").font(.system(size: 9, weight: .bold))
                        .frame(width: 22, height: 32)
                        .background(Color.white.opacity(0.85))
                }
                .buttonStyle(.plain)
                Button { applyView("右视", 1.5708, 0) } label: {
                    Text("右").font(.system(size: 9, weight: .bold))
                        .frame(width: 22, height: 32)
                        .background(Color(red: 0.78, green: 0.80, blue: 0.84))
                }
                .buttonStyle(.plain)
            }
            Text("视图").font(.system(size: 8)).foregroundStyle(.white)
                .frame(width: 44, height: 16)
                .background(studioBlue.opacity(0.85))
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.9), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
    }

    private var modelQuickBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                quickModelButton("方凸台", "square") {
                    addPrimitiveStep(.rect, mode: .add)
                }
                quickModelButton("圆凸台", "circle") {
                    addPrimitiveStep(.circle, mode: .add)
                }
                quickModelButton("方型腔", "square.dashed") {
                    addPrimitiveStep(.rect, mode: .cut)
                }
                quickModelButton("圆型腔", "circle.dashed") {
                    addPrimitiveStep(.circle, mode: .cut)
                }
                quickModelButton("异形", "scribble") {
                    addFreeformStep()
                }
                Menu {
                    Button("方板 120×80×20") { applyStarterTemplate(.rect) }
                    Button("圆板 Ø100×20") { applyStarterTemplate(.circle) }
                    Button("方板 + 圆凸台") { applyStarterTemplate(.rect, withCircleBoss: true) }
                    Button("圆板 + 方凸台") { applyStarterTemplate(.circle, withRectBoss: true) }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "square.grid.2x2")
                        Text("模板")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(studioBlue)
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(RoundedRectangle(cornerRadius: 10).fill(studioBlue.opacity(0.10)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 3)
    }

    private func quickModelButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 9)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.88)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.06), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var modelBottomBar: some View {
        HStack {
            Text("指针 X\(ncf(ptrX))  Y\(ncf(ptrY))  Z0")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            if sectionOn {
                Text("剖切 \(sectionAxis.rawValue) \(Int(sectionT * 100))%")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(studioBlue)
            }
            Spacer()
            Button {
                viewPanMode.toggle()
                lastDrag = .zero
                showToastView(viewPanMode ? "单指平移已开：拖动只移视图" : "单指旋转已开")
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "hand.draw")
                    Text("平移")
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(viewPanMode ? studioBlue : .secondary)
            }
            .buttonStyle(.plain)
            Text("过滤:\(modelFilter.rawValue)")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text("单指\(viewPanMode ? "平移" : "360°") · 双指缩放")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.72))
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private var modelPanelView: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(modelPanelTitle).font(.system(size: 16, weight: .bold))
                    Text(modelPanelSubtitle).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { modelPanel = .none } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color(.secondarySystemBackground)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 13)
            .padding(.top, 12)
            .padding(.bottom, 8)

            switch modelPanel {
            case .tree:
                modelTreePanel
            case .body:
                bodyPanel
            case .extrude:
                extrudePanel
            case .steps:
                stepsPanel
            case .section:
                sectionPanel
            case .measure:
                EmptyView()
            case .display:
                displayPanel
            case .tools:
                Form { modelControls }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color.white)
            case .none:
                EmptyView()
            }
        }
        .frame(width: 252)
        .frame(maxHeight: 570)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.97)))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white, lineWidth: 1))
        .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var modelPanelTitle: String {
        switch modelPanel {
        case .tree: return "建模树"
        case .body: return "体"
        case .extrude: return "拉伸"
        case .steps: return "凸台 / 台阶"
        case .section: return "剖切"
        case .measure: return "测量"
        case .display: return "显示"
        case .tools: return "建模工具"
        case .none: return ""
        }
    }

    private var modelPanelSubtitle: String {
        switch modelPanel {
        case .tree: return "\(treeItems.count) 项 · 可见/排序/编辑"
        case .body: return "实体属性 · 体积/重量/材料"
        case .extrude: return "由草图向下拉伸"
        case .steps: return "\(spec.steps.count) 层 · 独立 Z / 轮廓"
        case .section: return "X/Y/Z · 实时预览"
        case .measure: return "两点/两面距离 · 对象属性"
        case .display: return "视角与网格"
        case .tools: return "参数化特征"
        case .none: return ""
        }
    }

    // MARK: - Digit 式右侧上下文面板

    private var treeItems: [StudioTreeItem] {
        var out: [StudioTreeItem] = []
        out.append(StudioTreeItem(
            id: "sketch", index: 1, title: "草图 1",
            icon: "pencil",
            detail: "\(spec.template.rawValue) · \(spec.nodes.count) 个点",
            canMove: false, canDelete: false))
        for (i, s) in spec.steps.enumerated() {
            out.append(StudioTreeItem(
                id: "step-\(s.id.uuidString)", index: out.count + 1,
                title: s.name.isEmpty ? "台阶 \(i + 1)" : s.name,
                icon: "square.stack.3d.up",
                detail: "\(s.mode.rawValue) \(s.shape.summary) · Z\(ncf(s.drawBottom))~Z\(ncf(s.drawTop))",
                canMove: true, canDelete: true))
        }
        for (i, l) in spec.innerLoops.enumerated() {
            out.append(StudioTreeItem(
                id: "inner-\(l.id.uuidString)", index: out.count + 1,
                title: "草图内轮廓 \(i + 1)", icon: "pencil",
                detail: "\(l.name) · \(l.through ? "通" : "深\(ncf(l.depth))")",
                canMove: true, canDelete: true))
        }
        for (i, f) in spec.feats.enumerated() {
            out.append(StudioTreeItem(
                id: "feat-\(f.id.uuidString)", index: out.count + 1,
                title: f.name.isEmpty ? "\(f.kind.rawValue) \(i + 1)" : f.name,
                icon: f.kind == .hole ? "circle" : "square.dashed",
                detail: f.kind == .hole ? "Ø\(ncf(f.dia)) \(f.holeSummary)" : "\(ncf(f.w))×\(ncf(f.h)) 深\(ncf(f.depth))",
                canMove: true, canDelete: true, suppressed: f.suppressed))
        }
        out.append(StudioTreeItem(
            id: "extrude", index: out.count + 1, title: "拉伸",
            icon: "arrow.up.right.square",
            detail: "H \(ncf(spec.height)) mm\(spec.steps.isEmpty ? "" : " · \(spec.steps.count) 台阶")",
            canMove: false, canDelete: false))
        if treeFeatOnly {
            out = out.filter { $0.id.hasPrefix("feat-") }
            for i in out.indices { out[i].index = i + 1 }
        }
        return out
    }

    private var modelTreePanel: some View {
        VStack(spacing: 0) {
            TextField("工程名", text: $spec.projectName)
                .font(.system(size: 11, weight: .semibold))
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 10)
                .padding(.top, 6)
            HStack {
                Text("\(treeItems.count) 项")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button { treeFeatOnly.toggle() } label: {
                    Image(systemName: treeFeatOnly ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(treeFeatOnly ? studioBlue : .secondary)
                }
                .buttonStyle(.plain)
                Button { hiddenTreeIDs.removeAll() } label: {
                    Image(systemName: "eye")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 13)
            .padding(.bottom, 4)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(treeItems) { item in
                        HStack(spacing: 6) {
                            Image(systemName: item.suppressed ? "slash.circle" : item.icon)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(item.suppressed ? Color.red : (item.id == selectedTreeID ? studioBlue : Color.secondary))
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(item.index) · \(item.title)\(item.suppressed ? "（已抑制）" : "")")
                                    .font(.system(size: 12, weight: item.id == selectedTreeID ? .bold : .medium))
                                    .foregroundStyle(item.suppressed ? .secondary : .primary)
                                    .lineLimit(1)
                                Text(item.detail)
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 2)
                            Button { toggleTreeItem(item) } label: {
                                Image(systemName: hiddenTreeIDs.contains(item.id) ? "eye.slash" : "eye")
                                    .font(.system(size: 10))
                                    .frame(width: 20, height: 26)
                            }
                            .buttonStyle(.plain)
                            .opacity(item.id == "sketch" || item.id == "extrude" ? 0.35 : 1)
                            .disabled(item.id == "sketch" || item.id == "extrude")

                            Button { moveTreeItemUp(item) } label: {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 10))
                                    .frame(width: 20, height: 26)
                            }
                            .buttonStyle(.plain)
                            .opacity(item.canMove ? 1 : 0.25)
                            .disabled(!item.canMove)

                            Button { moveTreeItemDown(item) } label: {
                                Image(systemName: "arrow.down")
                                    .font(.system(size: 10))
                                    .frame(width: 20, height: 26)
                            }
                            .buttonStyle(.plain)
                            .opacity(item.canMove ? 1 : 0.25)
                            .disabled(!item.canMove)

                            Button { editTreeItem(item) } label: {
                                Image(systemName: "pencil")
                                    .font(.system(size: 10))
                                    .frame(width: 20, height: 26)
                            }
                            .buttonStyle(.plain)

                            Button { deleteTreeItem(item) } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 10))
                                    .frame(width: 20, height: 26)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(item.canDelete ? Color.red.opacity(0.8) : Color.secondary.opacity(0.3))
                            .disabled(!item.canDelete)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(item.id == selectedTreeID ? studioBlue.opacity(0.06) : Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { editTreeItem(item) }
                        .onTapGesture { selectedTreeID = item.id }
                        Divider().padding(.leading, 34)
                    }
                }
            }
            if selectedTreeID?.hasPrefix("feat-") == true {
                HStack(spacing: 6) {
                    Button("复制特征") { duplicateSelectedFeature() }
                    Button("线阵 \(arrayRows)×\(arrayCols)") { patternSelectedFeature() }
                }
                .font(.system(size: 10, weight: .semibold))
                .buttonStyle(.bordered)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
        }
        .frame(maxHeight: 500)
    }

    private func duplicateSelectedFeature() {
        guard let id = selectedTreeID, id.hasPrefix("feat-"),
              let f = spec.feats.first(where: { "feat-\($0.id.uuidString)" == id }) else {
            showToastView("先在树里选一个孔/腔特征")
            return
        }
        pushUndo()
        var n = f
        n.id = UUID()
        n.name = f.name.isEmpty ? "复制特征" : f.name + " 复制"
        n.x += 10
        spec.feats.append(n)
        showToastView("已复制特征，向右偏 10 mm")
    }

    private func patternSelectedFeature() {
        guard let id = selectedTreeID, id.hasPrefix("feat-"),
              let f = spec.feats.first(where: { "feat-\($0.id.uuidString)" == id }) else {
            showToastView("先在树里选一个孔/腔特征")
            return
        }
        let rows = max(1, arrayRows), cols = max(1, arrayCols)
        guard rows * cols > 1 else { showToastView("阵列行列数都为 1，没有可复制的特征"); return }
        pushUndo()
        for r in 0..<rows {
            for c in 0..<cols where !(r == 0 && c == 0) {
                var n = f
                n.id = UUID()
                n.name = (f.name.isEmpty ? "特征" : f.name) + " 阵列\(r + 1)-\(c + 1)"
                n.x += arrayDX * Double(c)
                n.y += arrayDY * Double(r)
                spec.feats.append(n)
            }
        }
        showToastView("已按 \(rows)×\(cols) 阵列特征")
    }

    private func toggleTreeItem(_ item: StudioTreeItem) {
        if hiddenTreeIDs.contains(item.id) {
            hiddenTreeIDs.remove(item.id)
        } else {
            hiddenTreeIDs.insert(item.id)
        }
    }

    private func moveTreeItemUp(_ item: StudioTreeItem) {
        if item.id.hasPrefix("inner-") {
            guard let idx = spec.innerLoops.firstIndex(where: { "inner-\($0.id.uuidString)" == item.id }),
                  idx > 0 else { return }
            pushUndo()
            spec.innerLoops.swapAt(idx, idx - 1)
        } else if item.id.hasPrefix("feat-") {
            guard let idx = spec.feats.firstIndex(where: { "feat-\($0.id.uuidString)" == item.id }),
                  idx > 0 else { return }
            pushUndo()
            spec.feats.swapAt(idx, idx - 1)
        } else if item.id.hasPrefix("step-") {
            guard let idx = spec.steps.firstIndex(where: { "step-\($0.id.uuidString)" == item.id }),
                  idx > 0 else { return }
            pushUndo()
            spec.steps.swapAt(idx, idx - 1)
        }
    }

    private func moveTreeItemDown(_ item: StudioTreeItem) {
        if item.id.hasPrefix("inner-") {
            guard let idx = spec.innerLoops.firstIndex(where: { "inner-\($0.id.uuidString)" == item.id }),
                  idx < spec.innerLoops.count - 1 else { return }
            pushUndo()
            spec.innerLoops.swapAt(idx, idx + 1)
        } else if item.id.hasPrefix("feat-") {
            guard let idx = spec.feats.firstIndex(where: { "feat-\($0.id.uuidString)" == item.id }),
                  idx < spec.feats.count - 1 else { return }
            pushUndo()
            spec.feats.swapAt(idx, idx + 1)
        } else if item.id.hasPrefix("step-") {
            guard let idx = spec.steps.firstIndex(where: { "step-\($0.id.uuidString)" == item.id }),
                  idx < spec.steps.count - 1 else { return }
            pushUndo()
            spec.steps.swapAt(idx, idx + 1)
        }
    }

    private func editTreeItem(_ item: StudioTreeItem) {
        selectedTreeID = item.id
        if item.id == "sketch" {
            step = 0
        } else if item.id == "extrude" {
            modelPanel = .extrude
        } else if item.id.hasPrefix("step-") {
            modelPanel = .steps
        } else if item.id.hasPrefix("feat-"),
                  let f = spec.feats.first(where: { "feat-\($0.id.uuidString)" == item.id }) {
            beginEditFeat(f)
        } else if item.id.hasPrefix("inner-") {
            step = 0
            sketchSidePanel = .params
            modelPanel = .none
            showToastView("内轮廓在草图页参数里编辑")
        } else {
            modelPanel = .tools
            showToastView("已选中 \(item.title)，参数在“建模工具”里")
        }
    }

    private func deleteTreeItem(_ item: StudioTreeItem) {
        if item.id.hasPrefix("inner-"),
           let id = UUID(uuidString: item.id.replacingOccurrences(of: "inner-", with: "")) {
            pushUndo()
            spec.innerLoops.removeAll { $0.id == id }
        } else if item.id.hasPrefix("feat-"),
                   let id = UUID(uuidString: item.id.replacingOccurrences(of: "feat-", with: "")) {
            pushUndo()
            spec.feats.removeAll { $0.id == id }
        } else if item.id.hasPrefix("step-"),
                   let id = UUID(uuidString: item.id.replacingOccurrences(of: "step-", with: "")) {
            pushUndo()
            spec.steps.removeAll { $0.id == id }
        }
        selectedTreeID = nil
    }

    private var extrudePanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 17))
                        .foregroundStyle(studioBlue)
                    Text("草图 1 → 实体").font(.system(size: 13, weight: .semibold))
                }
                numRow("厚度 H (mm)", $spec.height)
                numRow("顶面余量 (mm)", $spec.topStock)
                HStack {
                    Text("方向").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text("Z− 向下").font(.system(size: 11, weight: .bold)).foregroundStyle(studioBlue)
                }
                Text("外轮廓按草图闭合线拉伸；内圆/内方/孔/型腔是实体上的切除特征。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Button { modelPanel = .none } label: {
                    Text("应用并关闭").font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 9).fill(studioBlue))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 13)
            .padding(.bottom, 14)
        }
    }

    /// 进入“在模型上点异形凸台”的模式：点一下落一个点，至少 3 点自动闭合
    private func beginStepShapeEdit(_ id: UUID, clear: Bool) {
        guard let idx = spec.steps.firstIndex(where: { $0.id == id }) else { return }
        pushUndo()
        stepShapeEditBackup = spec.steps[idx].shape
        if clear {
            spec.steps[idx].shape = PartShape()
            spec.steps[idx].shape.template = .free
            spec.steps[idx].shape.nodes = []
        }
        spec.steps[idx].shape.template = .free
        spec.steps[idx].shape.cx = 0
        spec.steps[idx].shape.cy = 0
        stepShapeEditID = id
        step = 1
        modelPanel = .none
        showToastView("异形模式：在模型顶面依次点轮廓点，至少 3 点")
    }

    private func finishStepShapeEdit() {
        guard let id = stepShapeEditID,
              let idx = spec.steps.firstIndex(where: { $0.id == id }) else {
            stepShapeEditID = nil
            return
        }
        let n = spec.steps[idx].shape.nodes.count
        if n < 3 {
            showToastView("异形轮廓少于 3 点，先继续点")
            return
        }
        stepShapeEditID = nil
        stepShapeEditBackup = nil
        modelPanel = .steps
        showToastView("异形凸台已完成：\(n) 点")
    }

    /// 当前真正有材料的最高顶面；除料层的 z1 不能算进去
    private var topAddZ: Double {
        max(0, spec.steps.filter { $0.mode == .add }.map(\.z1).max() ?? 0)
    }

    /// 新凸台/异形的默认落料面：点在台阶上就叠在台阶顶面，否则回 XY 基准面 Z0。
    /// 避免连续点“方凸台 / 圆凸台”时第二个自动叠在第一个上面。
    private var addPlacementZ: Double {
        guard hasPtr else { return 0 }
        return PartProg.hostZ(spec, ptrX, ptrY)
    }

    /// 退出异形模式：恢复进入前的轮廓，避免点到一半退不出去
    private func cancelStepShapeEdit() {
        if let id = stepShapeEditID,
           let idx = spec.steps.firstIndex(where: { $0.id == id }),
           let backup = stepShapeEditBackup {
            spec.steps[idx].shape = backup
        }
        stepShapeEditID = nil
        stepShapeEditBackup = nil
        showToastView("已退出异形模式")
    }

    /// 直接从基本形状加一层凸台/型腔，不必先回草图重画
    private func addPrimitiveStep(_ template: ContourTemplate, mode: PartStepMode) {
        pushUndo()
        var s = PartStep()
        s.mode = mode
        s.height = mode == .add ? 5 : 3
        s.z0 = addPlacementZ
        s.shape.template = template
        switch template {
        case .circle:
            s.shape.circleD = min(max(spec.circleD > 1 ? spec.circleD : 80, 10), 2000)
        case .rect:
            s.shape.rectL = min(max(spec.rectL > 1 ? spec.rectL : 100, 10), 2000)
            s.shape.rectW = min(max(spec.rectW > 1 ? spec.rectW : 80, 10), 2000)
            s.shape.rectR = 0
        case .slot:
            s.shape.slotL = min(max(spec.slotL > 1 ? spec.slotL : 100, 10), 2000)
            s.shape.slotW = min(max(spec.slotW > 1 ? spec.slotW : 30, 2), 500)
        case .free: break
        }
        s.shape.cx = hasPtr ? ptrX : 0
        s.shape.cy = hasPtr ? ptrY : 0
        s.name = mode == .add
            ? (template == .circle ? "圆凸台" : "方凸台")
            : (template == .circle ? "圆型腔" : "方型腔")
        spec.steps.append(s)
        showToastView("已加\(s.name)：Z\(ncf(s.drawBottom))~\(ncf(s.drawTop))，可在这一行改尺寸/中心")
    }

    /// 直接加一个自由轮廓凸台，落点后马上进入“点模型画异形”模式
    private func addFreeformStep() {
        pushUndo()
        var s = PartStep()
        s.mode = .add
        s.height = 5
        s.z0 = addPlacementZ
        s.name = "异形凸台"
        s.shape = PartShape()
        s.shape.template = .free
        s.shape.nodes = []
        s.shape.cx = hasPtr ? ptrX : 0
        s.shape.cy = hasPtr ? ptrY : 0
        spec.steps.append(s)
        stepShapeEditBackup = s.shape
        stepShapeEditID = s.id
        step = 1
        modelPanel = .none
        showToastView("异形模式：在模型顶面依次点轮廓点，至少 3 点")
    }

    /// 一键铺一个可继续编辑的基础板，避免每次从空网格开始
    private func applyStarterTemplate(_ template: ContourTemplate,
                                      withCircleBoss: Bool = false,
                                      withRectBoss: Bool = false) {
        pushUndo()
        spec.template = template
        spec.nodes = []
        spec.innerLoops = []
        spec.feats = []
        spec.steps = []
        spec.height = 20
        if template == .rect {
            spec.rectL = 120
            spec.rectW = 80
            spec.rectR = 0
        } else {
            spec.circleD = 100
        }
        if withCircleBoss {
            var s = PartStep()
            s.name = "圆凸台"
            s.mode = .add
            s.z0 = 0
            s.height = 6
            s.shape.template = .circle
            s.shape.circleD = 40
            s.shape.cx = 0
            s.shape.cy = 0
            spec.steps.append(s)
        }
        if withRectBoss {
            var s = PartStep()
            s.name = "方凸台"
            s.mode = .add
            s.z0 = 0
            s.height = 6
            s.shape.template = .rect
            s.shape.rectL = 50
            s.shape.rectW = 30
            s.shape.rectR = 4
            s.shape.cx = 0
            s.shape.cy = 0
            spec.steps.append(s)
        }
        modelPanel = .steps
        showToastView("已铺\(template.rawValue)基础板；可继续点“方/圆凸台”往上加")
    }

    /// 凸台阵列：以当前层为种子复制，不改变原层
    private func patternStep(_ id: UUID, circular: Bool) {
        guard let base = spec.steps.first(where: { $0.id == id }) else { return }
        pushUndo()
        var copies: [PartStep] = []
        if circular {
            let n = max(2, arrayCount)
            for i in 1..<n {
                var c = base
                c.id = UUID()
                let a = Double(i) / Double(n) * 2 * Double.pi
                c.shape.cx = base.shape.cx + arrayRadius * cos(a)
                c.shape.cy = base.shape.cy + arrayRadius * sin(a)
                c.name = "\(base.name)-\(i + 1)"
                copies.append(c)
            }
        } else {
            let rows = max(1, arrayRows), cols = max(1, arrayCols)
            for r in 0..<rows {
                for c0 in 0..<cols where !(r == 0 && c0 == 0) {
                    var c = base
                    c.id = UUID()
                    c.shape.cx = base.shape.cx + arrayDX * Double(c0)
                    c.shape.cy = base.shape.cy + arrayDY * Double(r)
                    c.name = "\(base.name)-\(r * cols + c0 + 1)"
                    copies.append(c)
                }
            }
        }
        spec.steps.append(contentsOf: copies)
        showToastView("已阵列 \(copies.count) 个\(base.mode == .add ? "凸台" : "型腔")")
    }

    private var stepsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 17))
                        .foregroundStyle(studioBlue)
                    Text("基础层 + \(spec.steps.count) 个凸台/型腔")
                        .font(.system(size: 13, weight: .semibold))
                }

                DisclosureGroup("阵列参数（凸台用）") {
                    HStack(spacing: 6) {
                        Stepper("行 \(arrayRows)", value: $arrayRows, in: 1...8)
                        Stepper("列 \(arrayCols)", value: $arrayCols, in: 1...8)
                    }
                    HStack(spacing: 6) {
                        miniNum("DX", $arrayDX)
                        miniNum("DY", $arrayDY)
                    }
                    HStack(spacing: 6) {
                        Stepper("圆阵 \(arrayCount) 个", value: $arrayCount, in: 2...12)
                        miniNum("R", $arrayRadius)
                    }
                    .font(.system(size: 10))
                }
                .font(.system(size: 11, weight: .semibold))

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("基础层").font(.system(size: 12, weight: .semibold))
                        Text("草图外形 · Z \(ncf(-spec.height)) ~ 0")
                            .font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("当前草图").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(studioBlue)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(studioBlue.opacity(0.08)))

                if spec.steps.isEmpty {
                    Text("还没有凸台。下面可直接加圆/方凸台、圆/方型腔，或把当前草图做成一层。")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }

                ForEach($spec.steps) { $s in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            TextField("台阶名称", text: $s.name)
                                .font(.system(size: 12, weight: .semibold))
                                .textFieldStyle(.roundedBorder)
                            Picker("", selection: $s.mode) {
                                ForEach(PartStepMode.allCases) { m in Text(m.rawValue).tag(m) }
                            }
                            .labelsHidden()
                            .frame(width: 70)
                            Button {
                                pushUndo()
                                let id = s.id
                                spec.steps.removeAll { $0.id == id }
                            } label: {
                                Image(systemName: "trash").foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                        HStack(spacing: 6) {
                            miniNum(s.mode == .add ? "底 Z" : "顶 Z", $s.z0)
                            miniNum("厚", $s.height)
                            Text("Z \(ncf(s.drawBottom))~\(ncf(s.drawTop))")
                                .font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 6) {
                            miniNum("中心 X", $s.shape.cx)
                            miniNum("中心 Y", $s.shape.cy)
                            Button("居中") {
                                $s.shape.cx.wrappedValue = 0
                                $s.shape.cy.wrappedValue = 0
                            }
                                .font(.system(size: 9, weight: .semibold))
                                .buttonStyle(.bordered)
                        }
                        Picker("轮廓", selection: $s.shape.template) {
                            ForEach(ContourTemplate.allCases) { t in Text(t.rawValue).tag(t) }
                        }
                        .pickerStyle(.segmented)
                        switch s.shape.template {
                        case .rect:
                            HStack(spacing: 6) {
                                miniNum("长", $s.shape.rectL)
                                miniNum("宽", $s.shape.rectW)
                                miniNum("R", $s.shape.rectR)
                            }
                        case .circle:
                            miniNum("Ø", $s.shape.circleD)
                        case .slot:
                            HStack(spacing: 6) {
                                miniNum("总长", $s.shape.slotL)
                                miniNum("槽宽", $s.shape.slotW)
                            }
                        case .free:
                            Text("手画轮廓：\(s.shape.nodes.count) 段")
                                .font(.system(size: 9)).foregroundStyle(.secondary)
                            if !s.shape.nodes.isEmpty {
                                DisclosureGroup("异形节点微调") {
                                    ForEach($s.shape.nodes) { $n in
                                        HStack(spacing: 5) {
                                            Text("X").font(.system(size: 9)).foregroundStyle(.secondary)
                                            TextField("0", value: $n.x, format: .number)
                                                .font(.system(size: 11)).frame(width: 48)
                                            Text("Y").font(.system(size: 9)).foregroundStyle(.secondary)
                                            TextField("0", value: $n.y, format: .number)
                                                .font(.system(size: 11)).frame(width: 48)
                                            Button {
                                                let id = n.id
                                                $s.shape.nodes.wrappedValue.removeAll { $0.id == id }
                                            } label: {
                                                Image(systemName: "minus.circle").foregroundStyle(.red)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                .font(.system(size: 9))
                            }
                        }
                        HStack(spacing: 8) {
                            Button("模型点轮廓") {
                                beginStepShapeEdit(s.id, clear: s.shape.template != .free || s.shape.nodes.isEmpty)
                            }
                            .font(.system(size: 10, weight: .semibold))
                            Button("清空异形") {
                                pushUndo()
                                if let idx = spec.steps.firstIndex(where: { $0.id == s.id }) {
                                    spec.steps[idx].shape = PartShape()
                                    spec.steps[idx].shape.template = .free
                                    spec.steps[idx].shape.nodes = []
                                }
                                stepShapeEditID = s.id
                                showToastView("已清空：到建模画布点轮廓")
                            }
                            .font(.system(size: 10, weight: .semibold))
                        }
                        .buttonStyle(.bordered)

                        HStack(spacing: 8) {
                            Button("用当前草图更新") {
                                pushUndo()
                                if let idx = spec.steps.firstIndex(where: { $0.id == s.id }) {
                                    let cx = spec.steps[idx].shape.cx
                                    let cy = spec.steps[idx].shape.cy
                                    spec.steps[idx].shape = PartShape(spec)
                                    spec.steps[idx].shape.cx = cx
                                    spec.steps[idx].shape.cy = cy
                                }
                            }
                            .font(.system(size: 10, weight: .semibold))
                            Button("复制到草图") {
                                pushUndo()
                                // 用展平后的真实坐标，避免把偏置过的凸台复制回原点
                                let sp = PartProg.pts(s, spec)
                                spec.template = .free
                                spec.nodes = sp.map { ContourNode(x: Double($0.x), y: Double($0.y)) }
                                step = 0
                                showToastView("凸台轮廓已复制到草图，可继续编辑")
                            }
                            .font(.system(size: 10, weight: .semibold))
                        }
                        .buttonStyle(.bordered)

                        Menu {
                            Button("矩形阵列 \(arrayRows)×\(arrayCols)") {
                                patternStep(s.id, circular: false)
                            }
                            Button("圆形阵列 \(arrayCount) 个 R\(ncf(arrayRadius))") {
                                patternStep(s.id, circular: true)
                            }
                        } label: {
                            Label("阵列这个凸台", systemImage: "square.grid.3x3")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(9)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
                }

                HStack(spacing: 8) {
                    Button {
                        addPrimitiveStep(.circle, mode: .add)
                    } label: {
                        Label("加圆形凸台", systemImage: "circle")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                    }
                    .buttonStyle(.borderedProminent)
                    Button {
                        addPrimitiveStep(.rect, mode: .add)
                    } label: {
                        Label("加方形凸台", systemImage: "square")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                    }
                    .buttonStyle(.bordered)
                }

                HStack(spacing: 8) {
                    Button {
                        addPrimitiveStep(.circle, mode: .cut)
                    } label: {
                        Label("圆形型腔", systemImage: "circle.dashed")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    Button {
                        addPrimitiveStep(.rect, mode: .cut)
                    } label: {
                        Label("方形型腔", systemImage: "square.dashed")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    Button {
                        pushUndo()
                        var s = PartStep(from: spec)
                        s.name = "台阶 \(spec.steps.count + 1)"
                        s.z0 = addPlacementZ
                        s.height = 5
                        spec.steps.append(s)
                    } label: {
                        Label("用草图", systemImage: "square.on.square")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                }

                Text("说明：增料台阶会先出周边多刀粗加工、再出轮廓精加工；除料台阶按多刀清腔出粗加工。台阶上的孔/腔会按所在台阶自动取顶面 Z；整面飞面和复杂清角仍需补工步。")
                    .font(.system(size: 9)).foregroundStyle(.orange)
            }
            .padding(.horizontal, 13)
            .padding(.bottom, 14)
        }
    }

    private var bodyPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "cube.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(studioBlue)
                        .frame(width: 34, height: 34)
                        .background(RoundedRectangle(cornerRadius: 9).fill(studioBlue.opacity(0.10)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("体 1").font(.system(size: 14, weight: .bold))
                        Text("单一 2.5D 实体 · 由草图拉伸").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $bodyVisible).labelsHidden().tint(studioBlue)
                }

                Divider()

                metricCard("外形尺寸", "\(ncf(Double(partBBox.width))) × \(ncf(Double(partBBox.height))) × \(ncf(PartProg.maxZ(spec) - PartProg.minZ(spec))) mm")
                metricCard("体积", "\(ncf(partVolume)) mm³")
                metricCard("重量", "\(ncf(partWeight)) g（\(material.rawValue)）")
                metricCard("材料", material.rawValue)
                metricCard("特征", "\(spec.innerLoops.count) 内轮廓 · \(spec.feats.count) 孔/型腔")

                Picker("材料 / 实体外观", selection: $material) {
                    ForEach(StudioMaterial.allCases) { m in Text(m.rawValue).tag(m) }
                }
                .pickerStyle(.menu)
                Text("材料色同时用于建模实体着色；铝合金/钢/黄铜按金属明暗，ABS 按塑料。")
                    .font(.system(size: 9)).foregroundStyle(.secondary)

                HStack {
                    Button(bodyHighlight ? "取消高亮实体" : "高亮实体") {
                        bodyHighlight.toggle()
                        modelPanel = .none
                        showToastView(bodyHighlight ? "实体高亮已打开" : "实体高亮已关闭")
                    }
                    Spacer()
                    Button("适合窗口") { setView(0.78, 0.62); modelPanel = .none }
                }
                .buttonStyle(.bordered)
                .font(.system(size: 12, weight: .semibold))

                Text("工件坐标系在“加工”第 4 步里设置；这里只显示实体属性。")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 13)
            .padding(.bottom, 14)
        }
    }

    private var sectionPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("剖切", isOn: $sectionOn)
                    .tint(studioBlue)
                Picker("轴", selection: $sectionAxis) {
                    ForEach(SectionAxis.allCases) { a in Text(a.rawValue).tag(a) }
                }
                .pickerStyle(.segmented)
                HStack {
                    Text("位置").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text("\(Int(sectionT * 100))%")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(studioBlue)
                }
                Slider(value: $sectionT, in: 0.02...0.98)
                    .tint(studioBlue)
                Text("截面 Z = \(ncf(PartProg.maxZ(spec) - max(PartProg.maxZ(spec) - PartProg.minZ(spec), 0.2) * (sectionReverse ? (1 - sectionT) : sectionT)))")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button("反向") { sectionReverse.toggle() }
                        .buttonStyle(.bordered)
                    Button("重置") { sectionT = 0.45; sectionReverse = false }
                        .buttonStyle(.bordered)
                }
                .font(.system(size: 12, weight: .semibold))
                Toggle("手柄", isOn: $sectionHandles).tint(studioBlue)
                Toggle("截面线", isOn: $sectionLines).tint(studioBlue)
                Text(sectionAxis == .z
                     ? "Z 向按整个零件最高/最低 Z 剖切，多台阶、孔、型腔一起截断；橙色面为截面。"
                     : "X/Y 向显示完整高度范围的剖切平面；复杂曲面截面仍按 2.5D 近似。")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 13)
            .padding(.bottom, 14)
        }
    }

    private func distanceToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = Double(b.x - a.x), dy = Double(b.y - a.y)
        let l2 = dx * dx + dy * dy
        guard l2 > 1e-9 else { return hypot(Double(p.x - a.x), Double(p.y - a.y)) }
        let t = max(0, min(1, (Double(p.x - a.x) * dx + Double(p.y - a.y) * dy) / l2))
        let qx = Double(a.x) + dx * t, qy = Double(a.y) + dy * t
        return hypot(Double(p.x) - qx, Double(p.y) - qy)
    }

    private func activeSectionCutZ() -> Double? {
        guard sectionOn, sectionAxis == .z else { return nil }
        let zTop = PartProg.maxZ(spec)
        let zBottom = PartProg.minZ(spec)
        let span = max(zTop - zBottom, 0.2)
        return zTop - span * (sectionReverse ? (1 - sectionT) : sectionT)
    }

    /// 孔/腔/内轮廓的边界环；边拾取不能只认外轮廓，否则圆孔/圆腔只有基础 4 条边可选。
    private func featureRim(_ f: PartFeat) -> [CGPoint] {
        if f.kind == .rectPocket {
            let x0 = CGFloat(f.x - f.w / 2), x1 = CGFloat(f.x + f.w / 2)
            let y0 = CGFloat(f.y - f.h / 2), y1 = CGFloat(f.y + f.h / 2)
            return [CGPoint(x: x0, y: y0), CGPoint(x: x1, y: y0),
                    CGPoint(x: x1, y: y1), CGPoint(x: x0, y: y1)]
        }
        let topDia: Double = {
            switch f.resolvedHoleKind {
            case .counterbore: return f.resolvedCbDia
            case .countersink: return f.resolvedCsDia
            default: return f.dia
            }
        }()
        let cx = CGFloat(f.x), cy = CGFloat(f.y), r = CGFloat(max(topDia / 2, 0.1))
        return (0..<32).map { i in
            let a = Double(i) / 32 * 2 * Double.pi
            return CGPoint(x: cx + r * CGFloat(cos(a)), y: cy + r * CGFloat(sin(a)))
        }
    }

    private func edgeCandidates(_ cam: Cam, at loc: CGPoint) -> [(ModelPickEdge, Double)] {
        var out: [(ModelPickEdge, Double)] = []
        let cutZ = activeSectionCutZ()
        // 自由轮廓里的真实圆弧段也作为独立候选，带上 R
        if spec.template == .free {
            for (i, seg) in ContourGeo.segments(spec.nodes).enumerated()
                where seg.isArc && !seg.full && seg.r > 0.01 {
                let pa = cam.p(Double(seg.p0.x), Double(seg.p0.y), 0)
                let pb = cam.p(Double(seg.p1.x), Double(seg.p1.y), 0)
                let d = distanceToSegment(loc, pa, pb)
                out.append((ModelPickEdge(id: "arc-\(i)", a: seg.p0, b: seg.p1,
                                           z: 0, distance: d, arcR: seg.r), d))
            }
        }
        func scan(_ pts: [CGPoint], z: Double, prefix: String) {
            guard pts.count > 1 else { return }
            for i in pts.indices {
                let a = pts[i], b = pts[(i + 1) % pts.count]
                let pa = cam.p(Double(a.x), Double(a.y), z)
                let pb = cam.p(Double(b.x), Double(b.y), z)
                let d = distanceToSegment(loc, pa, pb)
                out.append((ModelPickEdge(id: "\(prefix)-\(i)", a: a, b: b, z: z, distance: d), d))
            }
        }
        func scanVertical(_ pts: [CGPoint], top: Double, bottom: Double, prefix: String) {
            guard top > bottom + 0.0001, pts.count > 1 else { return }
            for i in pts.indices {
                let p = pts[i]
                let pa = cam.p(Double(p.x), Double(p.y), top)
                let pb = cam.p(Double(p.x), Double(p.y), bottom)
                let d = distanceToSegment(loc, pa, pb)
                out.append((ModelPickEdge(id: "\(prefix)-v\(i)", a: p, b: p,
                                           z: top, z2: bottom, distance: d), d))
            }
        }
        scan(PartProg.pts(spec), z: 0, prefix: "base")
        let baseBottom = max(-spec.height, cutZ ?? -Double.greatestFiniteMagnitude)
        if 0 > baseBottom + 0.0001 {
            scanVertical(PartProg.pts(spec), top: 0, bottom: baseBottom, prefix: "base")
        }
        for s in spec.steps {
            scan(PartProg.pts(s, spec), z: s.drawTop, prefix: "step-\(s.id.uuidString)")
            let top = s.mode == .add ? s.z1 : s.drawTop
            let bottom0 = s.mode == .add ? s.z0 : s.drawBottom
            let bottom = max(bottom0, cutZ ?? -Double.greatestFiniteMagnitude)
            if top > bottom + 0.0001 {
                scanVertical(PartProg.pts(s, spec), top: top, bottom: bottom,
                             prefix: "step-\(s.id.uuidString)")
            }
        }
        // 孔 / 圆腔 / 方腔的边也要进入拾取候选，不能只有外轮廓的 4 条边。
        for f in spec.feats where !f.suppressed {
            let host = PartProg.hostZ(spec, f)
            let rim = featureRim(f)
            scan(rim, z: host, prefix: "feat-\(f.id.uuidString)")
            let bottom = f.kind == .hole ? PartProg.minZ(spec) : host - f.depth
            if host > bottom + 0.0001 {
                scan(rim, z: bottom, prefix: "feat-\(f.id.uuidString)-b")
                scanVertical(rim, top: host, bottom: bottom, prefix: "feat-\(f.id.uuidString)")
            }
        }
        // 草图内轮廓（内圆/内方/异形）同样可以作为边拾取。
        for l in spec.innerLoops {
            let host = PartProg.hostZ(spec, l.cx, l.cy)
            let rim = PartProg.loopPoints(l).map {
                CGPoint(x: $0.x + CGFloat(l.cx), y: $0.y + CGFloat(l.cy))
            }
            scan(rim, z: host, prefix: "loop-\(l.id.uuidString)")
            let bottom = l.through ? PartProg.minZ(spec) : host - l.depth
            if host > bottom + 0.0001 {
                scan(rim, z: bottom, prefix: "loop-\(l.id.uuidString)-b")
                scanVertical(rim, top: host, bottom: bottom, prefix: "loop-\(l.id.uuidString)")
            }
        }
        return out.sorted { $0.1 < $1.1 }
    }

    private func nearestEdge(_ cam: Cam, at loc: CGPoint) -> ModelPickEdge? {
        edgeCandidates(cam, at: loc).first(where: { $0.1 <= pickTolerance })?.0
    }

    private func holePolygon(_ cam: Cam, cx: Double, cy: Double, z: Double,
                             w: Double, h: Double, rect: Bool) -> [CGPoint] {
        if rect {
            let x0 = cx - w / 2, x1 = cx + w / 2
            let y0 = cy - h / 2, y1 = cy + h / 2
            return [cam.p(x0, y0, z), cam.p(x1, y0, z),
                    cam.p(x1, y1, z), cam.p(x0, y1, z)]
        }
        let r = max(max(w, h) / 2, 0.1)
        return (0..<20).map { i in
            let a = Double(i) / 20 * 2 * Double.pi
            return cam.p(cx + r * cos(a), cy + r * sin(a), z)
        }
    }

    /// 孔/腔中心到外轮廓的最近 2D 距离
    private func outerEdgeDistance(from h: ModelPickHole) -> Double {
        let pts = PartProg.pts(spec)
        guard pts.count > 1 else { return 0 }
        var best = Double.greatestFiniteMagnitude
        for i in 0..<pts.count {
            let a = pts[i], b = pts[(i + 1) % pts.count]
            let d = segmentDistance3D(
                (h.x, h.y, 0), (h.x, h.y, 0),
                (Double(a.x), Double(a.y), 0), (Double(b.x), Double(b.y), 0))
            best = min(best, d)
        }
        return best.isFinite ? best : 0
    }

    /// 当前圆到最近另一个圆的中心距/边间隙（只看孔、圆腔、圆形内轮廓）
    private func nearestOtherHole(from h: ModelPickHole) -> (name: String, center: Double, gap: Double)? {
        var best: (String, Double, Double, Double)? = nil
        func consider(_ id: String, _ name: String, _ x: Double, _ y: Double, _ dia: Double) {
            guard id != h.id else { return }
            let centerD = hypot(x - h.x, y - h.y)
            let gap = max(0, centerD - (h.dia / 2 + dia / 2))
            if best == nil || centerD < best!.1 {
                best = (name, centerD, gap, dia)
            }
        }
        for f in spec.feats where !f.suppressed {
            let d = f.kind == .rectPocket ? max(f.w, f.h) : f.dia
            consider("feat-\(f.id.uuidString)", f.name.isEmpty ? f.kind.rawValue : f.name, f.x, f.y, d)
        }
        for l in spec.innerLoops where l.template == .circle {
            consider("loop-\(l.id.uuidString)", l.name, l.cx, l.cy, l.circleD)
        }
        guard let b = best else { return nil }
        return (b.0, b.1, b.2)
    }

    /// 孔/腔底面的真实边界（模型坐标）
    private func holeBoundary(_ h: ModelPickHole) -> [ModelPickPoint] {
        let z = h.bottomZ
        if h.isPocket, h.w > 0, h.h > 0 {
            let x0 = h.x - h.w / 2, x1 = h.x + h.w / 2
            let y0 = h.y - h.h / 2, y1 = h.y + h.h / 2
            return [
                ModelPickPoint(x: x0, y: y0, z: z),
                ModelPickPoint(x: x1, y: y0, z: z),
                ModelPickPoint(x: x1, y: y1, z: z),
                ModelPickPoint(x: x0, y: y1, z: z)
            ]
        }
        let r = max(h.dia / 2, 0.1)
        return (0..<24).map { i in
            let a = Double(i) / 24 * 2 * Double.pi
            return ModelPickPoint(x: h.x + r * cos(a), y: h.y + r * sin(a), z: z)
        }
    }

    private func nearestHole(_ cam: Cam, at loc: CGPoint) -> ModelPickHole? {
        var best = Double.infinity
        var hit: ModelPickHole? = nil

        func consider(_ id: String, _ name: String, cx: Double, cy: Double,
                      host: Double, w: Double, h: Double, rect: Bool,
                      depth: Double, through: Bool, isPocket: Bool) {
            let bottomZ = through ? PartProg.minZ(spec) : host - depth
            let topPoly = holePolygon(cam, cx: cx, cy: cy, z: host, w: w, h: h, rect: rect)
            let bottomPoly = holePolygon(cam, cx: cx, cy: cy, z: bottomZ, w: w, h: h, rect: rect)
            let topCenter = cam.p(cx, cy, host)
            let bottomCenter = cam.p(cx, cy, bottomZ)
            let topD = hypot(Double(loc.x) - Double(topCenter.x), Double(loc.y) - Double(topCenter.y))
            let bottomD = hypot(Double(loc.x) - Double(bottomCenter.x), Double(loc.y) - Double(bottomCenter.y))
            let topHit = pointInScreenPolygon(loc, topPoly)
            let bottomHit = pointInScreenPolygon(loc, bottomPoly)
            let onBottom = bottomHit && (!topHit || bottomD < topD - 2)
            let d = onBottom ? bottomD : topD
            let chosenCenter = onBottom ? bottomCenter : topCenter
            let qEdge = cam.p(cx + max(w, h) / 2, cy, onBottom ? bottomZ : host)
            let screenRadius = abs(Double(qEdge.x - chosenCenter.x))
            let tol = min(max(pickTolerance, screenRadius * 0.6), 52)
            let qualifies = onBottom ? bottomHit : (topHit || topD < tol)
            guard qualifies, d < best else { return }
            best = d
            hit = ModelPickHole(id: id, name: name, x: cx, y: cy, z: host,
                                dia: max(w, h), depth: through ? 0 : depth,
                                through: through, isPocket: isPocket,
                                w: w, h: h, bottomZ: bottomZ, onBottom: onBottom)
        }

        for f in spec.feats where !f.suppressed {
            let host = PartProg.hostZ(spec, f)
            let w = f.kind == .rectPocket ? f.w : f.dia
            let h = f.kind == .rectPocket ? f.h : f.dia
            consider("feat-\(f.id.uuidString)",
                     f.name.isEmpty ? f.kind.rawValue : f.name,
                     cx: f.x, cy: f.y, host: host,
                     w: w, h: h, rect: f.kind == .rectPocket,
                     depth: f.depth, through: f.kind == .hole,
                     isPocket: f.kind != .hole)
        }
        for l in spec.innerLoops where l.template == .circle {
            let host = PartProg.hostZ(spec, l.cx, l.cy)
            consider("loop-\(l.id.uuidString)", l.name,
                     cx: l.cx, cy: l.cy, host: host,
                     w: l.circleD, h: l.circleD, rect: false,
                     depth: l.depth, through: l.through,
                     isPocket: false)
        }
        return hit
    }

    private func centroid(_ pts: [CGPoint]) -> CGPoint {
        guard !pts.isEmpty else { return .zero }
        let x = pts.reduce(0.0) { $0 + Double($1.x) } / Double(pts.count)
        let y = pts.reduce(0.0) { $0 + Double($1.y) } / Double(pts.count)
        return CGPoint(x: x, y: y)
    }

    private func pointInScreenPolygon(_ p: CGPoint, _ poly: [CGPoint]) -> Bool {
        guard poly.count >= 3 else { return false }
        var inside = false
        var j = poly.count - 1
        for i in poly.indices {
            let xi = poly[i].x, yi = poly[i].y
            let xj = poly[j].x, yj = poly[j].y
            if (yi > p.y) != (yj > p.y) {
                let x = (xj - xi) * (p.y - yi) / (yj - yi) + xi
                if p.x < x { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    private func faceAt(_ xy: (Double, Double), basePts: [CGPoint]) -> ModelPickFace? {
        var best: ModelPickFace? = nil
        if PartProg.pointIn(basePts, xy.0, xy.1) {
            best = ModelPickFace(id: "base-face", name: "基础顶面", z: 0,
                                 area: abs(ContourGeo.signedArea(basePts)),
                                 center: centroid(basePts),
                                 boundary: basePts.map { ModelPickPoint(x: Double($0.x), y: Double($0.y), z: 0) })
        }
        for s in spec.steps {
            let pts = PartProg.pts(s, spec)
            guard PartProg.pointIn(pts, xy.0, xy.1) else { continue }
            if best == nil || s.drawTop > best!.z {
                best = ModelPickFace(id: "step-\(s.id.uuidString)",
                                     name: "\(s.name) 顶面", z: s.drawTop,
                                     area: abs(ContourGeo.signedArea(pts)),
                                     center: centroid(pts),
                                     boundary: pts.map { ModelPickPoint(x: Double($0.x), y: Double($0.y), z: s.drawTop) })
            }
        }
        return best
    }

    private func baseBottomFaceAt(_ cam: Cam, at loc: CGPoint) -> ModelPickFace? {
        let cutZ = activeSectionCutZ()
        let bottom = max(-spec.height, cutZ ?? -Double.greatestFiniteMagnitude)
        guard bottom <= 0.0001, -spec.height <= bottom + 0.0001 else { return nil }
        // 基础底面按外轮廓投影判断，不用圆近似。
        let poly = PartProg.pts(spec).map { cam.p(Double($0.x), Double($0.y), bottom) }
        guard pointInScreenPolygon(loc, poly) else { return nil }
        let basePts = PartProg.pts(spec)
        return ModelPickFace(id: "base-bottom", name: "基础底面", z: bottom,
                             area: abs(ContourGeo.signedArea(basePts)),
                             center: centroid(basePts),
                             nx: 0, ny: 0, nz: -1,
                             boundary: basePts.map { ModelPickPoint(x: Double($0.x), y: Double($0.y), z: bottom) })
    }

    private func sideFaceAt(_ cam: Cam, at loc: CGPoint) -> ModelPickFace? {
        let cutZ = activeSectionCutZ()
        var best: (ModelPickFace, Double)? = nil
        func scan(_ ring: [CGPoint], top: Double, bottom: Double,
                  prefix: String, name: String) {
            guard ring.count > 1, top > bottom + 0.0001 else { return }
            for i in ring.indices {
                let a = ring[i], b = ring[(i + 1) % ring.count]
                let quad = [cam.p(Double(a.x), Double(a.y), top),
                            cam.p(Double(b.x), Double(b.y), top),
                            cam.p(Double(b.x), Double(b.y), bottom),
                            cam.p(Double(a.x), Double(a.y), bottom)]
                guard pointInScreenPolygon(loc, quad) else { continue }
                let mx = (Double(a.x) + Double(b.x)) / 2
                let my = (Double(a.y) + Double(b.y)) / 2
                let q = cam.p(mx, my, (top + bottom) / 2)
                let d = hypot(Double(loc.x) - Double(q.x), Double(loc.y) - Double(q.y))
                let len = max(hypot(Double(b.x - a.x), Double(b.y - a.y)), 1e-6)
                let nx = Double(b.y - a.y) / len
                let ny = -Double(b.x - a.x) / len
                let f = ModelPickFace(id: "\(prefix)-side\(i)", name: "\(name) \(i + 1)",
                                      z: (top + bottom) / 2,
                                      area: len * (top - bottom),
                                      center: CGPoint(x: mx, y: my),
                                      nx: nx, ny: ny, nz: 0,
                                      boundary: [
                                        ModelPickPoint(x: Double(a.x), y: Double(a.y), z: top),
                                        ModelPickPoint(x: Double(b.x), y: Double(b.y), z: top),
                                        ModelPickPoint(x: Double(b.x), y: Double(b.y), z: bottom),
                                        ModelPickPoint(x: Double(a.x), y: Double(a.y), z: bottom)
                                      ])
                if best == nil || d < best!.1 { best = (f, d) }
            }
        }
        let baseBottom = max(-spec.height, cutZ ?? -Double.greatestFiniteMagnitude)
        if 0 > baseBottom + 0.0001 {
            scan(PartProg.pts(spec), top: 0, bottom: baseBottom,
                 prefix: "base", name: "基础侧面")
        }
        for s in spec.steps {
            let top = s.mode == .add ? s.z1 : s.drawTop
            let bottom0 = s.mode == .add ? s.z0 : s.drawBottom
            let bottom = max(bottom0, cutZ ?? -Double.greatestFiniteMagnitude)
            if top > bottom + 0.0001 {
                scan(PartProg.pts(s, spec), top: top, bottom: bottom,
                     prefix: "step-\(s.id.uuidString)", name: "\(s.name) 侧面")
            }
        }
        return best?.0
    }

    private func closerFace(_ a: ModelPickFace?, _ b: ModelPickFace?, cam: Cam, at loc: CGPoint) -> ModelPickFace? {
        guard let a else { return b }
        guard let b else { return a }
        let qa = cam.p(Double(a.center.x), Double(a.center.y), a.z)
        let qb = cam.p(Double(b.center.x), Double(b.center.y), b.z)
        let da = hypot(Double(loc.x) - Double(qa.x), Double(loc.y) - Double(qa.y))
        let db = hypot(Double(loc.x) - Double(qb.x), Double(loc.y) - Double(qb.y))
        return da <= db ? a : b
    }

    /// 点测量：优先吸附到模型顶点/孔中心；没吸附到才用屏幕点反算。
    private func nearestModelPoint(_ cam: Cam, at loc: CGPoint, basePts: [CGPoint]) -> ModelPickPoint? {
        var best: (ModelPickPoint, Double)? = nil
        func consider(_ x: Double, _ y: Double, _ z: Double) {
            let q = cam.p(x, y, z)
            let d = hypot(Double(loc.x) - Double(q.x), Double(loc.y) - Double(q.y))
            if best == nil || d < best!.1 { best = (ModelPickPoint(x: x, y: y, z: z), d) }
        }
        for p in basePts {
            consider(Double(p.x), Double(p.y), 0)
            consider(Double(p.x), Double(p.y), -spec.height)
        }
        for s in spec.steps {
            let pts = PartProg.pts(s, spec)
            let top = s.mode == .add ? s.z1 : s.drawTop
            let bottom = s.mode == .add ? s.z0 : s.drawBottom
            for p in pts {
                consider(Double(p.x), Double(p.y), top)
                consider(Double(p.x), Double(p.y), bottom)
            }
        }
        for f in spec.feats where !f.suppressed {
            let host = PartProg.hostZ(spec, f)
            consider(f.x, f.y, host)
            consider(f.x, f.y, f.kind == .hole ? PartProg.minZ(spec) : host - f.depth)
        }
        for l in spec.innerLoops where l.template == .circle {
            let host = PartProg.hostZ(spec, l.cx, l.cy)
            consider(l.cx, l.cy, host)
            consider(l.cx, l.cy, l.through ? PartProg.minZ(spec) : host - l.depth)
        }
        guard let best, best.1 <= max(pickTolerance, 14) else { return nil }
        return best.0
    }

    private func faceMeasure(_ a: ModelPickFace, _ b: ModelPickFace)
        -> (distance: Double, center: Double, parallel: Bool,
            dx: Double, dy: Double, dz: Double) {
        func unit(_ x: Double, _ y: Double, _ z: Double) -> (Double, Double, Double) {
            let l = max(sqrt(x * x + y * y + z * z), 1e-9)
            return (x / l, y / l, z / l)
        }
        let n1 = unit(a.nx, a.ny, a.nz)
        let n2 = unit(b.nx, b.ny, b.nz)
        let dot = n1.0 * n2.0 + n1.1 * n2.1 + n1.2 * n2.2
        let dx = Double(b.center.x - a.center.x)
        let dy = Double(b.center.y - a.center.y)
        let dz = b.z - a.z
        let center = sqrt(dx * dx + dy * dy + dz * dz)
        let plane = abs(dx * n1.0 + dy * n1.1 + dz * n1.2)
        let parallel = abs(abs(dot) - 1) < 0.02
        return (parallel ? plane : center, center, parallel, dx, dy, dz)
    }

    private func clearMeasurePicks() {
        pickedPoints = []
        pickedEdges = []
        pickedFaces = []
        pickedHole = nil
        measurePickHint = "点/边/面：连续点两个对象测距离；体/复合：看属性"
    }

    private func handleMeasureTap(at loc: CGPoint, size: CGSize) {
        let cam = modelCam(size: size)
        let xy = modelXY(at: loc, size: size)
        let basePts = PartProg.pts(spec)
        let candidates = edgeCandidates(cam, at: loc)
        let edge = candidates.first(where: { $0.1 <= pickTolerance })?.0
        let topFace = faceAt(xy, basePts: basePts)
        let bottomFace = baseBottomFaceAt(cam, at: loc)
        let sideFace = sideFaceAt(cam, at: loc)
        var face = closerFace(sideFace, closerFace(topFace, bottomFace, cam: cam, at: loc),
                              cam: cam, at: loc)
        let hole = nearestHole(cam, at: loc)
        if measureTarget == .face, let h = hole, h.onBottom {
            let area = h.isPocket && h.w > 0 ? h.w * h.h : Double.pi * pow(h.dia / 2, 2)
            face = ModelPickFace(id: h.id + "-bottom", name: h.name + " 底面",
                                 z: h.bottomZ, area: area,
                                 center: CGPoint(x: h.x, y: h.y),
                                 boundary: holeBoundary(h))
        }
        let z = (hole?.onBottom == true ? hole?.bottomZ : hole?.z) ?? face?.z ?? 0

        if calibratingPick {
            calibrationSample = PickCalibration(
                point: loc,
                nearestEdge: candidates.first?.0,
                edgeDistances: Array(candidates.prefix(3)).map { $0.1 },
                hole: hole,
                face: face)
            if let d = calibrationSample?.edgeDistances.first {
                let second = calibrationSample!.edgeDistances.count > 1
                    ? ncf(calibrationSample!.edgeDistances[1]) : "无"
                measurePickHint = "校准：最近边 \(ncf(d)) pt；第二近 \(second) pt"
            } else {
                measurePickHint = "校准：当前容差内没有边；可调大拾取半径或放大视图"
            }
            return
        }
        switch measureTarget {
        case .edge:
            guard let edge else {
                measurePickHint = "没有拾取到边：点靠近外轮廓/台阶上沿"
                showToastView("未拾取到边")
                return
            }
            if pickedEdges.count >= 2 { pickedEdges = [] }
            pickedEdges.append(edge)
            pickedFaces = []; pickedHole = nil
            let nearOther = edgeIsAmbiguous(cam, at: loc)
            measurePickHint = pickedEdges.count == 1 ? "边1 已拾取；再点第二条边测最短距离" : "两条边已拾取"
            if nearOther { measurePickHint += "；附近边较近，放大后再点更稳" }
            showToastView("已拾取边")
        case .face:
            guard let face else {
                measurePickHint = "没有拾取到面：点在外轮廓/台阶顶面内部"
                showToastView("未拾取到面")
                return
            }
            if pickedFaces.count >= 2 { pickedFaces = [] }
            pickedFaces.append(face)
            pickedEdges = []; pickedHole = nil
            measurePickHint = pickedFaces.count == 1
                ? "面1 已拾取：\(face.name)；再点第二个面测距"
                : "两面已拾取；上面显示距离"
            showToastView("已拾取面")
        case .point:
            let p = nearestModelPoint(cam, at: loc, basePts: basePts)
                    ?? ModelPickPoint(x: xy.0, y: xy.1, z: z)
            if pickedPoints.count >= 2 { pickedPoints = [] }
            pickedPoints.append(p)
            pickedEdges = []; pickedFaces = []; pickedHole = nil
            measurePickHint = pickedPoints.count == 1
                ? "点1 已拾取 X\(ncf(p.x)) Y\(ncf(p.y)) Z\(ncf(p.z))；再点第二个点"
                : "两点已拾取；上面显示距离"
            showToastView("已拾取点")
        case .pointFace:
            if pickedPoints.isEmpty {
                let p = nearestModelPoint(cam, at: loc, basePts: basePts)
                        ?? ModelPickPoint(x: xy.0, y: xy.1, z: z)
                pickedPoints = [p]
                pickedFaces = []; pickedHole = nil
                measurePickHint = "点已拾取 X\(ncf(p.x)) Y\(ncf(p.y)) Z\(ncf(p.z))；再点一个面"
                showToastView("已拾取点")
            } else if pickedFaces.isEmpty {
                guard let face else {
                    measurePickHint = "没有拾取到面：点在外轮廓/台阶顶面内部"
                    showToastView("未拾取到面")
                    return
                }
                pickedFaces = [face]
                pickedHole = nil
                measurePickHint = "点-面已拾取；上面显示点到面的距离"
                showToastView("已拾取面")
            } else {
                pickedPoints = []; pickedFaces = []
                measurePickHint = "点/面已清空；重新点一个点"
            }
        case .pointEdge:
            if pickedPoints.isEmpty {
                let p = nearestModelPoint(cam, at: loc, basePts: basePts)
                        ?? ModelPickPoint(x: xy.0, y: xy.1, z: z)
                pickedPoints = [p]
                pickedEdges = []; pickedFaces = []; pickedHole = nil
                measurePickHint = "点已拾取 X\(ncf(p.x)) Y\(ncf(p.y)) Z\(ncf(p.z))；再点一条边"
                showToastView("已拾取点")
            } else if pickedEdges.isEmpty {
                guard let edge else {
                    measurePickHint = "没有拾取到边：点靠近外轮廓/台阶上沿"
                    showToastView("未拾取到边")
                    return
                }
                pickedEdges = [edge]
                pickedFaces = []; pickedHole = nil
                measurePickHint = "点-边已拾取；上面显示点到边的最短距离"
                showToastView("已拾取边")
            } else {
                pickedPoints = []; pickedEdges = []
                measurePickHint = "点/边已清空；重新点一个点"
            }
        case .edgeFace:
            if pickedEdges.isEmpty {
                guard let edge else {
                    measurePickHint = "没有拾取到边：点靠近外轮廓/台阶上沿"
                    showToastView("未拾取到边")
                    return
                }
                pickedEdges = [edge]
                pickedPoints = []; pickedFaces = []; pickedHole = nil
                measurePickHint = "边已拾取；再点一个面"
                showToastView("已拾取边")
            } else if pickedFaces.isEmpty {
                guard let face else {
                    measurePickHint = "没有拾取到面：点在外轮廓/台阶顶面内部"
                    showToastView("未拾取到面")
                    return
                }
                pickedFaces = [face]
                pickedPoints = []; pickedHole = nil
                measurePickHint = "边-面已拾取；上面显示边到面所在平面的距离"
                showToastView("已拾取面")
            } else {
                pickedEdges = []; pickedFaces = []
                measurePickHint = "边/面已清空；重新点一条边"
            }
        case .circle:
            if let h = hole, (!h.isPocket || abs(h.w - h.h) < 0.01) {
                pickedHole = h
                pickedPoints = []; pickedEdges = []; pickedFaces = []
                measurePickHint = "圆已拾取 Ø\(ncf(h.dia))；结果区显示半径 R\(ncf(h.dia / 2))"
                showToastView("已拾取圆")
            } else if spec.template == .circle {
                let c = centroid(basePts)
                let h = ModelPickHole(id: "base-circle", name: "基础圆",
                                      x: Double(c.x), y: Double(c.y), z: 0,
                                      dia: spec.circleD, depth: 0, through: true,
                                      isPocket: false, w: spec.circleD, h: spec.circleD,
                                      bottomZ: PartProg.minZ(spec), onBottom: false)
                pickedHole = h
                pickedPoints = []; pickedEdges = []; pickedFaces = []
                measurePickHint = "基础圆 Ø\(ncf(h.dia))；结果区显示半径 R\(ncf(h.dia / 2))"
                showToastView("已拾取基础圆")
            } else {
                measurePickHint = "没有拾取到圆：点圆孔、圆腔或圆形内轮廓"
                showToastView("未拾取到圆")
            }
        case .angle:
            let p = nearestModelPoint(cam, at: loc, basePts: basePts)
                    ?? ModelPickPoint(x: xy.0, y: xy.1, z: z)
            if pickedPoints.count >= 3 { pickedPoints = [] }
            pickedPoints.append(p)
            pickedEdges = []; pickedFaces = []; pickedHole = nil
            measurePickHint = pickedPoints.count < 3
                ? "角点\(pickedPoints.count) 已拾取；再点\(3 - pickedPoints.count)个点（建议按顶点→拐点→顶点）"
                : "三点已拾取；上面显示夹角"
            showToastView("已拾取角点")
        case .body, .compound:
            if let hole {
                pickedHole = hole
                pickedEdges = []; pickedFaces = []
                measurePickHint = "孔/腔已拾取：\(hole.name)"
                showToastView("已拾取孔/腔")
            } else if let face {
                pickedFaces = [face]
                pickedEdges = []; pickedHole = nil
                measurePickHint = "面已拾取：\(face.name)"
                showToastView("已拾取面")
            } else if let edge {
                if pickedEdges.count >= 2 { pickedEdges = [] }
                pickedEdges.append(edge)
                pickedFaces = []; pickedHole = nil
                let nearOther = edgeIsAmbiguous(cam, at: loc)
                measurePickHint = nearOther ? "边已拾取；附近边较近，放大后再点更稳" : "边已拾取"
                showToastView("已拾取边")
            } else {
                measurePickHint = "未拾取到实体对象"
            }
        }
    }

    private func edgeLength(_ e: ModelPickEdge) -> Double {
        let dx = Double(e.b.x - e.a.x)
        let dy = Double(e.b.y - e.a.y)
        let dz = e.zEnd - e.z
        let chord = sqrt(dx * dx + dy * dy + dz * dz)
        if e.arcR > 0.01 {
            let ratio = min(1, chord / (2 * e.arcR))
            return 2 * e.arcR * asin(ratio)
        }
        return chord
    }

    private func midpoint(_ e: ModelPickEdge) -> (Double, Double, Double) {
        (Double(e.a.x + e.b.x) / 2, Double(e.a.y + e.b.y) / 2, (e.z + e.zEnd) / 2)
    }

    private func dot3(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        a.0 * b.0 + a.1 * b.1 + a.2 * b.2
    }

    private func sub3(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> (Double, Double, Double) {
        (a.0 - b.0, a.1 - b.1, a.2 - b.2)
    }

    private func len3(_ a: (Double, Double, Double)) -> Double {
        sqrt(dot3(a, a))
    }

    private func cross3(_ a: (Double, Double, Double),
                        _ b: (Double, Double, Double)) -> (Double, Double, Double) {
        (a.1 * b.2 - a.2 * b.1,
         a.2 * b.0 - a.0 * b.2,
         a.0 * b.1 - a.1 * b.0)
    }

    private func add3(_ a: (Double, Double, Double), _ b: (Double, Double, Double), _ s: Double = 1) -> (Double, Double, Double) {
        (a.0 + b.0 * s, a.1 + b.1 * s, a.2 + b.2 * s)
    }

    private func clamp01(_ v: Double) -> Double { max(0, min(1, v)) }

    /// 两条 3D 线段之间的最短距离（Ericson 线段-线段最近点算法）
    private func segmentDistance3D(_ p1: (Double, Double, Double), _ p2: (Double, Double, Double),
                                   _ q1: (Double, Double, Double), _ q2: (Double, Double, Double)) -> Double {
        let d1 = sub3(p2, p1), d2 = sub3(q2, q1), r = sub3(p1, q1)
        let a = dot3(d1, d1), e = dot3(d2, d2), f = dot3(d2, r)
        var s = 0.0, t = 0.0
        if a <= 1e-9, e <= 1e-9 { return len3(sub3(p1, q1)) }
        if a <= 1e-9 {
            t = clamp01(f / e)
        } else {
            let c = dot3(d1, r)
            if e <= 1e-9 {
                s = clamp01(-c / a)
            } else {
                let b = dot3(d1, d2)
                let denom = a * e - b * b
                s = denom > 1e-9 ? clamp01((b * f - c * e) / denom) : 0
                t = (b * s + f) / e
                if t < 0 {
                    t = 0; s = clamp01(-c / a)
                } else if t > 1 {
                    t = 1; s = clamp01((b - c) / a)
                }
            }
        }
        let c1 = add3(p1, d1, s)
        let c2 = add3(q1, d2, t)
        return len3(sub3(c1, c2))
    }

    private func edgeGap(_ a: ModelPickEdge, _ b: ModelPickEdge) -> Double {
        segmentDistance3D(
            (Double(a.a.x), Double(a.a.y), a.z),
            (Double(a.b.x), Double(a.b.y), a.zEnd),
            (Double(b.a.x), Double(b.a.y), b.z),
            (Double(b.b.x), Double(b.b.y), b.zEnd))
    }

    /// 点到线段的最短距离（3D，线段退化为点时也能算）
    private func pointEdgeGap(_ p: ModelPickPoint, _ e: ModelPickEdge) -> Double {
        segmentDistance3D(
            (p.x, p.y, p.z), (p.x, p.y, p.z),
            (Double(e.a.x), Double(e.a.y), e.z),
            (Double(e.b.x), Double(e.b.y), e.zEnd))
    }

    private func faceNormal(_ f: ModelPickFace) -> (Double, Double, Double) {
        let l = max(sqrt(f.nx * f.nx + f.ny * f.ny + f.nz * f.nz), 1e-9)
        return (f.nx / l, f.ny / l, f.nz / l)
    }

    /// 以面边界第一条边为 u 轴，建立面内的二维坐标；没有边界时返回 nil。
    private func faceBasis(_ f: ModelPickFace)
        -> (n: (Double, Double, Double), u: (Double, Double, Double),
           v: (Double, Double, Double), origin: (Double, Double, Double))? {
        guard f.boundary.count >= 3 else { return nil }
        let n = faceNormal(f)
        let p0 = (f.boundary[0].x, f.boundary[0].y, f.boundary[0].z)
        let p1 = (f.boundary[1].x, f.boundary[1].y, f.boundary[1].z)
        let e = sub3(p1, p0)
        let el = len3(e)
        guard el > 1e-9 else { return nil }
        let u = (e.0 / el, e.1 / el, e.2 / el)
        let v = cross3(n, u)
        return (n, u, v, p0)
    }

    private func pointInFaceBoundary(_ p: (Double, Double, Double),
                                     _ f: ModelPickFace,
                                     _ basis: (n: (Double, Double, Double),
                                               u: (Double, Double, Double),
                                               v: (Double, Double, Double),
                                               origin: (Double, Double, Double))?) -> Bool {
        guard f.boundary.count >= 3, let basis else { return true }
        let rel = sub3(p, basis.origin)
        let q = CGPoint(x: CGFloat(dot3(rel, basis.u)), y: CGFloat(dot3(rel, basis.v)))
        let poly = f.boundary.map { pt -> CGPoint in
            let r = (pt.x - basis.origin.0, pt.y - basis.origin.1, pt.z - basis.origin.2)
            return CGPoint(x: CGFloat(dot3(r, basis.u)), y: CGFloat(dot3(r, basis.v)))
        }
        return pointInScreenPolygon(q, poly)
    }

    /// 点到面的最短距离：优先用真实边界；没有边界才退回无限平面。
    private func pointFaceGap(_ p: ModelPickPoint, _ f: ModelPickFace)
        -> (distance: Double, finite: Bool) {
        let n = faceNormal(f)
        let delta = (p.x - Double(f.center.x), p.y - Double(f.center.y), p.z - f.z)
        let signed = dot3(delta, n)
        let planeD = abs(signed)
        let basis = faceBasis(f)
        guard f.boundary.count >= 3, let basis else { return (planeD, false) }
        let proj = (p.x - n.0 * signed, p.y - n.1 * signed, p.z - n.2 * signed)
        if pointInFaceBoundary(proj, f, basis) { return (planeD, true) }
        var best = Double.greatestFiniteMagnitude
        for i in f.boundary.indices {
            let a = f.boundary[i]
            let b = f.boundary[(i + 1) % f.boundary.count]
            let d = segmentDistance3D(
                (p.x, p.y, p.z), (p.x, p.y, p.z),
                (a.x, a.y, a.z), (b.x, b.y, b.z))
            best = min(best, d)
        }
        return (best.isFinite ? best : planeD, true)
    }

    /// 边到面（有限边界）的最短距离；没有边界时退回面所在平面。
    private func edgeFaceGap(_ e: ModelPickEdge, _ f: ModelPickFace)
        -> (distance: Double, crosses: Bool, finite: Bool) {
        let n = faceNormal(f)
        let a = (Double(e.a.x), Double(e.a.y), e.z)
        let b = (Double(e.b.x), Double(e.b.y), e.zEnd)
        let c = (Double(f.center.x), Double(f.center.y), f.z)
        let da = dot3(sub3(a, c), n)
        let db = dot3(sub3(b, c), n)
        let crosses = da * db <= 0
        guard f.boundary.count >= 3, let basis = faceBasis(f) else {
            return (crosses ? 0 : min(abs(da), abs(db)), crosses, false)
        }
        if crosses {
            let denom = da - db
            if abs(denom) > 1e-9 {
                let t = da / denom
                let hit = add3(a, sub3(b, a), t)
                if pointInFaceBoundary(hit, f, basis) { return (0, true, true) }
            }
        }
        var best = Double.greatestFiniteMagnitude
        let pa = (a.0 - n.0 * da, a.1 - n.1 * da, a.2 - n.2 * da)
        let pb = (b.0 - n.0 * db, b.1 - n.1 * db, b.2 - n.2 * db)
        if pointInFaceBoundary(pa, f, basis) { best = min(best, abs(da)) }
        if pointInFaceBoundary(pb, f, basis) { best = min(best, abs(db)) }
        for i in f.boundary.indices {
            let q1 = f.boundary[i]
            let q2 = f.boundary[(i + 1) % f.boundary.count]
            let d = segmentDistance3D(a, b, (q1.x, q1.y, q1.z), (q2.x, q2.y, q2.z))
            best = min(best, d)
        }
        if !best.isFinite { best = min(abs(da), abs(db)) }
        return (best, false, true)
    }

    private func edgeIsAmbiguous(_ cam: Cam, at loc: CGPoint) -> Bool {
        let ds = edgeCandidates(cam, at: loc).map { $0.1 }.filter { $0 <= pickTolerance }
        return ds.count > 1 && ds[1] - ds[0] < 3
    }

    private var toleranceLabel: String {
        let v = pickTolerance.isFinite ? pickTolerance : 22
        return String(format: "%.0f pt", min(max(v, 12), 40))
    }

    private func defaultTolerance(for target: MeasureTarget) -> Double {
        switch target {
        case .point: return 18
        case .edge: return 16
        case .angle: return 18
        case .face, .pointFace, .pointEdge, .edgeFace, .circle, .body, .compound: return 22
        }
    }

    private func toleranceKey(for target: MeasureTarget) -> String {
        "measureTolerance.\(target.rawValue)"
    }

    private func storedTolerance(for target: MeasureTarget) -> Double {
        let fallback = defaultTolerance(for: target)
        let v = UserDefaults.standard.object(forKey: toleranceKey(for: target)) as? Double ?? fallback
        return v.isFinite ? min(max(v, 12), 40) : fallback
    }

    private func storeTolerance(_ value: Double, for target: MeasureTarget) {
        UserDefaults.standard.set(min(max(value, 12), 40), forKey: toleranceKey(for: target))
    }

    private var measureTargetBinding: Binding<MeasureTarget> {
        Binding(
            get: { measureTarget },
            set: { newTarget in
                pickToleranceByTarget[measureTarget.rawValue] = pickTolerance
                storeTolerance(pickTolerance, for: measureTarget)
                measureTarget = newTarget
                clearMeasurePicks()
                let saved = pickToleranceByTarget[newTarget.rawValue] ?? storedTolerance(for: newTarget)
                pickTolerance = min(max(saved, 12), 40)
            })
    }

    private func adjustTolerance(_ delta: Double) {
        let v = pickTolerance.isFinite ? pickTolerance : defaultTolerance(for: measureTarget)
        setTolerance(min(max(v + delta, 12), 40))
    }

    private func setTolerance(_ value: Double) {
        let v = value.isFinite ? min(max(value, 12), 40) : defaultTolerance(for: measureTarget)
        pickTolerance = v
        pickToleranceByTarget[measureTarget.rawValue] = v
        storeTolerance(v, for: measureTarget)
    }

    private func resetTolerance() {
        setTolerance(defaultTolerance(for: measureTarget))
    }

    private func topViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return nil }
        var vc = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        while let p = vc?.presentedViewController { vc = p }
        return vc
    }

    private func presentMeasureSheet() {
        guard measureHost == nil, let top = topViewController() else { return }
        measureOn = true
        modelPanel = .none
        let host = UIHostingController(rootView: AnyView(measureSheet))
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.layer.cornerRadius = 18
        host.view.layer.shadowColor = UIColor.black.cgColor
        host.view.layer.shadowOpacity = 0.18
        host.view.layer.shadowRadius = 18
        host.view.layer.shadowOffset = CGSize(width: 0, height: 8)
        top.addChild(host)
        top.view.addSubview(host.view)
        let width = min(320, max(270, top.view.bounds.width * 0.78))
        let height = min(560, max(380, top.view.bounds.height * 0.72))
        NSLayoutConstraint.activate([
            host.view.trailingAnchor.constraint(equalTo: top.view.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            host.view.topAnchor.constraint(equalTo: top.view.safeAreaLayoutGuide.topAnchor, constant: 86),
            host.view.widthAnchor.constraint(equalToConstant: width),
            host.view.heightAnchor.constraint(equalToConstant: height)
        ])
        host.didMove(toParent: top)
        measureHost = host
    }

    private func dismissMeasureSheet() {
        guard let host = measureHost else { return }
        host.willMove(toParent: nil)
        host.view.removeFromSuperview()
        host.removeFromParent()
        measureHost = nil
    }

    private var measureSheet: some View {
        NavigationStack {
            Form {
                Section("测量目标") {
                    Picker("目标", selection: measureTargetBinding) {
                        ForEach(MeasureTarget.allCases) { t in
                            Label(t.rawValue, systemImage: t.icon).tag(t)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("拾取半径") {
                    HStack {
                        Text("当前 · \(measureTarget.rawValue)")
                        Spacer()
                        Text(toleranceLabel).font(.system(size: 13, weight: .bold)).foregroundStyle(studioBlue)
                    }
                    HStack(spacing: 10) {
                        Button("−2") { adjustTolerance(-2) }
                            .buttonStyle(.bordered)
                        Button("+2") { adjustTolerance(2) }
                            .buttonStyle(.bordered)
                        Spacer()
                        Button("重置") { resetTolerance() }
                            .buttonStyle(.borderless)
                    }
                    Text("边/孔太难点就调大；点错相邻边就调小。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }

                Section("拾取校准") {
                    Toggle("拾取校准模式", isOn: $calibratingPick)
                    if calibratingPick {
                        Text("打开测量后，在模型上点一下，下面显示该点到最近边、第二近边、孔和面的屏幕距离。")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        if let sample = calibrationSample {
                            LabeledContent("最近边", value: sample.edgeDistances.first.map { "\(ncf($0)) pt" } ?? "未命中")
                            if sample.edgeDistances.count > 1 {
                                LabeledContent("第二近边", value: "\(ncf(sample.edgeDistances[1])) pt")
                                    .foregroundStyle(sample.edgeDistances[1] - sample.edgeDistances[0] < 3 ? Color.red : Color.secondary)
                            }
                            if let h = sample.hole {
                                LabeledContent("孔/腔", value: h.name)
                            }
                            if let f = sample.face {
                                LabeledContent("面", value: "\(f.name) · Z\(ncf(f.z))")
                            }
                            if let first = sample.edgeDistances.first {
                                Button("按当前命中设容差 \(Int(max(12, min(40, first + 4)))) pt") {
                                    setTolerance(max(12, min(40, first + 4)))
                                }
                            }
                        } else {
                            Text("还没有校准样本，去画布上点一下。").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Text(measurePickHint).font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                        Button("清空") { clearMeasurePicks() }
                    }
                }

                Section("显示") {
                    Toggle("显示测量框", isOn: $measureOn)
                    Picker("材料", selection: $material) {
                        ForEach(StudioMaterial.allCases) { m in Text(m.rawValue).tag(m) }
                    }
                }

                Section("结果") {
                    if measureTarget == .angle, pickedPoints.count >= 3 {
                        let a = pickedPoints[0], b = pickedPoints[1], c = pickedPoints[2]
                        let u = (a.x - b.x, a.y - b.y, a.z - b.z)
                        let v = (c.x - b.x, c.y - b.y, c.z - b.z)
                        let lu = sqrt(u.0 * u.0 + u.1 * u.1 + u.2 * u.2)
                        let lv = sqrt(v.0 * v.0 + v.1 * v.1 + v.2 * v.2)
                        if lu > 1e-9, lv > 1e-9 {
                            let cosA = max(-1, min(1, (u.0 * v.0 + u.1 * v.1 + u.2 * v.2) / (lu * lv)))
                            LabeledContent("三点夹角", value: "\(ncf(acos(cosA) * 180 / .pi))°")
                            LabeledContent("两边长度", value: "\(ncf(lu)) / \(ncf(lv)) mm")
                        }
                    }
                    if measureTarget == .pointFace, let p = pickedPoints.first,
                       let f = pickedFaces.first {
                        let dz = p.z - f.z
                        let planar = hypot(p.x - Double(f.center.x), p.y - Double(f.center.y))
                        let shortest = pointFaceGap(p, f)
                        LabeledContent("点-面最短距离", value: "\(ncf(shortest.distance)) mm")
                        Text(shortest.finite ? "按面的有限边界计算。" : "没有面边界，按无限平面计算。")
                            .font(.system(size: 9)).foregroundStyle(shortest.finite ? Color.secondary : Color.orange)
                        LabeledContent("点-面 Z 向距离", value: "\(ncf(abs(dz))) mm")
                        LabeledContent("点-面 XY 偏移", value: "\(ncf(planar)) mm")
                        LabeledContent("点投影到面", value: "X\(ncf(p.x)) Y\(ncf(p.y)) Z\(ncf(f.z))")
                    }
                    if measureTarget == .pointEdge, let p = pickedPoints.first, let e = pickedEdges.first {
                        LabeledContent("点-边最短距离", value: "\(ncf(pointEdgeGap(p, e))) mm")
                        LabeledContent("边长度", value: "\(ncf(edgeLength(e))) mm")
                        LabeledContent("点坐标", value: "X\(ncf(p.x)) Y\(ncf(p.y)) Z\(ncf(p.z))")
                        LabeledContent("边端点", value: "(X\(ncf(Double(e.a.x))) Y\(ncf(Double(e.a.y))) Z\(ncf(e.z))) → (X\(ncf(Double(e.b.x))) Y\(ncf(Double(e.b.y))) Z\(ncf(e.zEnd)))")
                    }
                    if measureTarget == .edgeFace, let e = pickedEdges.first, let f = pickedFaces.first {
                        let m = edgeFaceGap(e, f)
                        LabeledContent(m.finite ? "边-面最短距离" : "边-面平面距离", value: "\(ncf(m.distance)) mm")
                        if m.crosses {
                            Text("边穿过该面，距离按 0 处理。")
                                .font(.system(size: 9)).foregroundStyle(.orange)
                        } else {
                            Text(m.finite ? "按面的有限边界计算。" : "没有面边界，按无限平面计算。")
                                .font(.system(size: 9)).foregroundStyle(m.finite ? Color.secondary : Color.orange)
                        }
                        LabeledContent("面", value: "\(f.name) · Z\(ncf(f.z))")
                        LabeledContent("边长度", value: "\(ncf(edgeLength(e))) mm")
                        if e.arcR > 0.01 {
                            LabeledContent("圆弧半径 R", value: "\(ncf(e.arcR)) mm")
                        }
                    }
                    if !pickedPoints.isEmpty {
                        ForEach(Array(pickedPoints.enumerated()), id: \.offset) { pair in
                            LabeledContent("点\(pair.offset + 1)",
                                           value: "X\(ncf(pair.element.x)) Y\(ncf(pair.element.y)) Z\(ncf(pair.element.z))")
                        }
                        if pickedPoints.count > 1 {
                            let a = pickedPoints[0], b = pickedPoints[1]
                            let dx = b.x - a.x, dy = b.y - a.y, dz = b.z - a.z
                            LabeledContent("两点距离（3D）", value: "\(ncf(sqrt(dx * dx + dy * dy + dz * dz))) mm")
                            LabeledContent("ΔX / ΔY / ΔZ", value: "\(ncf(dx)) / \(ncf(dy)) / \(ncf(dz)) mm")
                        } else {
                            LabeledContent("到原点", value: "\(ncf(hypot(hypot(pickedPoints[0].x, pickedPoints[0].y), pickedPoints[0].z))) mm")
                        }
                    }
                    if let e = pickedEdges.first {
                        LabeledContent(e.arcR > 0.01 ? "圆弧1 弧长" : "边1 长度", value: "\(ncf(edgeLength(e))) mm")
                        if e.arcR > 0.01 {
                            LabeledContent("圆弧1 半径 R", value: "\(ncf(e.arcR)) mm")
                        }
                        LabeledContent("边1 端点", value: "(\(ncf(Double(e.a.x))),\(ncf(Double(e.a.y))),\(ncf(e.z))) → (\(ncf(Double(e.b.x))),\(ncf(Double(e.b.y))),\(ncf(e.zEnd)))")
                    }
                    if pickedEdges.count > 1 {
                        LabeledContent("边2 长度", value: "\(ncf(edgeLength(pickedEdges[1]))) mm")
                        LabeledContent("两边最短距离（3D）", value: "\(ncf(edgeGap(pickedEdges[0], pickedEdges[1]))) mm")
                    }
                    if !pickedFaces.isEmpty {
                        ForEach(Array(pickedFaces.enumerated()), id: \.offset) { pair in
                            LabeledContent("面\(pair.offset + 1)", value: "\(pair.element.name) · Z\(ncf(pair.element.z))")
                        }
                        if pickedFaces.count > 1 {
                            let m = faceMeasure(pickedFaces[0], pickedFaces[1])
                            LabeledContent(m.parallel ? "两面法向距离" : "两面中心距（不平行）", value: "\(ncf(m.distance)) mm")
                            LabeledContent("ΔX / ΔY / ΔZ", value: "\(ncf(m.dx)) / \(ncf(m.dy)) / \(ncf(m.dz)) mm")
                            LabeledContent("中心距", value: "\(ncf(m.center)) mm")
                        } else if let f = pickedFaces.first {
                            LabeledContent("该面面积", value: "\(ncf(f.area)) mm²")
                        }
                    }
                    if let h = pickedHole {
                        LabeledContent(h.onBottom ? "拾取孔/腔底面" : "拾取孔/腔", value: h.name)
                        LabeledContent(h.onBottom ? "底面中心" : "中心 / 顶面",
                                       value: "X\(ncf(h.x)) Y\(ncf(h.y)) Z\(ncf(h.onBottom ? h.bottomZ : h.z))")
                        LabeledContent(h.isPocket ? "外形尺寸" : "直径", value: "\(ncf(h.dia)) mm")
                        if measureTarget == .circle {
                            LabeledContent("半径 R", value: "\(ncf(h.dia / 2)) mm")
                            LabeledContent("圆心", value: "X\(ncf(h.x)) Y\(ncf(h.y)) Z\(ncf(h.z))")
                            if h.id != "base-circle" {
                                let edgeD = outerEdgeDistance(from: h)
                                let wall = max(0, edgeD - (h.isPocket ? min(h.w, h.h) : h.dia) / 2)
                                LabeledContent("孔/腔边到外形", value: "\(ncf(edgeD)) mm")
                                LabeledContent("最小壁厚", value: "\(ncf(wall)) mm")
                                if let other = nearestOtherHole(from: h) {
                                    LabeledContent("最近圆：\(other.name)", value: "中心距 \(ncf(other.center)) mm")
                                    LabeledContent("两圆边间隙", value: "\(ncf(other.gap)) mm")
                                }
                            }
                        }
                        LabeledContent("深度", value: h.through ? "通孔 / 通腔" : "\(ncf(h.depth)) mm")
                        LabeledContent("底 Z", value: "Z\(ncf(h.bottomZ))")
                    }
                    if measureTarget == .body || measureTarget == .compound {
                        LabeledContent("体积", value: "\(ncf(partVolume)) mm³")
                        LabeledContent("重量", value: "\(ncf(partWeight)) g（\(material.rawValue)）")
                        LabeledContent("价格", value: "¥\(ncf(partPrice))")
                        LabeledContent("包容体积", value: "\(ncf(partBBoxVolume)) mm³")
                        LabeledContent("外形尺寸", value: "\(ncf(Double(partBBox.width))) × \(ncf(Double(partBBox.height))) × \(ncf(PartProg.maxZ(spec) - PartProg.minZ(spec))) mm")
                        LabeledContent("顶面面积", value: "\(ncf(partProjectedArea)) mm²")
                        LabeledContent("外形面积", value: "\(ncf(outerSurfaceArea)) mm²")
                        if !spec.steps.isEmpty {
                            LabeledContent("台阶层数", value: "\(spec.steps.count) 层")
                            LabeledContent("总 Z 范围", value: "Z\(ncf(PartProg.minZ(spec))) → Z\(ncf(PartProg.maxZ(spec)))")
                        }
                    }
                }

                Section("说明") {
                    Text("点/边/面：第一次点对象1，第二次点对象2，结果算两点、两边或两面距离。角：连续点三个点，算中间点的夹角。体/复合：查看体积、重量、包容尺寸。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Text("点目标会优先吸附模型顶点和孔中心；面目标支持顶面和侧面；孔/腔底面也可单独拾取。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("测量")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismissMeasureSheet() }
                }
            }
        }
    }

    private func metricCard(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(size: 11, weight: .bold)).multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color(.secondarySystemBackground).opacity(0.75)))
    }

    private var displayPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("视角").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Text("当前：\(modelViewName)").font(.system(size: 11)).foregroundStyle(studioBlue)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        viewChip("等轴", active: modelViewName == "等轴") { applyView("等轴", 0.78, 0.62) }
                        viewChip("俯视", active: modelViewName == "俯视") { applyView("俯视", 0, 1.5) }
                        viewChip("正视", active: modelViewName == "正视") { applyView("正视", 0, 0) }
                        viewChip("右视", active: modelViewName == "右视") { applyView("右视", 1.5708, 0) }
                        viewChip("仰视", active: modelViewName == "仰视") { applyView("仰视", 0, -1.5) }
                    }
                }
                Divider()
                HStack {
                    Text("网格").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Picker("", selection: Binding(
                        get: { gridStep },
                        set: { v in
                            gridStep = v
                            showToastView("参考网格已改为 \(Int(v)) mm")
                        })) {
                        Text("5").tag(5.0); Text("10").tag(10.0); Text("20").tag(20.0); Text("50").tag(50.0)
                    }
                    .labelsHidden().frame(width: 80)
                }
                Toggle("显示网格", isOn: Binding(
                    get: { showModelGrid },
                    set: { v in
                        showModelGrid = v
                        showToastView(v ? "参考网格已打开" : "参考网格已关闭")
                    }))
                Toggle("网格吸附", isOn: $snapGrid)
                Toggle("节点吸附", isOn: $snapVertex)
                Toggle("点顶面取 XY", isOn: Binding(
                    get: { tapOnModel },
                    set: { v in
                        tapOnModel = v
                        if v {
                            modelPanel = .none
                            showToastView("点顶面取XY已开：在模型顶面点一下")
                        }
                    }))
                if tapOnModel {
                    Text(hasPtr ? "指针 X\(ncf(ptrX)) Y\(ncf(ptrY))" : "已开启：在模型顶面点一下即可取点")
                        .font(.system(size: 10)).foregroundStyle(studioBlue)
                }
                Text("网格吸附、节点吸附与草图页“参数”里同一组设置，只影响草图落点。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Divider()
                Text("选择过滤").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Picker("选择过滤", selection: $modelFilter) {
                    ForEach(ModelSelectionFilter.allCases) { f in Text(f.rawValue).tag(f) }
                }
                .pickerStyle(.segmented)
                Text("过滤后：全部=点特征/台阶都能选；特征=只选孔/腔；台阶=只选增料台阶；草图=只选草图。特征树不受影响。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Toggle("单指平移视图", isOn: $viewPanMode)
                Text("单指自由旋转（俯仰不锁 ±90°），双指缩放；打开平移后单指拖动只移视图。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 13)
            .padding(.bottom, 14)
        }
    }

    private func applyView(_ name: String, _ y: Double, _ p: Double) {
        setView(y, p)
        modelViewName = name
        modelPanel = .none
        showToastView("已切换到\(name)")
    }

    // MARK: - 测量数据（2.5D 真实几何近似）

    private func longestEdgeLength(_ pts: [CGPoint]) -> Double {
        guard pts.count >= 2 else { return 0 }
        var best = 0.0
        for i in pts.indices {
            let a = pts[i]
            let b = pts[(i + 1) % pts.count]
            best = max(best, hypot(Double(a.x - b.x), Double(a.y - b.y)))
        }
        return best
    }

    private var partBBox: CGRect { PartProg.bbox(spec) }

    private var outerSurfaceArea: Double {
        abs(ContourGeo.signedArea(PartProg.pts(spec)))
    }

    private var cutVolume: Double {
        var cut = 0.0
        let bottom = PartProg.minZ(spec)
        for l in spec.innerLoops {
            let a = abs(ContourGeo.signedArea(PartProg.loopPoints(l)))
            let host = PartProg.hostZ(spec, l.cx, l.cy)
            let avail = max(host - bottom, 0)
            let d = l.through ? avail : min(max(l.depth, 0), avail)
            cut += a * d
        }
        for f in spec.feats {
            let host = PartProg.hostZ(spec, f)
            let avail = max(host - bottom, 0)
            let area = f.kind == .rectPocket
                ? f.w * f.h
                : Double.pi * (f.dia / 2) * (f.dia / 2)
            let d = f.kind == .hole ? avail : min(max(f.depth, 0), avail)
            cut += area * d
        }
        return cut
    }

    private var stepVolume: Double {
        var v = 0.0
        for s in spec.steps {
            let a = abs(ContourGeo.signedArea(PartProg.shapePoints(s.shape, spec)))
            v += (s.mode == .add ? 1 : -1) * a * max(s.height, 0)
        }
        return v
    }

    private var partVolume: Double {
        max(0, outerSurfaceArea * spec.height - cutVolume + stepVolume)
    }

    private var partWeight: Double { partVolume * material.density / 1000 }

    private var partPrice: Double { partWeight / 1000 * material.pricePerKg }

    private var partBBoxVolume: Double {
        Double(partBBox.width) * Double(partBBox.height)
            * max(0, PartProg.maxZ(spec) - PartProg.minZ(spec))
    }

    private var partProjectedArea: Double {
        var cut = 0.0
        for l in spec.innerLoops {
            cut += abs(ContourGeo.signedArea(PartProg.loopPoints(l)))
        }
        for f in spec.feats {
            cut += (f.kind == .rectPocket ? f.w * f.h : Double.pi * (f.dia / 2) * (f.dia / 2))
        }
        return max(0, outerSurfaceArea - cut)
    }

    @ViewBuilder
    private var modelControls: some View {
        Section("视角") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    viewChip("等轴") { applyView("等轴", 0.78, 0.62) }
                    viewChip("俯视") { applyView("俯视", 0, 1.5) }
                    viewChip("正视") { applyView("正视", 0, 0) }
                    viewChip("右视") { applyView("右视", 1.5708, 0) }
                    viewChip("仰视") { applyView("仰视", 0, -1.5) }
                    viewChip("适合窗口") { applyView("等轴", 0.78, 0.62) }
                }
                .padding(.vertical, 2)
            }
            Text("画布已独立，手指左右拖可一直转（360°不限），上下翻到仰视；双指缩放，不再带着页面上下跑。")
                .font(.caption).foregroundStyle(.secondary)
        }

        Section("指针 / 加特征") {
            Toggle("点图上顶面取 XY", isOn: Binding(
                get: { tapOnModel },
                set: { v in
                    tapOnModel = v
                    if v {
                        modelPanel = .none
                        showToastView("点顶面取XY已开：在模型顶面点一下")
                    }
                }))
            HStack {
                miniNum("X", $ptrX)
                miniNum("Y", $ptrY)
                Button("用这个点加孔") { beginFeat(.hole) }
                    .font(.system(size: 12, weight: .semibold))
            }
            Text(hasPtr ? "当前指针 X\(ncf(ptrX)) Y\(ncf(ptrY))" : "还没落点：打开上面的开关，再点一下零件顶面")
                .font(.caption).foregroundStyle(.secondary)
        }

        Section("特征清单") {
            HStack {
                Text("草图 \(spec.nodes.count) 段").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("外形 · 孔\(spec.feats.filter { $0.kind == .hole }.count) · 型腔\(spec.feats.filter { $0.kind != .hole }.count)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if spec.feats.isEmpty {
                Text("还没有特征；下面加孔/圆腔/方腔，或草图里加内轮廓。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }

        Section("特征（孔 / 型腔）") {
            ForEach($spec.feats) { $f in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        TextField("名称", text: $f.name)
                            .font(.system(size: 13, weight: .semibold))
                            .textFieldStyle(.roundedBorder)
                        Picker("", selection: $f.kind) {
                            ForEach(PartFeatKind.allCases) { k in Text(k.rawValue).tag(k) }
                        }
                        .labelsHidden()
                        Spacer()
                        Button {
                            pushUndo()
                            let id = f.id
                            spec.feats.removeAll { $0.id == id }
                        } label: {
                            Image(systemName: "trash").foregroundStyle(.red)
                        }
                        Toggle("抑制", isOn: $f.suppressed)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .scaleEffect(0.7)
                    }
                    HStack(spacing: 6) {
                        miniNum("X", $f.x)
                        miniNum("Y", $f.y)
                        if f.kind == .rectPocket {
                            miniNum("长", $f.w)
                            miniNum("宽", $f.h)
                        } else {
                            miniNum("Ø", $f.dia)
                        }
                        miniNum("深", $f.depth)
                    }
                    Text(f.kind == .hole ? "Ø\(ncf(f.dia)) \(f.holeSummary)"
                         : (f.kind == .rectPocket ? "\(ncf(f.w))×\(ncf(f.h)) 深\(ncf(f.depth))"
                            : "Ø\(ncf(f.dia)) 深\(ncf(f.depth))"))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            HStack {
                Button { beginFeat(.hole) } label: { Label("加孔", systemImage: "circle.circle") }
                Spacer()
                Button { beginFeat(.pocket) } label: { Label("加圆腔", systemImage: "circle.dashed") }
                Spacer()
                Button { beginFeat(.rectPocket) } label: { Label("加方腔", systemImage: "rectangle.dashed") }
            }
            if !spec.innerLoops.isEmpty {
                Text("草图里还有 \(spec.innerLoops.count) 个内轮廓，会自动作为挖孔/型腔加进工序。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }

        Section("拉伸 / 整件变换") {
            numRow("厚度 H (mm)", $spec.height)
            numRow("顶面余量 (mm)", $spec.topStock)
            HStack {
                Button("旋转零件…") { showRotate = true }
                Spacer()
                Button("缩放零件…") { showScale = true }
                Spacer()
                Button("适合窗口") { setView(0.78, 0.62) }
            }
            .font(.system(size: 13, weight: .semibold))
        }
    }


    private func setView(_ y: Double, _ p: Double) {
        yaw = y; pitch = p; zoom = 0.95; zoomBase = 0.95
        panX = 0; panY = 0
        if abs(y - 0.78) < 0.1 && abs(p - 0.62) < 0.1 {
            modelViewName = "等轴"
        } else if abs(y) < 0.1 && abs(p - 1.5) < 0.1 {
            modelViewName = "俯视"
        } else if abs(y) < 0.1 && abs(p) < 0.1 {
            modelViewName = "正视"
        } else if abs(y - 1.5708) < 0.1 && abs(p) < 0.1 {
            modelViewName = "右视"
        } else if abs(y) < 0.1 && abs(p + 1.5) < 0.1 {
            modelViewName = "仰视"
        }
    }

    private func makeFeatDraft(_ kind: PartFeatKind) -> PartFeat {
        let b = PartProg.bbox(spec)
        var f = PartFeat(kind: kind)
        f.x = hasPtr ? ptrX : Double(b.midX)
        f.y = hasPtr ? ptrY : Double(b.midY)
        f.dia = kind == .hole ? 10 : 30
        f.depth = min(5, max(1, spec.height / 2))
        return f
    }

    private func beginFeat(_ kind: PartFeatKind) {
        featDraft = makeFeatDraft(kind)
        featEditID = nil
        selectedTreeID = nil
        modelPanel = .none
        showFeatCommand = true
    }

    private func beginEditFeat(_ f: PartFeat) {
        featDraft = f
        featEditID = f.id
        selectedTreeID = "feat-\(f.id.uuidString)"
        showFeatCommand = true
    }

    private func cancelFeatCommand() {
        showFeatCommand = false
        featDraft = nil
        featEditID = nil
    }

    private func validFeatDraft(_ f: PartFeat) -> Bool {
        switch f.kind {
        case .hole: return f.dia > 0
        case .pocket: return f.dia > 0 && f.depth > 0
        case .rectPocket: return f.w > 0 && f.h > 0 && f.depth > 0
        }
    }

    private func applyFeatDraft(close: Bool) {
        guard let draft = featDraft, validFeatDraft(draft) else {
            showToastView("特征参数不完整，先补尺寸")
            return
        }
        pushUndo()
        if let id = featEditID, let idx = spec.feats.firstIndex(where: { $0.id == id }) {
            spec.feats[idx] = draft
        } else {
            spec.feats.append(draft)
            featEditID = draft.id
            selectedTreeID = "feat-\(draft.id.uuidString)"
        }
        if close {
            showFeatCommand = false
            featDraft = nil
            featEditID = nil
            showToastView("特征已更新，下游工序已重建")
        } else {
            showToastView("已应用，继续调整参数")
        }
    }

    private func modelCam(size: CGSize) -> Cam {
        Cam(spec: spec, yaw: yaw, pitch: pitch, zoom: zoom,
            panX: panX, panY: panY, size: size)
    }

    private func modelXY(at p: CGPoint, size: CGSize) -> (Double, Double) {
        modelCam(size: size).unprojectTop(p)
    }

    private func drawModel(context: GraphicsContext, size: CGSize) {
        if !bodyVisible { return }
        if hiddenTreeIDs.contains("sketch") || hiddenTreeIDs.contains("extrude") { return }
        var ctx = context
        let cam = modelCam(size: size)
        let pts = PartProg.pts(spec)
        guard pts.count > 2 else { return }
        let depth = max(spec.height, 0.1)
        let showZCut = sectionOn && sectionAxis == .z
        let zTopAll = PartProg.maxZ(spec)
        let zBottomAll = PartProg.minZ(spec)
        let zSpanAll = max(zTopAll - zBottomAll, 0.2)
        let cutZ: Double? = showZCut
            ? zTopAll - zSpanAll * (sectionReverse ? (1 - sectionT) : sectionT)
            : nil
        func clipZ(_ top: Double, _ bottom: Double) -> (Double, Double)? {
            let b = max(bottom, cutZ ?? -Double.greatestFiniteMagnitude)
            return top > b + 0.0001 ? (top, b) : nil
        }
        func visibleZ(_ z: Double) -> Bool {
            guard let cutZ else { return true }
            return z >= cutZ - 0.0001
        }

        func ringPath(_ z: Double) -> Path {
            var path = Path()
            guard let f = pts.first else { return path }
            path.move(to: cam.p(f.x, f.y, z))
            for q in pts.dropFirst() { path.addLine(to: cam.p(q.x, q.y, z)) }
            return path
        }

        func circle(_ cx: Double, _ cy: Double, _ z: Double, _ r: Double) -> Path {
            var path = Path()
            for i in 0...30 {
                let a = Double(i) / 30 * 2 * Double.pi
                let q = cam.p(cx + r * cos(a), cy + r * sin(a), z)
                if i == 0 { path.move(to: q) } else { path.addLine(to: q) }
            }
            return path
        }

        func ringPath(_ ring: [CGPoint], _ z: Double) -> Path {
            var path = Path()
            guard let f = ring.first else { return path }
            path.move(to: cam.p(Double(f.x), Double(f.y), z))
            for q in ring.dropFirst() { path.addLine(to: cam.p(Double(q.x), Double(q.y), z)) }
            return path
        }

        func metalTone(_ k: Double, _ alpha: Double = 1) -> Color {
            let t = max(0, min(1, k))
            let b = metalBaseRGB
            let f = 0.30 + 0.74 * t
            return Color(red: min(1, b.0 * f),
                         green: min(1, b.1 * f),
                         blue: min(1, b.2 * f)).opacity(alpha)
        }

        /// 高光色：向白色混合，保留材料本身的冷暖倾向
        func metalSpecular(_ strength: Double) -> Color {
            let s = max(0, min(1, strength))
            let b = metalBaseRGB
            return Color(red: min(1, b.0 + (1 - b.0) * s),
                         green: min(1, b.1 + (1 - b.1) * s),
                         blue: min(1, b.2 + (1 - b.2) * s))
        }

        /// 顶面：沿屏幕光照方向做暗→亮→高光渐变，避免整块死平
        func metalTopShading(_ ring: [CGPoint], z: Double) -> GraphicsContext.Shading {
            guard let first = ring.first else { return .color(metalTone(0.92)) }
            var minX = Double(first.x), maxX = Double(first.x)
            var minY = Double(first.y), maxY = Double(first.y)
            for p in ring {
                let q = cam.p(Double(p.x), Double(p.y), z)
                minX = min(minX, Double(q.x)); maxX = max(maxX, Double(q.x))
                minY = min(minY, Double(q.y)); maxY = max(maxY, Double(q.y))
            }
            let start = CGPoint(x: CGFloat(minX), y: CGFloat(maxY))
            let end = CGPoint(x: CGFloat(maxX), y: CGFloat(minY))
            let spec = metalSpecularStrength * 0.88
            return .linearGradient(
                Gradient(stops: [
                    .init(color: metalTone(0.56), location: 0.0),
                    .init(color: metalTone(0.82), location: 0.36),
                    .init(color: metalTone(1.0), location: 0.74),
                    .init(color: metalSpecular(spec), location: 1.0)
                ]),
                startPoint: start,
                endPoint: end
            )
        }

        /// 侧面：上沿亮、下沿暗，朝光面再加一条窄高光带
        func metalFaceShading(_ a: CGPoint, _ b: CGPoint,
                              zTop: Double, zBottom: Double,
                              shade: Double) -> GraphicsContext.Shading {
            let midX = (Double(a.x) + Double(b.x)) / 2
            let midY = (Double(a.y) + Double(b.y)) / 2
            let topMid = cam.p(midX, midY, zTop)
            let botMid = cam.p(midX, midY, zBottom)
            let faceSpec = max(0, min(1, (shade - 0.56) / 0.40)) * metalSpecularStrength
            var stops: [Gradient.Stop] = [
                .init(color: metalTone(min(1, shade + 0.08)), location: 0.0)
            ]
            if faceSpec > 0.03 {
                stops.append(.init(color: metalSpecular(faceSpec), location: 0.14))
            }
            stops.append(.init(color: metalTone(shade * 0.78), location: 0.50))
            stops.append(.init(color: metalTone(shade * 0.52), location: 1.0))
            return .linearGradient(
                Gradient(stops: stops),
                startPoint: topMid,
                endPoint: botMid
            )
        }

        /// 侧面朝光程度：外法向与固定光照方向点积，做出面与面之间的明暗差
        func sideShade(_ a: CGPoint, _ b: CGPoint,
                       centroid: (Double, Double)) -> Double {
            let dx = Double(b.x - a.x), dy = Double(b.y - a.y)
            let len = max(hypot(dx, dy), 0.0001)
            var nx = -dy / len, ny = dx / len
            let mx = (Double(a.x) + Double(b.x)) / 2
            let my = (Double(a.y) + Double(b.y)) / 2
            if nx * (mx - centroid.0) + ny * (my - centroid.1) < 0 {
                nx = -nx; ny = -ny
            }
            let light = nx * 0.38 - ny * 0.46 + 0.08
            return max(0.40, min(0.96, 0.56 + light * 0.58))
        }

        func prism(_ ring: [CGPoint], zTop: Double, zBottom: Double,
                   tint: Color, alpha: Double, dashed: Bool = false,
                   metal: Bool = false) {
            guard ring.count > 2 else { return }
            let top = ringPath(ring, zTop)
            let bottom = ringPath(ring, zBottom)
            if metal {
                let cx = ring.reduce(0.0) { $0 + Double($1.x) } / Double(ring.count)
                let cy = ring.reduce(0.0) { $0 + Double($1.y) } / Double(ring.count)
                ctx.fill(bottom, with: .color(metalTone(0.26)))
                ctx.stroke(bottom, with: .color(metalTone(0.22)), lineWidth: 1)
                for i in ring.indices {
                    let a = ring[i], b = ring[(i + 1) % ring.count]
                    var side = Path()
                    side.move(to: cam.p(Double(a.x), Double(a.y), zTop))
                    side.addLine(to: cam.p(Double(b.x), Double(b.y), zTop))
                    side.addLine(to: cam.p(Double(b.x), Double(b.y), zBottom))
                    side.addLine(to: cam.p(Double(a.x), Double(a.y), zBottom))
                    side.closeSubpath()
                    let shade = sideShade(a, b, centroid: (cx, cy))
                    ctx.fill(side, with: metalFaceShading(a, b, zTop: zTop, zBottom: zBottom, shade: shade))
                }
                ctx.fill(top, with: metalTopShading(ring, z: zTop))
                ctx.stroke(top, with: .color(metalTone(0.28)), lineWidth: 1.2)
            } else {
                ctx.fill(bottom, with: .color(tint.opacity(alpha * 0.45)))
                ctx.stroke(bottom, with: .color(tint.opacity(alpha + 0.25)), lineWidth: 1)
                for i in ring.indices {
                    let a = ring[i], b = ring[(i + 1) % ring.count]
                    var side = Path()
                    side.move(to: cam.p(Double(a.x), Double(a.y), zTop))
                    side.addLine(to: cam.p(Double(b.x), Double(b.y), zTop))
                    side.addLine(to: cam.p(Double(b.x), Double(b.y), zBottom))
                    side.addLine(to: cam.p(Double(a.x), Double(a.y), zBottom))
                    side.closeSubpath()
                    ctx.fill(side, with: .color(tint.opacity(alpha * 0.55)))
                }
                ctx.fill(top, with: .color(tint.opacity(alpha)))
                ctx.stroke(top, with: .color(tint),
                           style: StrokeStyle(lineWidth: dashed ? 1.4 : 2,
                                              dash: dashed ? [4, 3] : []))
            }
        }

        func selectedMarker(_ f: PartFeat, radius: Double, z: Double = 0) {
            let r = max(radius, 1)
            ctx.stroke(circle(f.x, f.y, z, r), with: .color(studioBlue), lineWidth: 2)
            let q = cam.p(f.x, f.y, z)
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: q.x - 7, y: q.y)); p.addLine(to: CGPoint(x: q.x + 7, y: q.y))
                p.move(to: CGPoint(x: q.x, y: q.y - 7)); p.addLine(to: CGPoint(x: q.x, y: q.y + 7))
            }, with: .color(studioBlue), lineWidth: 1.2)
        }

        if spec.showStock {
            let sb = PartProg.stockBBox(spec)
            let sz = PartProg.stockZRange(spec)
            let ring = [CGPoint(x: sb.minX, y: sb.minY), CGPoint(x: sb.maxX, y: sb.minY),
                        CGPoint(x: sb.maxX, y: sb.maxY), CGPoint(x: sb.minX, y: sb.maxY)]
            if let (st, sbot) = clipZ(sz.top, sz.bottom) {
                prism(ring, zTop: st, zBottom: sbot,
                      tint: Color(white: 0.45), alpha: 0.035, dashed: true)
                let q = cam.p(Double(sb.minX), Double(sb.maxY), st)
                ctx.draw(Text("毛坯 \(ncf(Double(sb.width)))×\(ncf(Double(sb.height)))")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.secondary),
                         at: CGPoint(x: q.x + 6, y: q.y - 8))
            }
        }

        if let (baseTop, baseBottom) = clipZ(0, -depth) {
            let bottom = ringPath(baseBottom)
            ctx.stroke(bottom, with: .color(metalTone(0.24)), lineWidth: 1)
            let baseCx = pts.reduce(0.0) { $0 + Double($1.x) } / Double(pts.count)
            let baseCy = pts.reduce(0.0) { $0 + Double($1.y) } / Double(pts.count)

            for i in pts.indices {
                let a = pts[i], b = pts[(i + 1) % pts.count]
                var side = Path()
                side.move(to: cam.p(a.x, a.y, baseTop))
                side.addLine(to: cam.p(b.x, b.y, baseTop))
                side.addLine(to: cam.p(b.x, b.y, baseBottom))
                side.addLine(to: cam.p(a.x, a.y, baseBottom))
                side.closeSubpath()
                let shade = sideShade(a, b, centroid: (baseCx, baseCy))
                ctx.fill(side, with: metalFaceShading(a, b, zTop: baseTop, zBottom: baseBottom, shade: shade))
            }

            let layers = max(1, Int(ceil((baseTop - baseBottom) / max(spec.stepDown, 0.1))))
            if layers > 1 {
                for i in 1..<layers {
                    let z = max(baseBottom, baseTop - Double(i) * spec.stepDown)
                    ctx.stroke(ringPath(z), with: .color(metalTone(0.38, 0.45)), lineWidth: 0.7)
                }
            }
            for i in Swift.stride(from: 0, to: pts.count, by: max(1, pts.count / 30)) {
                let q = pts[i]
                ctx.stroke(Path { p in
                    p.move(to: cam.p(q.x, q.y, baseTop))
                    p.addLine(to: cam.p(q.x, q.y, baseBottom))
                }, with: .color(metalTone(0.30, 0.75)), lineWidth: 0.8)
            }

            ctx.fill(ringPath(baseTop), with: metalTopShading(pts, z: baseTop))
            ctx.stroke(ringPath(baseTop), with: .color(metalTone(0.25)), lineWidth: 1.2)

            if bodyHighlight {
                ctx.fill(ringPath(baseTop), with: .color(Color.yellow.opacity(0.14)))
                ctx.stroke(ringPath(baseTop), with: .color(Color.yellow.opacity(0.95)), lineWidth: 4)
            }

            if showZCut {
                ctx.fill(bottom, with: .color(Color.orange.opacity(0.42)))
                ctx.stroke(bottom, with: .color(.orange), lineWidth: 2)
            } else {
                ctx.fill(bottom, with: .color(metalTone(0.30)))
            }
        }

        // 建模页参考网格：让“显示”里的网格步距有真实反馈
        if showModelGrid, gridStep > 0.01, !showZCut {
            let b = PartProg.bbox(spec)
            let step = gridStep
            let x0 = floor(Double(b.minX) / step) * step
            let x1 = ceil(Double(b.maxX) / step) * step
            let y0 = floor(Double(b.minY) / step) * step
            let y1 = ceil(Double(b.maxY) / step) * step
            var topClip = ringPath(0)
            topClip.closeSubpath()
            var gridCtx = ctx
            gridCtx.clip(to: topClip)
            var x = x0
            while x <= x1 + 0.001 {
                gridCtx.stroke(Path { p in
                    p.move(to: cam.p(x, y0, 0)); p.addLine(to: cam.p(x, y1, 0))
                }, with: .color(Color.black.opacity(0.10)), lineWidth: 0.6)
                x += step
            }
            var y = y0
            while y <= y1 + 0.001 {
                gridCtx.stroke(Path { p in
                    p.move(to: cam.p(x0, y, 0)); p.addLine(to: cam.p(x1, y, 0))
                }, with: .color(Color.black.opacity(0.10)), lineWidth: 0.6)
                y += step
            }
        }

        // 多台阶：基础体之上按各自的 Z 画独立棱柱；除料层用红色虚线
        for s in spec.steps.sorted(by: { $0.z0 < $1.z0 })
            where bodyVisible && !hiddenTreeIDs.contains("extrude") && !hiddenTreeIDs.contains("step-\(s.id.uuidString)") {
            let sp = PartProg.pts(s, spec)
            guard sp.count > 2 else { continue }
            let top = s.mode == .add ? s.z1 : s.drawTop
            let bottom = s.mode == .add ? s.z0 : s.drawBottom
            guard let (vt, vb) = clipZ(top, bottom) else { continue }
            if s.mode == .add {
                prism(sp, zTop: vt, zBottom: vb,
                      tint: bodyTint, alpha: 0.20, metal: true)
            } else {
                prism(sp, zTop: vt, zBottom: vb,
                      tint: Color.red, alpha: 0.13, dashed: true)
            }
            if showZCut {
                ctx.fill(ringPath(sp, vb), with: .color(Color.orange.opacity(0.42)))
                ctx.stroke(ringPath(sp, vb), with: .color(.orange), lineWidth: 1.6)
            }
            let cx = sp.reduce(0.0) { $0 + Double($1.x) } / Double(sp.count)
            let cy = sp.reduce(0.0) { $0 + Double($1.y) } / Double(sp.count)
            let q = cam.p(cx, cy, vt)
            ctx.draw(Text("\(s.name)  Z\(ncf(vb))~\(ncf(vt))")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(s.mode == .add ? bodyTint : .red),
                     at: CGPoint(x: q.x, y: q.y - 11))
        }

        for l in spec.innerLoops where !hiddenTreeIDs.contains("inner-\(l.id.uuidString)") {
            let host = PartProg.hostZ(spec, l.cx, l.cy)
            guard visibleZ(host) else { continue }
            let avail = max(host - PartProg.minZ(spec), 0)
            let loopCut = l.through ? avail : min(max(l.depth, 0), avail)
            guard loopCut > 0.001 else { continue }
            let d = PartProg.drawForLoop(l, spec, depth: loopCut + 1,
                                         dia: max(spec.pocketDia, 1), hNo: spec.pocketTool, zTop: host)
            let segs = ContourGeo.segments(ContourGeo.buildNodes(d))
            let flat = ContourGeo.flatten(segs, arcStep: 24)
            func loopPath(_ z: Double) -> Path {
                var p = Path()
                guard let f = flat.first else { return p }
                p.move(to: cam.p(f.x + l.cx, f.y + l.cy, z))
                for q in flat.dropFirst() { p.addLine(to: cam.p(q.x + l.cx, q.y + l.cy, z)) }
                return p
            }
            let topLoop = loopPath(host)
            ctx.fill(topLoop, with: .color(Color.red.opacity(0.12)))
            ctx.stroke(topLoop, with: .color(.red),
                       style: StrokeStyle(lineWidth: 1.4, dash: [4, 3]))
            let bottomLoopZ = max(host - loopCut, cutZ ?? -Double.greatestFiniteMagnitude)
            ctx.stroke(loopPath(bottomLoopZ), with: .color(Color.red.opacity(0.55)), lineWidth: 0.9)
            let c = cam.p(l.cx, l.cy, host)
            let text: String
            switch l.template {
            case .circle: text = "Ø" + ncf(l.circleD)
            case .rect: text = ncf(l.rectL) + "×" + ncf(l.rectW)
            case .slot: text = ncf(l.slotL) + "×" + ncf(l.slotW)
            case .free: text = l.name
            }
            ctx.draw(Text(text).font(.system(size: 9, weight: .semibold)).foregroundColor(.red),
                     at: CGPoint(x: c.x, y: c.y - 10))
        }

        for f in spec.feats where !hiddenTreeIDs.contains("feat-\(f.id.uuidString)")
            && !(showFeatCommand && featEditID == f.id) {
            let isSelected = selectedTreeID == "feat-\(f.id.uuidString)"
            let host = PartProg.hostZ(spec, f)
            guard visibleZ(host) else { continue }
            if f.kind == .rectPocket {
                let d = min(f.depth, max(spec.height + host, 0))
                let botZ = max(host - d, cutZ ?? -Double.greatestFiniteMagnitude)
                guard botZ < host - 0.001 else { continue }
                var top = Path()
                let x0 = f.x - f.w / 2, x1 = f.x + f.w / 2
                let y0 = f.y - f.h / 2, y1 = f.y + f.h / 2
                top.move(to: cam.p(x0, y0, host))
                top.addLine(to: cam.p(x1, y0, host))
                top.addLine(to: cam.p(x1, y1, host))
                top.addLine(to: cam.p(x0, y1, host))
                top.closeSubpath()
                ctx.fill(top, with: .color(Color(red: 1.0, green: 0.42, blue: 0.10).opacity(0.18)))
                ctx.stroke(top, with: .color(Color(red: 0.95, green: 0.55, blue: 0.20)), lineWidth: 1.4)
                var bot = Path()
                bot.move(to: cam.p(x0, y0, botZ))
                bot.addLine(to: cam.p(x1, y0, botZ))
                bot.addLine(to: cam.p(x1, y1, botZ))
                bot.addLine(to: cam.p(x0, y1, botZ))
                bot.closeSubpath()
                ctx.stroke(bot, with: .color(Color(red: 0.95, green: 0.55, blue: 0.20).opacity(0.75)), lineWidth: 1)
                label(ctx, cam, f, "\(ncf(f.w))×\(ncf(f.h)) 深\(ncf(f.depth))", z: host)
                if isSelected { selectedMarker(f, radius: max(f.w, f.h) / 2 + 4, z: host) }
                continue
            }
            let r = f.dia / 2
            if f.kind == .hole {
                let hk = f.resolvedHoleKind
                let rawBottom = PartProg.holeBottomZ(spec, f, host: host)
                let botZ = max(rawBottom, cutZ ?? -Double.greatestFiniteMagnitude)
                let color = Color(white: 0.35)
                if hk == .counterbore {
                    let bigR = f.resolvedCbDia / 2
                    let shoulder = max(host - PartProg.counterboreDepth(f),
                                       cutZ ?? -Double.greatestFiniteMagnitude)
                    ctx.fill(circle(f.x, f.y, host, bigR), with: .color(Color(white: 0.28).opacity(0.55)))
                    ctx.stroke(circle(f.x, f.y, host, bigR), with: .color(color), lineWidth: 1.5)
                    ctx.stroke(circle(f.x, f.y, shoulder, r), with: .color(color), lineWidth: 1.1)
                    ctx.stroke(circle(f.x, f.y, shoulder, bigR), with: .color(color.opacity(0.6)), lineWidth: 0.9)
                    ctx.stroke(circle(f.x, f.y, botZ, r), with: .color(color.opacity(0.65)), lineWidth: 0.9)
                    label(ctx, cam, f, "沉头 Ø\(ncf(f.resolvedCbDia)) 深\(ncf(f.resolvedCbDepth)) / 孔 Ø\(ncf(f.dia))", z: host)
                    if isSelected { selectedMarker(f, radius: bigR + 4, z: host) }
                } else if hk == .countersink {
                    let bigR = f.resolvedCsDia / 2
                    let coneZ = max(host - PartProg.countersinkDepth(f),
                                    cutZ ?? -Double.greatestFiniteMagnitude)
                    ctx.fill(circle(f.x, f.y, host, bigR), with: .color(Color(white: 0.28).opacity(0.55)))
                    ctx.stroke(circle(f.x, f.y, host, bigR), with: .color(color), lineWidth: 1.5)
                    ctx.stroke(circle(f.x, f.y, coneZ, r), with: .color(color), lineWidth: 1.1)
                    for i in 0..<16 {
                        let a = Double(i) / 16 * 2 * Double.pi
                        ctx.stroke(Path { p in
                            p.move(to: cam.p(f.x + bigR * cos(a), f.y + bigR * sin(a), host))
                            p.addLine(to: cam.p(f.x + r * cos(a), f.y + r * sin(a), coneZ))
                        }, with: .color(color.opacity(0.65)), lineWidth: 0.8)
                    }
                    ctx.stroke(circle(f.x, f.y, botZ, r), with: .color(color.opacity(0.65)), lineWidth: 0.9)
                    label(ctx, cam, f, "沉孔 Ø\(ncf(f.resolvedCsDia)) \(ncf(f.resolvedCsAngle))° / 孔 Ø\(ncf(f.dia))", z: host)
                    if isSelected { selectedMarker(f, radius: bigR + 4, z: host) }
                } else {
                    let c = circle(f.x, f.y, host, r)
                    ctx.fill(c, with: .color(Color(white: 0.28).opacity(0.55)))
                    ctx.stroke(c, with: .color(color), lineWidth: 1.4)
                    ctx.stroke(circle(f.x, f.y, botZ, r), with: .color(color.opacity(0.65)), lineWidth: 0.9)
                    let text = hk == .blind ? "盲孔 Ø\(ncf(f.dia)) 深\(ncf(f.resolvedHoleDepth))"
                        : (hk == .thread ? "螺纹底孔 Ø\(ncf(f.dia)) 深\(ncf(f.resolvedHoleDepth))" : "Ø\(ncf(f.dia))")
                    label(ctx, cam, f, text, z: host)
                    if isSelected { selectedMarker(f, radius: r + 4, z: host) }
                }
            } else {
                let d = min(f.depth, max(spec.height + host, 0))
                let botZ = max(host - d, cutZ ?? -Double.greatestFiniteMagnitude)
                guard botZ < host - 0.001 else { continue }
                let c = circle(f.x, f.y, host, r)
                ctx.fill(c, with: .color(Color(red: 1.0, green: 0.42, blue: 0.10).opacity(0.18)))
                ctx.stroke(c, with: .color(Color(red: 0.95, green: 0.55, blue: 0.20)), lineWidth: 1.4)
                ctx.stroke(circle(f.x, f.y, botZ, r), with: .color(Color(red: 0.95, green: 0.55, blue: 0.20).opacity(0.75)), lineWidth: 1)
                label(ctx, cam, f, "Ø\(ncf(f.dia)) 深\(ncf(f.depth))", z: host)
                if isSelected { selectedMarker(f, radius: r + 4, z: host) }
            }
        }

        if showFeatCommand, let d = featDraft {
            drawFeatDraft(&ctx, cam: cam, feat: d, cutZ: cutZ)
        }

        if sectionOn {
            drawSectionPlane(&ctx, cam, size: size)
        }
        if measureOn {
            drawMeasureBox(&ctx, cam)
        }

        drawAxisTriad(&ctx, size: size)
        drawCenterAxes(&ctx, cam: cam, size: size)

        if hasPtr {
            let o = cam.p(ptrX, ptrY, 0)
            let ax = cam.p(ptrX + 8, ptrY, 0)
            let ay = cam.p(ptrX, ptrY + 8, 0)
            let az = cam.p(ptrX, ptrY, -8)
            ctx.stroke(Path { p in p.move(to: o); p.addLine(to: ax) }, with: .color(.red), lineWidth: 1.4)
            ctx.stroke(Path { p in p.move(to: o); p.addLine(to: ay) }, with: .color(.green), lineWidth: 1.4)
            ctx.stroke(Path { p in p.move(to: o); p.addLine(to: az) }, with: .color(.blue), lineWidth: 1.4)
            ctx.draw(Text("X\(ncf(ptrX)) Y\(ncf(ptrY))").font(.system(size: 9, weight: .medium)).foregroundColor(.black),
                 at: CGPoint(x: o.x + 2, y: o.y - 16))
        }
    }

    private func drawFeatDraft(_ ctx: inout GraphicsContext, cam: Cam,
                               feat f: PartFeat, cutZ: Double?) {
        let host = PartProg.hostZ(spec, f)
        if let cutZ, host < cutZ - 0.0001 { return }
        let color = Color(red: 0.10, green: 0.55, blue: 0.95)
        func ring(_ cx: Double, _ cy: Double, _ z: Double, _ r: Double) -> Path {
            var p = Path()
            for i in 0...30 {
                let a = Double(i) / 30 * 2 * Double.pi
                let q = cam.p(cx + r * cos(a), cy + r * sin(a), z)
                if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
            }
            return p
        }
        func rect(_ z: Double) -> Path {
            let x0 = f.x - f.w / 2, x1 = f.x + f.w / 2
            let y0 = f.y - f.h / 2, y1 = f.y + f.h / 2
            var p = Path()
            p.move(to: cam.p(x0, y0, z))
            p.addLine(to: cam.p(x1, y0, z))
            p.addLine(to: cam.p(x1, y1, z))
            p.addLine(to: cam.p(x0, y1, z))
            p.closeSubpath()
            return p
        }
        let top: Path
        let bottom: Path
        switch f.kind {
        case .hole:
            let r = max(f.dia / 2, 0.1)
            top = ring(f.x, f.y, host, r)
            bottom = ring(f.x, f.y, max(PartProg.minZ(spec), cutZ ?? -Double.greatestFiniteMagnitude), r)
        case .pocket:
            let r = max(f.dia / 2, 0.1)
            let d = min(f.depth, max(spec.height + host, 0))
            top = ring(f.x, f.y, host, r)
            bottom = ring(f.x, f.y, max(host - d, cutZ ?? -Double.greatestFiniteMagnitude), r)
        case .rectPocket:
            let d = min(f.depth, max(spec.height + host, 0))
            top = rect(host)
            bottom = rect(max(host - d, cutZ ?? -Double.greatestFiniteMagnitude))
        }
        ctx.fill(top, with: .color(color.opacity(0.12)))
        ctx.stroke(top, with: .color(color), style: StrokeStyle(lineWidth: 1.8, dash: [4, 3]))
        ctx.stroke(bottom, with: .color(color.opacity(0.65)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        let c = cam.p(f.x, f.y, host)
        let label = f.kind == .hole ? "Ø\(ncf(f.dia)) \(f.holeSummary)" : (f.kind == .rectPocket ? "\(ncf(f.w))×\(ncf(f.h)) 深\(ncf(f.depth))" : "Ø\(ncf(f.dia)) 深\(ncf(f.depth))")
        ctx.draw(Text("预览 " + label).font(.system(size: 9, weight: .semibold)).foregroundColor(color),
                 at: CGPoint(x: c.x, y: c.y - 12))
    }

    private func drawAxisTriad(_ ctx: inout GraphicsContext, size: CGSize) {
        let origin = CGPoint(x: 96, y: CGFloat(size.height) - 84)
        let c = cos(yaw), s = sin(yaw)
        let sp = sin(pitch), cp = cos(pitch)
        func tip(_ x: Double, _ y: Double, _ z: Double) -> CGPoint {
            let rx = x * c - y * s
            let ry = x * s + y * c
            let syy = -(ry * sp + z * cp)
            return CGPoint(x: origin.x + CGFloat(rx * 22), y: origin.y + CGFloat(syy * 22))
        }
        let axes: [(CGPoint, Color, String)] = [
            (tip(1, 0, 0), .red, "X"),
            (tip(0, 1, 0), .green, "Y"),
            (tip(0, 0, 1), .blue, "Z")
        ]
        for (end, color, name) in axes {
            ctx.stroke(Path { p in p.move(to: origin); p.addLine(to: end) }, with: .color(color), lineWidth: 1.8)
            ctx.fill(Path(ellipseIn: CGRect(x: end.x - 2.5, y: end.y - 2.5, width: 5, height: 5)),
                     with: .color(color))
            ctx.draw(Text(name).font(.system(size: 9, weight: .bold)).foregroundColor(color),
                     at: CGPoint(x: end.x + (end.x >= origin.x ? 8 : -8),
                                 y: end.y + (end.y >= origin.y ? 6 : -7)))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: origin.x - 3, y: origin.y - 3, width: 6, height: 6)),
                 with: .color(.white))
        ctx.stroke(Path(ellipseIn: CGRect(x: origin.x - 3, y: origin.y - 3, width: 6, height: 6)),
                   with: .color(Color(white: 0.35)), lineWidth: 1)
    }

    /// 建模实体中心的 XYZ 方向箭头；告诉用户零件在 XY 基准面上、Z 朝上。
    private func drawCenterAxes(_ ctx: inout GraphicsContext, cam: Cam, size: CGSize) {
        let b = partBBox
        let cx = Double(b.midX), cy = Double(b.midY), z = 0.0
        let len = max(14.0, min(Double(b.width), Double(b.height)) * 0.30)
        let origin = cam.p(cx, cy, z)
        let ex = cam.p(cx + len, cy, z)
        let ey = cam.p(cx, cy + len, z)
        let ez = cam.p(cx, cy, z + len)

        func arrow(_ end: CGPoint, _ color: Color, _ label: String) {
            ctx.stroke(Path { p in
                p.move(to: origin)
                p.addLine(to: end)
            }, with: .color(color), lineWidth: 1.8)

            let dx = Double(end.x - origin.x), dy = Double(end.y - origin.y)
            let l = hypot(dx, dy)
            if l > 1 {
                let ux = dx / l, uy = dy / l
                let px = -uy, py = ux
                let p1 = CGPoint(x: end.x - CGFloat(ux * 7 + px * 3),
                                 y: end.y - CGFloat(uy * 7 + py * 3))
                let p2 = CGPoint(x: end.x - CGFloat(ux * 7 - px * 3),
                                 y: end.y - CGFloat(uy * 7 - py * 3))
                ctx.fill(Path { p in
                    p.move(to: end)
                    p.addLine(to: p1)
                    p.addLine(to: p2)
                    p.closeSubpath()
                }, with: .color(color))
            }
            let down = end.y > origin.y
            ctx.draw(Text(label).font(.system(size: 10, weight: .bold)).foregroundColor(color),
                     at: CGPoint(x: end.x + (end.x >= origin.x ? 9 : -9),
                                 y: end.y + (down ? 7 : -8)))
        }

        arrow(ex, .red, "X")
        arrow(ey, .green, "Y")
        arrow(ez, .blue, "Z")

        ctx.stroke(Path { p in
            p.move(to: CGPoint(x: origin.x - 5, y: origin.y))
            p.addLine(to: CGPoint(x: origin.x + 5, y: origin.y))
            p.move(to: CGPoint(x: origin.x, y: origin.y - 5))
            p.addLine(to: CGPoint(x: origin.x, y: origin.y + 5))
        }, with: .color(Color.white.opacity(0.9)), lineWidth: 1.2)
        ctx.draw(Text("XY 基准 Z0")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(Color(white: 0.32)),
                 at: CGPoint(x: origin.x + 26, y: origin.y + 14))
    }

    private func drawSectionPlane(_ ctx: inout GraphicsContext, _ cam: Cam, size: CGSize) {
        let b = partBBox
        let zTop = PartProg.maxZ(spec)
        let zBottom = PartProg.minZ(spec)
        let zSpan = max(zTop - zBottom, 0.2)
        let z = zTop - zSpan * (sectionReverse ? (1 - sectionT) : sectionT)
        let x = Double(b.minX) + Double(b.width) * (sectionReverse ? (1 - sectionT) : sectionT)
        let y = Double(b.minY) + Double(b.height) * (sectionReverse ? (1 - sectionT) : sectionT)
        var corners: [(Double, Double, Double)] = []
        switch sectionAxis {
        case .z:
            corners = [(Double(b.minX), Double(b.minY), z), (Double(b.maxX), Double(b.minY), z),
                       (Double(b.maxX), Double(b.maxY), z), (Double(b.minX), Double(b.maxY), z)]
        case .x:
            corners = [(x, Double(b.minY), zTop), (x, Double(b.maxY), zTop),
                       (x, Double(b.maxY), zBottom), (x, Double(b.minY), zBottom)]
        case .y:
            corners = [(Double(b.minX), y, zTop), (Double(b.maxX), y, zTop),
                       (Double(b.maxX), y, zBottom), (Double(b.minX), y, zBottom)]
        }
        var plane = Path()
        guard let f = corners.first else { return }
        plane.move(to: cam.p(f.0, f.1, f.2))
        for c in corners.dropFirst() { plane.addLine(to: cam.p(c.0, c.1, c.2)) }
        plane.closeSubpath()
        ctx.fill(plane, with: .color(studioBlue.opacity(0.13)))
        ctx.stroke(plane, with: .color(studioBlue.opacity(0.8)),
                   style: StrokeStyle(lineWidth: 1, dash: sectionLines ? [CGFloat(5), CGFloat(4)] : []))

        if sectionHandles {
            for c in corners {
                let q = cam.p(c.0, c.1, c.2)
                ctx.fill(Path(ellipseIn: CGRect(x: q.x - 3, y: q.y - 3, width: 6, height: 6)),
                         with: .color(.white))
                ctx.stroke(Path(ellipseIn: CGRect(x: q.x - 3, y: q.y - 3, width: 6, height: 6)),
                          with: .color(studioBlue), lineWidth: 1)
            }
        }
        let mid = cam.p(corners[0].0, corners[0].1, corners[0].2)
        ctx.draw(Text("剖切 \(sectionAxis.rawValue) \(Int(sectionT * 100))%")
                    .font(.system(size: 9, weight: .semibold)).foregroundColor(studioBlue),
                 at: CGPoint(x: mid.x + 42, y: mid.y + 14))
    }

    private func drawMeasureBox(_ ctx: inout GraphicsContext, _ cam: Cam) {
        let b = partBBox
        let zTop = PartProg.maxZ(spec)
        let zBottom = PartProg.minZ(spec)
        let pts = PartProg.pts(spec)
        let bottom: [(Double, Double)] = [(Double(b.minX), Double(b.minY)), (Double(b.maxX), Double(b.minY)),
                                          (Double(b.maxX), Double(b.maxY)), (Double(b.minX), Double(b.maxY))]
        func boxPath(_ z: Double) -> Path {
            var p = Path()
            guard let f = bottom.first else { return p }
            p.move(to: cam.p(f.0, f.1, z))
            for q in bottom.dropFirst() { p.addLine(to: cam.p(q.0, q.1, z)) }
            p.closeSubpath()
            return p
        }
        func topPath() -> Path {
            var p = Path()
            guard let f = pts.first else { return boxPath(0) }
            p.move(to: cam.p(Double(f.x), Double(f.y), 0))
            for q in pts.dropFirst() { p.addLine(to: cam.p(Double(q.x), Double(q.y), 0)) }
            p.closeSubpath()
            return p
        }

        switch measureTarget {
        case .point:
            if hasPtr {
                let q = cam.p(ptrX, ptrY, 0)
                ctx.stroke(Path(ellipseIn: CGRect(x: q.x - 9, y: q.y - 9, width: 18, height: 18)),
                           with: .color(.orange), lineWidth: 2)
                ctx.stroke(Path { p in
                    p.move(to: CGPoint(x: q.x - 15, y: q.y)); p.addLine(to: CGPoint(x: q.x + 15, y: q.y))
                    p.move(to: CGPoint(x: q.x, y: q.y - 15)); p.addLine(to: CGPoint(x: q.x, y: q.y + 15))
                }, with: .color(.orange), lineWidth: 1.2)
                ctx.draw(Text("点 X\(ncf(ptrX)) Y\(ncf(ptrY)) Z0")
                            .font(.system(size: 10, weight: .semibold)).foregroundColor(.orange),
                         at: CGPoint(x: q.x, y: q.y - 22))
            } else {
                let q = cam.p(Double(b.midX), Double(b.midY), 0)
                ctx.draw(Text("点：先打开“点顶面取 XY”，再点零件顶面")
                            .font(.system(size: 9, weight: .semibold)).foregroundColor(.orange),
                         at: CGPoint(x: q.x, y: q.y - 26))
            }

        case .edge:
            ctx.stroke(topPath(), with: .color(.orange), lineWidth: 2)
            if pts.count >= 2 {
                var best = 0.0
                var bestA = pts[0], bestB = pts[1]
                for i in 0..<pts.count {
                    let a = pts[i], c = pts[(i + 1) % pts.count]
                    let d = hypot(Double(c.x - a.x), Double(c.y - a.y))
                    if d > best { best = d; bestA = a; bestB = c }
                }
                ctx.stroke(Path { p in
                    p.move(to: cam.p(Double(bestA.x), Double(bestA.y), 0))
                    p.addLine(to: cam.p(Double(bestB.x), Double(bestB.y), 0))
                }, with: .color(.blue), lineWidth: 2.6)
                let mid = cam.p(Double((bestA.x + bestB.x) / 2), Double((bestA.y + bestB.y) / 2), 0)
                ctx.draw(Text("最长边 \(ncf(best)) mm / \(pts.count) 段")
                            .font(.system(size: 10, weight: .semibold)).foregroundColor(.blue),
                         at: CGPoint(x: mid.x, y: mid.y - 18))
            }

        case .face:
            let top = topPath()
            ctx.fill(top, with: .color(Color.orange.opacity(0.16)))
            ctx.stroke(top, with: .color(.orange), lineWidth: 2)
            let q = cam.p(Double(b.midX), Double(b.midY), 0)
            ctx.draw(Text("顶面面积 \(ncf(partProjectedArea)) mm²")
                        .font(.system(size: 10, weight: .semibold)).foregroundColor(.orange),
                     at: CGPoint(x: q.x, y: q.y - 26))

        case .pointFace:
            ctx.fill(topPath(), with: .color(Color.orange.opacity(0.12)))
            ctx.stroke(topPath(), with: .color(.orange.opacity(0.8)), lineWidth: 1.4)
            for p in pickedPoints {
                let q = cam.p(p.x, p.y, p.z)
                ctx.fill(Path(ellipseIn: CGRect(x: q.x - 4, y: q.y - 4, width: 8, height: 8)),
                         with: .color(.blue))
            }
            for f in pickedFaces {
                let q = cam.p(Double(f.center.x), Double(f.center.y), f.z)
                ctx.draw(Text("面 \(ncf(f.z))").font(.system(size: 9, weight: .semibold)).foregroundColor(.orange),
                         at: CGPoint(x: q.x, y: q.y - 12))
            }

        case .pointEdge:
            if let p = pickedPoints.first, let e = pickedEdges.first {
                let q = cam.p(p.x, p.y, p.z)
                let eq = cam.p(Double(e.a.x), Double(e.a.y), e.z)
                ctx.draw(Text("点-边 \(ncf(pointEdgeGap(p, e))) mm")
                            .font(.system(size: 9, weight: .semibold)).foregroundColor(.orange),
                         at: CGPoint(x: q.x, y: min(q.y, eq.y) - 22))
            }

        case .edgeFace:
            if let e = pickedEdges.first, let f = pickedFaces.first {
                let m = edgeFaceGap(e, f)
                let eq = cam.p(Double(e.a.x), Double(e.a.y), e.z)
                ctx.draw(Text("边-面 \(ncf(m.distance)) mm")
                            .font(.system(size: 9, weight: .semibold)).foregroundColor(.orange),
                         at: CGPoint(x: eq.x, y: eq.y - 22))
                let q = cam.p(Double(f.center.x), Double(f.center.y), f.z)
                ctx.draw(Text("面 \(ncf(f.z))").font(.system(size: 9, weight: .semibold)).foregroundColor(.orange),
                         at: CGPoint(x: q.x, y: q.y - 12))
            }

        case .circle:
            if let h = pickedHole {
                let hz = h.onBottom ? h.bottomZ : h.z
                let q = cam.p(h.x, h.y, hz)
                let edge = cam.p(h.x + h.dia / 2, h.y, hz)
                let r = max(8, abs(Double(edge.x - q.x)))
                ctx.stroke(Path(ellipseIn: CGRect(x: q.x - r, y: q.y - r, width: r * 2, height: r * 2)),
                           with: .color(.orange), lineWidth: 2.6)
                ctx.draw(Text("R\(ncf(h.dia / 2))  Ø\(ncf(h.dia))")
                            .font(.system(size: 9, weight: .semibold)).foregroundColor(.orange),
                         at: CGPoint(x: q.x, y: q.y - r - 12))
            }

        case .angle:
            for (i, p) in pickedPoints.enumerated() {
                let q = cam.p(p.x, p.y, p.z)
                ctx.fill(Path(ellipseIn: CGRect(x: q.x - 4, y: q.y - 4, width: 8, height: 8)),
                         with: .color(i == 1 ? .orange : .blue))
                ctx.draw(Text("\(i + 1)").font(.system(size: 8, weight: .bold)).foregroundColor(.secondary),
                         at: CGPoint(x: q.x + 7, y: q.y - 7))
            }
            if pickedPoints.count >= 2 {
                var line = Path()
                guard let f = pickedPoints.first else { break }
                let a = cam.p(f.x, f.y, f.z)
                line.move(to: a)
                for pp in pickedPoints.dropFirst() { line.addLine(to: cam.p(pp.x, pp.y, pp.z)) }
                ctx.stroke(line, with: .color(.orange), lineWidth: 1.8)
            }

        case .body, .compound:
            if measureTarget == .compound {
                ctx.fill(topPath(), with: .color(Color.yellow.opacity(0.10)))
            }
            ctx.stroke(boxPath(zTop), with: .color(.orange), lineWidth: 1.6)
            ctx.stroke(boxPath(zBottom), with: .color(.orange.opacity(0.55)), lineWidth: 1)
            for q in bottom {
                ctx.stroke(Path { p in
                    p.move(to: cam.p(q.0, q.1, zTop))
                    p.addLine(to: cam.p(q.0, q.1, zBottom))
                }, with: .color(.orange.opacity(0.45)), lineWidth: 1)
            }
            let q = cam.p(Double(b.midX), Double(b.midY), zTop)
            ctx.draw(Text("体积 \(ncf(partVolume)) mm³").font(.system(size: 10, weight: .semibold)).foregroundColor(.orange),
                     at: CGPoint(x: q.x, y: q.y - 26))
            ctx.draw(Text("\(ncf(Double(b.width))) × \(ncf(Double(b.height))) × \(ncf(PartProg.maxZ(spec) - PartProg.minZ(spec)))")
                        .font(.system(size: 9)).foregroundColor(.orange),
                     at: CGPoint(x: q.x, y: q.y - 13))
        }

        for (i, e) in pickedEdges.enumerated() {
            let a = cam.p(Double(e.a.x), Double(e.a.y), e.z)
            let b = cam.p(Double(e.b.x), Double(e.b.y), e.zEnd)
            ctx.stroke(Path { p in p.move(to: a); p.addLine(to: b) },
                       with: .color(.blue), lineWidth: 3)
            for q in [a, b] {
                ctx.fill(Path(ellipseIn: CGRect(x: q.x - 4, y: q.y - 4, width: 8, height: 8)),
                         with: .color(.blue))
            }
            ctx.draw(Text("边\(i + 1) \(ncf(edgeLength(e)))").font(.system(size: 9, weight: .semibold)).foregroundColor(.blue),
                     at: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 - 12))
        }
        if pickedEdges.count > 1 {
            let m1 = midpoint(pickedEdges[0]), m2 = midpoint(pickedEdges[1])
            let q1 = cam.p(m1.0, m1.1, m1.2), q2 = cam.p(m2.0, m2.1, m2.2)
            ctx.stroke(Path { p in p.move(to: q1); p.addLine(to: q2) },
                       with: .color(.blue.opacity(0.65)), lineWidth: 1.4)
            ctx.draw(Text("边距 \(ncf(edgeGap(pickedEdges[0], pickedEdges[1])))")
                        .font(.system(size: 9, weight: .semibold)).foregroundColor(.blue),
                     at: CGPoint(x: (q1.x + q2.x) / 2, y: (q1.y + q2.y) / 2 - 18))
        }
        for (i, f) in pickedFaces.enumerated() {
            let q = cam.p(Double(f.center.x), Double(f.center.y), f.z)
            ctx.stroke(Path(ellipseIn: CGRect(x: q.x - 9, y: q.y - 9, width: 18, height: 18)),
                       with: .color(.blue), lineWidth: 2)
            ctx.draw(Text("面\(i + 1) \(f.name)").font(.system(size: 9, weight: .semibold)).foregroundColor(.blue),
                     at: CGPoint(x: q.x, y: q.y - 20))
        }
        if pickedFaces.count > 1 {
            let a = pickedFaces[0], b = pickedFaces[1]
            let q1 = cam.p(Double(a.center.x), Double(a.center.y), a.z)
            let q2 = cam.p(Double(b.center.x), Double(b.center.y), b.z)
            let m = faceMeasure(a, b)
            ctx.stroke(Path { p in p.move(to: q1); p.addLine(to: q2) },
                       with: .color(.blue.opacity(0.65)), lineWidth: 1.4)
            ctx.draw(Text("面距 \(ncf(m.distance))").font(.system(size: 9, weight: .semibold)).foregroundColor(.blue),
                     at: CGPoint(x: (q1.x + q2.x) / 2, y: (q1.y + q2.y) / 2 - 20))
        }
        if let h = pickedHole {
            let hz = h.onBottom ? h.bottomZ : h.z
            let q = cam.p(h.x, h.y, hz)
            let edge = cam.p(h.x + h.dia / 2, h.y, hz)
            let r = max(5, abs(Double(edge.x - q.x)))
            ctx.stroke(Path(ellipseIn: CGRect(x: q.x - r, y: q.y - r, width: r * 2, height: r * 2)),
                       with: .color(.blue), lineWidth: 2)
            ctx.draw(Text(h.onBottom ? h.name + " 底面" : h.name)
                        .font(.system(size: 9, weight: .semibold)).foregroundColor(.blue),
                     at: CGPoint(x: q.x, y: q.y - 18))
        }
        for (i, p) in pickedPoints.enumerated() {
            let q = cam.p(p.x, p.y, p.z)
            ctx.fill(Path(ellipseIn: CGRect(x: q.x - 5, y: q.y - 5, width: 10, height: 10)),
                     with: .color(.blue))
            ctx.draw(Text("点\(i + 1)").font(.system(size: 9, weight: .semibold)).foregroundColor(.blue),
                     at: CGPoint(x: q.x, y: q.y - 14))
        }
        if pickedPoints.count > 1 {
            let a = pickedPoints[0], b = pickedPoints[1]
            let q1 = cam.p(a.x, a.y, a.z), q2 = cam.p(b.x, b.y, b.z)
            let d = sqrt(pow(b.x - a.x, 2) + pow(b.y - a.y, 2) + pow(b.z - a.z, 2))
            ctx.stroke(Path { p in p.move(to: q1); p.addLine(to: q2) },
                       with: .color(.blue.opacity(0.7)), lineWidth: 1.6)
            ctx.draw(Text("点距 \(ncf(d))").font(.system(size: 9, weight: .semibold)).foregroundColor(.blue),
                     at: CGPoint(x: (q1.x + q2.x) / 2, y: (q1.y + q2.y) / 2 - 20))
        }

        if calibratingPick, let sample = calibrationSample {
            let q = sample.point
            let r = CGFloat(pickTolerance)
            ctx.stroke(Path(ellipseIn: CGRect(x: q.x - r, y: q.y - r, width: r * 2, height: r * 2)),
                       with: .color(.green.opacity(0.8)),
                       style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: q.x - 8, y: q.y)); p.addLine(to: CGPoint(x: q.x + 8, y: q.y))
                p.move(to: CGPoint(x: q.x, y: q.y - 8)); p.addLine(to: CGPoint(x: q.x, y: q.y + 8))
            }, with: .color(.green), lineWidth: 1.5)
            ctx.draw(Text(toleranceLabel).font(.system(size: 9, weight: .bold)).foregroundColor(.green),
                     at: CGPoint(x: q.x, y: q.y + r + 10))
            if let e = sample.nearestEdge {
                let a = cam.p(Double(e.a.x), Double(e.a.y), e.z)
                let b = cam.p(Double(e.b.x), Double(e.b.y), e.z)
                ctx.stroke(Path { p in p.move(to: a); p.addLine(to: b) },
                           with: .color(.green), lineWidth: 3)
            }
        }
    }

    private func label(_ ctx: GraphicsContext, _ cam: Cam, _ f: PartFeat, _ text: String, z: Double = 0) {
        let q = cam.p(f.x, f.y, z)
        ctx.draw(Text(text).font(.system(size: 9, weight: .semibold)).foregroundColor(.black),
                 at: CGPoint(x: q.x, y: q.y - 10))
    }

    // MARK: - 3 出图

    private var drawingPage: some View {
        Group {
            Section("出图 · 尺寸图") {
                GeometryReader { _ in
                    drawingCanvas
                }
                .frame(height: 390)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            Section("图纸信息") {
                let b = PartProg.bbox(spec)
                Text("外形 \(ncf(Double(b.width))) × \(ncf(Double(b.height))) × 总高 \(ncf(PartProg.maxZ(spec) - PartProg.minZ(spec)))")
                Text("孔 \(spec.feats.filter { $0.kind == .hole }.count) 个 · 型腔 \(spec.feats.filter { $0.kind != .hole }.count) 个")
                    .font(.caption).foregroundStyle(.secondary)
                Text("尺寸按草图与特征自动标注，改建模参数这里会同步。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("导出 / 分享") {
                HStack(spacing: 10) {
                    Button {
                        exportDrawing()
                    } label: {
                        Label("导出尺寸图 PNG", systemImage: "square.and.arrow.down")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    if let url = drawingExportURL {
                        ShareLink(item: url) {
                            Label("分享", systemImage: "square.and.arrow.up")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                Button {
                    copyDrawingSummary()
                } label: {
                    Label("复制尺寸清单", systemImage: "doc.on.doc")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.bordered)
                HStack(spacing: 10) {
                    Button {
                        exportDXF()
                    } label: {
                        Label("导出 DXF 轮廓", systemImage: "square.and.arrow.down")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    if let url = dxfExportURL {
                        ShareLink(item: url) {
                            Label("分享 DXF", systemImage: "square.and.arrow.up")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                Button {
                    showDXFImporter = true
                } label: {
                    Label("导入 DXF / SVG / PLT", systemImage: "square.and.arrow.down")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.bordered)
                Text("支持 DXF / SVG / PLT 的 2D 轮廓（外形/内轮廓/孔）；不冒充 3D STEP。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    private var drawingCanvas: some View {
        Canvas { context, size in
            drawDrawing(context: context, size: size)
        }
        .background(Color.white)
    }

    private func importVector(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        do {
            let text = try readImportText(url)
            let name = url.deletingPathExtension().lastPathComponent
            let result: DXFImportResult
            let kind: String
            switch ext {
            case "svg":
                result = try SVGImporter.parse(text, name: name); kind = "SVG"
            case "plt", "hpgl":
                result = try PLTImporter.parse(text, name: name); kind = "PLT"
            default:
                result = try DXFImporter.parse(text, name: name); kind = "DXF"
            }
            applyImportedVector(result, kind: kind)
        } catch {
            showToastView("轮廓导入失败：\(error.localizedDescription)")
        }
    }

    private func readImportText(_ url: URL) throws -> String {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func applyImportedVector(_ result: DXFImportResult, kind: String) {
        pushUndo()
        var s = result.spec
        s.height = spec.height
        s.programNo = spec.programNo
        s.coord = spec.coord
        s.spindle = spec.spindle
        s.feed = spec.feed
        s.stepDown = spec.stepDown
        s.stepOver = spec.stepOver
        s.safeZ = spec.safeZ
        s.faceTool = spec.faceTool; s.faceDia = spec.faceDia
        s.contourTool = spec.contourTool; s.contourDia = spec.contourDia
        s.holeTool = spec.holeTool; s.holeDia = spec.holeDia
        s.pocketTool = spec.pocketTool; s.pocketDia = spec.pocketDia
        s.tapTool = spec.tapTool; s.tapDia = spec.tapDia
        s.postName = spec.postName
        spec = s
        showToastView(result.note)
        if !result.warnings.isEmpty {
            opCodeTitle = "\(kind) 导入提示"
            opCodeText = result.warnings.joined(separator: "\n")
            showOpCode = true
        }
    }

    private func exportDXF() {
        let b = PartProg.bbox(spec)
        var lines: [String] = []
        func pair(_ code: Int, _ value: String) {
            lines.append(String(format: "%3d", code))
            lines.append(value)
        }
        func point(_ x: Double, _ y: Double, _ z: Double = 0) {
            pair(10, String(format: "%.4f", x))
            pair(20, String(format: "%.4f", y))
            pair(30, String(format: "%.4f", z))
        }
        func line(_ a: CGPoint, _ c: CGPoint, layer: String = "0") {
            pair(0, "LINE")
            pair(8, layer)
            point(Double(a.x), Double(a.y))
            point(Double(c.x), Double(c.y))
        }
        func circle(_ x: Double, _ y: Double, _ r: Double) {
            pair(0, "CIRCLE")
            pair(8, "0")
            point(x, y)
            pair(40, String(format: "%.4f", r))
        }
        lines.append("0"); lines.append("SECTION"); lines.append("2"); lines.append("HEADER")
        lines.append("9"); lines.append("$ACADVER"); lines.append("1"); lines.append("AC1009")
        lines.append("0"); lines.append("ENDSEC")
        lines.append("0"); lines.append("SECTION"); lines.append("2"); lines.append("ENTITIES")
        let outer = PartProg.pts(spec)
        if outer.count > 1 {
            for i in 0..<outer.count { line(outer[i], outer[(i + 1) % outer.count]) }
        }
        // 凸台/型腔台阶也必须进 DXF，否则出图和模型不一致
        for s in spec.steps {
            let pts = PartProg.pts(s, spec)
            guard pts.count > 1 else { continue }
            let layer = s.mode == .add ? "BOSS_ADD" : "BOSS_CUT"
            for i in 0..<pts.count { line(pts[i], pts[(i + 1) % pts.count], layer: layer) }
        }
        for l in spec.innerLoops {
            let p = PartProg.drawForLoop(l, spec,
                                         depth: l.through ? spec.height : l.depth,
                                         dia: max(spec.pocketDia, 1), hNo: spec.pocketTool)
            let pts = ContourGeo.flatten(ContourGeo.segments(ContourGeo.buildNodes(p)))
                .map { CGPoint(x: Double($0.x) + l.cx, y: Double($0.y) + l.cy) }
            if pts.count > 1 {
                for i in 0..<pts.count { line(pts[i], pts[(i + 1) % pts.count]) }
            }
        }
        for f in spec.feats where !f.suppressed {
            if f.kind == .hole {
                circle(f.x, f.y, f.dia / 2)
            } else if f.kind == .pocket {
                circle(f.x, f.y, f.dia / 2)
            } else {
                let x0 = f.x - f.w / 2, x1 = f.x + f.w / 2
                let y0 = f.y - f.h / 2, y1 = f.y + f.h / 2
                line(CGPoint(x: x0, y: y0), CGPoint(x: x1, y: y0))
                line(CGPoint(x: x1, y: y0), CGPoint(x: x1, y: y1))
                line(CGPoint(x: x1, y: y1), CGPoint(x: x0, y: y1))
                line(CGPoint(x: x0, y: y1), CGPoint(x: x0, y: y0))
            }
        }
        lines.append("0"); lines.append("ENDSEC"); lines.append("0"); lines.append("EOF")
        let name = "MacroGen-\(Int(Double(b.width)))x\(Int(Double(b.height))).dxf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            dxfExportURL = url
            showToastView("已导出 DXF：\(name)")
        } catch {
            showToastView("DXF 导出失败：\(error.localizedDescription)")
        }
    }

    private func exportDrawing() {
        let renderer = ImageRenderer(content: drawingCanvas.frame(width: 1200, height: 900))
        renderer.scale = 1.0
        guard let image = renderer.uiImage, let data = image.pngData() else {
            drawingExportURL = nil
            showToastView("导出失败：尺寸图渲染为空")
            return
        }
        let b = PartProg.bbox(spec)
        let name = "MacroGen-尺寸图-\(Int(Double(b.width)))x\(Int(Double(b.height)))x\(Int(PartProg.maxZ(spec) - PartProg.minZ(spec))).png"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            drawingExportURL = url
            showToastView("已导出：\(name)")
        } catch {
            showToastView("导出失败：\(error.localizedDescription)")
        }
    }

    private func copyDrawingSummary() {
        let b = PartProg.bbox(spec)
        let holes = spec.feats.filter { $0.kind == .hole }.count
        let pockets = spec.feats.filter { $0.kind != .hole }.count
        var lines: [String] = []
        lines.append("MacroGen 尺寸清单")
        lines.append("外形 L×W×H = \(ncf(Double(b.width))) × \(ncf(Double(b.height))) × \(ncf(PartProg.maxZ(spec) - PartProg.minZ(spec))) mm")
        lines.append("孔 \(holes) 个，型腔 \(pockets) 个，草图内轮廓 \(spec.innerLoops.count) 个")
        for (i, s) in spec.steps.enumerated() {
            lines.append("台阶\(i + 1) \(s.name)：\(s.mode.rawValue) \(s.shape.summary) Z\(ncf(s.drawBottom))~\(ncf(s.drawTop))")
        }
        for (i, f) in spec.feats.enumerated() {
            if f.kind == .rectPocket {
                lines.append("方腔\(i + 1)：\(ncf(f.w))×\(ncf(f.h)) 深\(ncf(f.depth)) @X\(ncf(f.x)) Y\(ncf(f.y))")
            } else {
                lines.append("\(f.kind == .hole ? "孔" : "圆腔")\(i + 1)：Ø\(ncf(f.dia)) 深\(ncf(f.depth)) @X\(ncf(f.x)) Y\(ncf(f.y))")
            }
        }
        UIPasteboard.general.string = lines.joined(separator: "\n")
        showToastView("尺寸清单已复制")
    }

    private func drawDrawing(context: GraphicsContext, size: CGSize) {
        var ctx = context
        let b = PartProg.bbox(spec)
        let pts = PartProg.pts(spec)
        let pad = 44.0
        let k = min((Double(size.width) - pad * 2) / max(Double(b.width), 1),
                    (Double(size.height) - pad * 2) / max(Double(b.height), 1))
        let ox = size.width / 2, oy = size.height / 2
        func P(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: ox + (x - Double(b.midX)) * k, y: oy - (y - Double(b.midY)) * k)
        }

        var path = Path()
        if let f = pts.first { path.move(to: P(f.x, f.y)) }
        for q in pts.dropFirst() { path.addLine(to: P(q.x, q.y)) }
        ctx.stroke(path, with: .color(.orange), lineWidth: 2)

        for s in spec.steps {
            let sp = PartProg.shapePoints(s.shape, spec)
            guard sp.count > 2 else { continue }
            var spPath = Path()
            if let f = sp.first { spPath.move(to: P(Double(f.x), Double(f.y))) }
            for q in sp.dropFirst() { spPath.addLine(to: P(Double(q.x), Double(q.y))) }
            spPath.closeSubpath()
            ctx.stroke(spPath, with: .color(s.mode == .add ? .green : .red),
                       style: StrokeStyle(lineWidth: 1.2, dash: s.mode == .cut ? [3, 2] : []))
            let c = P(sp.reduce(0.0) { $0 + Double($1.x) } / Double(sp.count),
                      sp.reduce(0.0) { $0 + Double($1.y) } / Double(sp.count))
            ctx.draw(Text("\(s.name) Z\(ncf(s.drawBottom))~\(ncf(s.drawTop))")
                        .font(.system(size: 8)).foregroundColor(s.mode == .add ? .green : .red),
                     at: CGPoint(x: c.x, y: c.y - 10))
        }

        for l in spec.innerLoops {
            let d = PartProg.drawForLoop(l, spec, depth: l.through ? spec.height + 1 : l.depth,
                                         dia: max(spec.pocketDia, 1), hNo: spec.pocketTool)
            let flat = ContourGeo.flatten(ContourGeo.segments(ContourGeo.buildNodes(d)), arcStep: 24)
            var lp = Path()
            if let f = flat.first { lp.move(to: P(f.x + l.cx, f.y + l.cy)) }
            for q in flat.dropFirst() { lp.addLine(to: P(q.x + l.cx, q.y + l.cy)) }
            ctx.stroke(lp, with: .color(.red), style: StrokeStyle(lineWidth: 1.4, dash: [4, 3]))
            let text: String
            switch l.template {
            case .circle: text = "Ø" + ncf(l.circleD)
            case .rect: text = ncf(l.rectL) + "×" + ncf(l.rectW)
            case .slot: text = ncf(l.slotL) + "×" + ncf(l.slotW)
            case .free: text = l.name
            }
            ctx.draw(Text(text).font(.system(size: 9)).foregroundColor(.red),
                     at: CGPoint(x: P(l.cx, l.cy).x, y: P(l.cx, l.cy).y - 10))
        }

        for f in spec.feats where !f.suppressed {
            if f.kind == .rectPocket {
                var rp = Path()
                rp.addRect(CGRect(x: P(f.x - f.w / 2, f.y - f.h / 2).x,
                                  y: P(f.x - f.w / 2, f.y + f.h / 2).y,
                                  width: CGFloat(f.w) * k, height: CGFloat(f.h) * k))
                ctx.stroke(rp, with: .color(.orange), lineWidth: 1.4)
                ctx.draw(Text("\(ncf(f.w))×\(ncf(f.h))").font(.system(size: 9)).foregroundColor(.blue),
                         at: CGPoint(x: P(f.x, f.y).x, y: P(f.x, f.y).y - 12))
                continue
            }
            let r = f.dia / 2
            var c = Path()
            for i in 0...30 {
                let a = Double(i) / 30 * 2 * Double.pi
                let q = P(f.x + r * cos(a), f.y + r * sin(a))
                if i == 0 { c.move(to: q) } else { c.addLine(to: q) }
            }
            ctx.stroke(c, with: .color(f.kind == .hole ? .black : .orange), lineWidth: 1.4)
            ctx.draw(Text("Ø\(ncf(f.dia))").font(.system(size: 9)).foregroundColor(.blue),
                 at: CGPoint(x: P(f.x, f.y).x, y: P(f.x, f.y).y - 12))
            if f.kind == .pocket {
                ctx.draw(Text("深\(ncf(f.depth))").font(.system(size: 8)).foregroundColor(Color.gray),
                 at: CGPoint(x: P(f.x, f.y).x, y: P(f.x, f.y).y + 12))
            }
        }

        drawDim(ctx, from: P(Double(b.minX), Double(b.minY) - 8), to: P(Double(b.maxX), Double(b.minY) - 8),
                text: "长 \(ncf(Double(b.width)))")
        drawDim(ctx, from: P(Double(b.minX) - 8, Double(b.minY)), to: P(Double(b.minX) - 8, Double(b.maxY)),
                text: "宽 \(ncf(Double(b.height)))")
        ctx.draw(Text("总高 \(ncf(PartProg.maxZ(spec) - PartProg.minZ(spec)))").font(.system(size: 10, weight: .medium)).foregroundColor(.blue),
                 at: CGPoint(x: ox, y: Double(size.height) - 22))
    }

    // MARK: - 4 加工

    private var hasHoleFeature: Bool {
        spec.feats.contains { $0.kind == .hole }
            || spec.innerLoops.contains { $0.template == .circle && $0.through }
    }

    private var hasPocketFeature: Bool {
        spec.feats.contains { $0.kind != .hole }
            || spec.innerLoops.contains { !($0.template == .circle && $0.through) }
    }

    private func openOp(_ name: String) {
        opSheetName = name
        showOpSheet = true
    }

    private func openOp(for text: String) {
        if text.contains("平面铣") { openOp("平面铣") }
        else if text.contains("轮廓铣") { openOp("轮廓铣") }
        else if text.contains("螺旋铣") { openOp("螺旋铣") }
        else if text.contains("型腔铣") { openOp("型腔铣") }
        else if text.contains("攻丝") { openOp("攻丝") }
        else if text.contains("钻") { openOp("钻孔") }
    }

    // MARK: - 2D 刀路检查

    private var cam2DPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("2D 刀路检查", systemImage: "square.on.square")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Button {
                    cam2DZoom = max(0.5, cam2DZoom - 0.25)
                    cam2DZoomBase = cam2DZoom
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.bordered)
                Text("\(Int(cam2DZoom * 100))%")
                    .font(.system(size: 10, design: .monospaced))
                    .frame(width: 38)
                Button {
                    cam2DZoom = min(4.0, cam2DZoom + 0.25)
                    cam2DZoomBase = cam2DZoom
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.bordered)
                Button("复位") { resetCam2DView() }
                    .font(.system(size: 10, weight: .semibold))
                    .buttonStyle(.bordered)
            }
            Canvas { context, size in
                drawCam2D(context: context, size: size)
            }
            .frame(height: 300)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.separator).opacity(0.5), lineWidth: 0.6))
            .highPriorityGesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { g in
                        cam2DPanX = Double(cam2DPanStart.width) + Double(g.translation.width)
                        cam2DPanY = Double(cam2DPanStart.height) + Double(g.translation.height)
                    }
                    .onEnded { _ in
                        cam2DPanStart = CGSize(width: cam2DPanX, height: cam2DPanY)
                    }
            )
            .simultaneousGesture(MagnificationGesture()
                .onChanged { v in cam2DZoom = min(4.0, max(0.5, cam2DZoomBase * Double(v))) }
                .onEnded { _ in cam2DZoomBase = cam2DZoom }
            )
            .onTapGesture(count: 2) { resetCam2DView() }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip("毛坯", cam2DStock) { cam2DStock.toggle() }
                    chip("零件", cam2DPart) { cam2DPart.toggle() }
                    chip("草图", cam2DSketch) { cam2DSketch.toggle() }
                    chip("刀路", cam2DToolpath) { cam2DToolpath.toggle() }
                    chip("快移", cam2DRapid) { cam2DRapid.toggle() }
                    chip("层切", cam2DLayerOnly) { cam2DLayerOnly.toggle() }
                }
            }
            if cam2DLayerOnly {
                let lo = PartProg.minZ(spec), hi = max(PartProg.maxZ(spec), lo + 0.1)
                Slider(value: $cam2DLayerZ, in: lo...hi)
                Text("层切查看 Z\(ncf(cam2DLayerZ))（只显示该层附近的刀路，不是材料切除仿真）")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }
            Text("俯视示意：青色是切削中心线，灰色虚线是快移。单指拖动平移、双指缩放、双击复位。")
                .font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }

    private func resetCam2DView() {
        cam2DZoom = 1.0
        cam2DZoomBase = 1.0
        cam2DPanX = 0
        cam2DPanY = 0
        cam2DPanStart = .zero
    }

    private func drawCam2D(context: GraphicsContext, size: CGSize) {
        guard size.width > 10, size.height > 10 else { return }
        let b = cam2DStock ? PartProg.stockBBox(spec) : PartProg.bbox(spec)
        let w = Double(size.width), h = Double(size.height)
        let bw = Double(b.width), bh = Double(b.height)
        guard bw > 0.1, bh > 0.1 else {
            context.draw(Text("还没有可检查的轮廓").font(.system(size: 11)).foregroundColor(.secondary),
                         at: CGPoint(x: size.width / 2, y: size.height / 2))
            return
        }
        let margin = max(12.0, max(bw, bh) * 0.08)
        let baseScale = min((w - 2 * margin) / bw, (h - 2 * margin) / bh)
        let scale = baseScale * cam2DZoom
        let ox = (w - bw * scale) / 2 + cam2DPanX - Double(b.minX) * scale
        let oy = (h - bh * scale) / 2 + cam2DPanY + Double(b.maxY) * scale
        let cx = ox + Double(b.midX) * scale
        let cy = oy - Double(b.midY) * scale

        func p(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: CGFloat(ox + x * scale), y: CGFloat(oy - y * scale))
        }
        func path(_ pts: [CGPoint]) -> Path {
            var pth = Path()
            guard let f = pts.first else { return pth }
            pth.move(to: p(Double(f.x), Double(f.y)))
            for q in pts.dropFirst() { pth.addLine(to: p(Double(q.x), Double(q.y))) }
            return pth
        }
        func closed(_ pts: [CGPoint]) -> Path {
            var pth = path(pts)
            if pts.count > 2 { pth.closeSubpath() }
            return pth
        }
        func circle(_ x: Double, _ y: Double, _ dia: Double) -> Path {
            let r = CGFloat(max(0.7, dia * scale / 2))
            let q = p(x, y)
            return Path(ellipseIn: CGRect(x: q.x - r, y: q.y - r, width: r * 2, height: r * 2))
        }

        if cam2DStock {
            let r = CGRect(x: p(Double(b.minX), Double(b.maxY)).x,
                           y: p(Double(b.minX), Double(b.maxY)).y,
                           width: CGFloat(bw * scale), height: CGFloat(bh * scale))
            let stockPath = Path { pth in pth.addRect(r) }
            context.fill(stockPath, with: .color(Color(white: 0.80).opacity(0.16)))
            context.stroke(stockPath, with: .color(Color(white: 0.45)), lineWidth: 1)
            let sz = PartProg.stockZRange(spec)
            context.draw(Text("毛坯 \(ncf(bw))×\(ncf(bh))  Z\(ncf(sz.bottom))~\(ncf(sz.top))")
                            .font(.system(size: 8)).foregroundColor(.secondary),
                         at: CGPoint(x: r.minX + 4, y: r.minY - 6))
        }

        if cam2DPart {
            context.fill(closed(PartProg.pts(spec)), with: .color(studioBlue.opacity(0.15)))
            context.stroke(closed(PartProg.pts(spec)), with: .color(studioBlue), lineWidth: 1.6)
            for s in spec.steps {
                let sp = PartProg.pts(s, spec)
                guard sp.count > 2 else { continue }
                let tint = s.mode == .add ? Color.green : Color.red
                context.fill(closed(sp), with: .color(tint.opacity(0.13)))
                context.stroke(closed(sp), with: .color(tint.opacity(0.85)),
                               style: StrokeStyle(lineWidth: 1.2, dash: s.mode == .cut ? [3, 2] : []))
                let q = p(sp.reduce(0.0) { $0 + Double($1.x) } / Double(sp.count),
                          sp.reduce(0.0) { $0 + Double($1.y) } / Double(sp.count))
                context.draw(Text("\(s.name) Z\(ncf(s.drawBottom))~\(ncf(s.drawTop))")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundColor(tint),
                             at: CGPoint(x: q.x, y: q.y - 9))
            }
            for f in spec.feats where !f.suppressed {
                if f.kind == .hole {
                    context.fill(circle(f.x, f.y, f.dia), with: .color(Color(white: 0.2).opacity(0.55)))
                    context.stroke(circle(f.x, f.y, f.dia), with: .color(Color(white: 0.3)), lineWidth: 1)
                } else if f.kind == .rectPocket {
                    let r = CGRect(x: p(f.x - f.w / 2, f.y + f.h / 2).x,
                                   y: p(f.x - f.w / 2, f.y + f.h / 2).y,
                                   width: CGFloat(f.w * scale), height: CGFloat(f.h * scale))
                    context.stroke(Path { pth in pth.addRect(r) }, with: .color(.orange), lineWidth: 1.2)
                } else {
                    context.stroke(circle(f.x, f.y, f.dia), with: .color(.orange), lineWidth: 1.2)
                }
            }
            for l in spec.innerLoops {
                let lp = PartProg.loopPoints(l).map {
                    CGPoint(x: $0.x + CGFloat(l.cx), y: $0.y + CGFloat(l.cy))
                }
                context.stroke(closed(lp), with: .color(.red.opacity(0.8)), lineWidth: 1.1)
            }
        }

        if cam2DSketch {
            context.stroke(closed(PartProg.pts(spec)), with: .color(.orange),
                           style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            for s in spec.steps {
                let sp = PartProg.pts(s, spec)
                guard sp.count > 2 else { continue }
                context.stroke(closed(sp), with: .color(.orange.opacity(0.7)),
                               style: StrokeStyle(lineWidth: 0.9, dash: [3, 3]))
            }
            for l in spec.innerLoops {
                let lp = PartProg.loopPoints(l).map {
                    CGPoint(x: $0.x + CGFloat(l.cx), y: $0.y + CGFloat(l.cy))
                }
                context.stroke(closed(lp), with: .color(.orange.opacity(0.8)),
                               style: StrokeStyle(lineWidth: 0.9, dash: [3, 3]))
            }
        }

        if cam2DToolpath || cam2DRapid {
            for seg in cam2DPaths where !cam2DLayerOnly || abs(seg.z - cam2DLayerZ) <= max(0.2, spec.stepDown / 2) {
                if seg.cut && !cam2DToolpath { continue }
                if !seg.cut && !cam2DRapid { continue }
                let sp = seg.pts.map { p(Double($0.x), Double($0.y)) }
                if sp.count == 1 {
                    let q = sp[0]
                    context.fill(Path(ellipseIn: CGRect(x: q.x - 1.5, y: q.y - 1.5, width: 3, height: 3)),
                                 with: .color(seg.cut ? Color.cyan : Color.gray.opacity(0.6)))
                    continue
                }
                if seg.cut {
                    context.stroke(path(seg.pts), with: .color(.cyan), lineWidth: 1.1)
                } else {
                    context.stroke(path(seg.pts), with: .color(Color.gray.opacity(0.55)),
                                   style: StrokeStyle(lineWidth: 0.8, dash: [3, 2]))
                }
            }
        }

        context.draw(Text("Z0").font(.system(size: 8, weight: .bold)).foregroundColor(.secondary),
                     at: CGPoint(x: cx, y: cy + 12))
    }

    private func cacheIsStale(_ id: String) -> Bool {
        guard opCodeCache[id] != nil else { return false }
        return opCacheSpecs[id] != spec
    }

    private func opStatusText(_ op: PartOpInfo) -> String {
        if cacheIsStale(op.id), op.status != .disabled, op.status != .modelOnly {
            return "需重算"
        }
        switch op.status {
        case .disabled: return "已禁用"
        case .modelOnly: return "仅建模"
        case .stale: return "需重算"
        case .ready: return opGenerated ? "已生成" : "可生成"
        }
    }

    private func opStatusColor(_ op: PartOpInfo) -> Color {
        if cacheIsStale(op.id), op.status != .disabled, op.status != .modelOnly {
            return .red
        }
        switch op.status {
        case .disabled: return .gray
        case .modelOnly: return .orange
        case .stale: return .red
        case .ready: return opGenerated ? .green : studioBlue
        }
    }

    private func setupSheetText() -> String {
        let ops = PartProg.ops(spec)
        let sb = PartProg.stockBBox(spec)
        let sz = PartProg.stockZRange(spec)
        var lines: [String] = []
        lines.append("MacroGen 工序单")
        lines.append("工程：\(spec.projectName)")
        lines.append("毛坯：\(ncf(Double(sb.width)))×\(ncf(Double(sb.height)))  Z\(ncf(sz.bottom))~\(ncf(sz.top))")
        lines.append("工件坐标：G\(spec.coord)  X0=\(ncf(spec.originX)) Y0=\(ncf(spec.originY))  Z0=基础顶面")
        lines.append("材料：请按现场填写；后处理：\(spec.postName)")
        lines.append("")
        lines.append("序号  T/D        工序                  Z范围                 状态")
        for (i, op) in ops.enumerated() {
            let td = "T\(op.tool)/D\(ncf(op.dia))"
            let title = op.title + " " + op.kind
            lines.append("\(String(format: "%2d", i + 1))  \(td)  \(title)  Z\(op.zRange)  \(opStatusText(op))")
        }
        lines.append("")
        lines.append("检查：")
        let issues = PartProg.issues(spec)
        if issues.isEmpty { lines.append("无") }
        for s in issues { lines.append("- " + s) }
        return lines.joined(separator: "\n")
    }

    private func moveOp(_ id: String, _ delta: Int) {
        var ids = PartProg.ops(spec).map(\.id)
        guard let idx = ids.firstIndex(of: id) else { return }
        let to = idx + delta
        guard to >= 0, to < ids.count else { return }
        pushUndo()
        ids.swapAt(idx, to)
        spec.opOrder = ids
        showToastView("工序顺序已调整")
    }

    private func resetOpOrder() {
        guard !spec.opOrder.isEmpty else { return }
        pushUndo()
        spec.opOrder = []
        showToastView("工序已恢复自动顺序")
    }

    private var camOverviewCard: some View {
        let ops = PartProg.ops(spec)
        let cutLen = cam2DPaths.filter { $0.cut }.reduce(0) { $0 + $1.len }
        let rapidLen = cam2DPaths.filter { !$0.cut }.reduce(0) { $0 + $1.len }
        let minutes = cutLen / Double(max(spec.feed, 1)) + rapidLen / 5000
        let issues = PartProg.issues(spec)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("程序概览")
                        .font(.system(size: 15, weight: .bold))
                    Text("先看刀路，再生成程序；参数还在下面逐项可改")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { generateProgram() } label: {
                    Label("生成程序", systemImage: "function")
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(studioBlue))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 6) {
                camMetric("工序", "\(ops.count)", "道")
                camMetric("切削", ncf(cutLen), "mm")
                camMetric("快移", ncf(rapidLen), "mm")
                camMetric("估算", camDuration(minutes), "")
            }

            if issues.isEmpty {
                Label("没有发现明显问题，可以先生成看刀路", systemImage: "checkmark.seal")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.green)
            } else {
                Label("有 \(issues.count) 条检查项，先看下面的“检查”", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(studioBlue.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(studioBlue.opacity(0.16), lineWidth: 1)
        )
    }

    private func camMetric(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 8.5))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 8.5))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.8)))
    }

    private func camDuration(_ minutes: Double) -> String {
        let total = max(0, Int((minutes * 60).rounded()))
        return "\(total / 60)m\(total % 60)s"
    }

    private func generateProgram() {
        var validCache: [String: String] = [:]
        var expiredIDs: [String] = []
        for (id, text) in opCodeCache {
            if opCacheSpecs[id] == spec { validCache[id] = text }
            else { expiredIDs.append(id) }
        }
        code = PartProg.build(spec, prebuilt: validCache)
        opGenerated = true
        for id in expiredIDs {
            opCodeCache.removeValue(forKey: id)
            opCacheSpecs.removeValue(forKey: id)
        }
        showResult = true
    }

    private var camPage: some View {
        Group {
            Section {
                camOverviewCard
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    .listRowBackground(Color.clear)
            }

            Section("2D 刀路检查") {
                cam2DPanel
            }

            Section("毛坯（独立于零件）") {
                Toggle("显示毛坯", isOn: $spec.showStock)
                numRow("XY 单边余量 (mm)", $spec.stockMarginXY)
                numRow("顶面余量 (mm)", $spec.stockExtraTop)
                numRow("底面余量 (mm)", $spec.stockExtraBottom)
                let bb = PartProg.stockBBox(spec)
                let sz = PartProg.stockZRange(spec)
                Text("毛坯 \(ncf(Double(bb.width)))×\(ncf(Double(bb.height)))  Z\(ncf(sz.bottom))~\(ncf(sz.top))；毛坯外形按零件包围盒加余量。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("工件坐标系 / 程序") {
                HStack {
                    Text("程序号 O")
                    Spacer()
                    TextField("1010", value: $spec.programNo, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }
                Toggle("程序尾 M01 可选停", isOn: $spec.optionalStop)
                Picker("后处理 / 控制器", selection: $spec.postName) {
                    Text("FANUC 0i-MF").tag("FANUC")
                    Text("三菱 M70/M80").tag("三菱 M70/M80")
                    Text("Siemens 840D（宏展开）").tag("Siemens 840D")
                }
                if spec.postName.contains("Siemens") {
                    Text("Siemens 会把 #宏/WHILE 展开成普通 G 代码；G43/G28/G52 和刀补仍需按机床核对。")
                        .font(.caption).foregroundStyle(.orange)
                }
                Picker("坐标系", selection: $spec.coord) {
                    ForEach([54, 55, 56, 57, 58, 59], id: \.self) { n in Text("G\(n)").tag(n) }
                }
                let bb = PartProg.bbox(spec)
                HStack(spacing: 6) {
                    Button("左下角") {
                        spec.originX = Double(bb.minX)
                        spec.originY = Double(bb.minY)
                    }
                    Button("中心") {
                        spec.originX = Double(bb.midX)
                        spec.originY = Double(bb.midY)
                    }
                    Button("取指针") {
                        if hasPtr {
                            spec.originX = ptrX
                            spec.originY = ptrY
                            showToastView("X0/Y0 已取指针点 X\(ncf(ptrX)) Y\(ncf(ptrY))")
                        } else {
                            showToastView("先到建模页点一下顶面取 XY，或直接改下方 X0/Y0")
                        }
                    }
                }
                .buttonStyle(.bordered)
                .font(.system(size: 12, weight: .semibold))
                HStack(spacing: 6) {
                    miniNum("X0", $spec.originX)
                    miniNum("Y0", $spec.originY)
                }
                Text("当前 X0=\(ncf(spec.originX))  Y0=\(ncf(spec.originY))（草图坐标）  Z0=工件顶面")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("加工工序（自动识别）") {
                let hasHole = hasHoleFeature
                let hasPocket = hasPocketFeature
                HStack {
                    Toggle("平面铣（顶面余量 > 0）", isOn: $spec.doFace)
                        .disabled(spec.topStock <= 0)
                    Button("参数") { openOp("平面铣") }.buttonStyle(.borderless)
                        .font(.system(size: 12, weight: .semibold))
                }
                HStack {
                    Toggle("轮廓铣（闭合外形）", isOn: $spec.doContour)
                    Button("参数") { openOp("轮廓铣") }.buttonStyle(.borderless)
                        .font(.system(size: 12, weight: .semibold))
                }
                Toggle("外轮廓反向（顺/逆铣）", isOn: $spec.reverseOuter)
                    .font(.system(size: 12))
                HStack {
                    Text("轮廓起点序号").font(.system(size: 12))
                    Stepper("", value: $spec.contourStartNode,
                            in: 0...max(0, spec.nodes.count - 1))
                        .labelsHidden()
                    Text("\(spec.contourStartNode)").font(.system(size: 12, design: .monospaced))
                }
                HStack {
                    Toggle("轮廓倒角 C（2.5D 近似）", isOn: $spec.doChamfer)
                        .font(.system(size: 12))
                    numRow("C (mm)", $spec.chamferSize)
                        .frame(width: 120)
                }
                if spec.doChamfer {
                    Text("沿基础外形顶边走一刀，用于去毛刺/倒角近似；不生成真实斜面。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Toggle("残料清角 / 二次开粗（2.5D 近似）", isOn: $spec.doRest)
                        .font(.system(size: 12))
                    Spacer()
                }
                if spec.doRest {
                    toolRow("残料", $spec.restTool, $spec.restDia)
                    Text("基础外形/台阶沿边界补刀；方腔按上一把大刀的 2D 刀路扫掠差集，只有真检测到残料才整腔二次开粗；圆腔/孔整圆清一次。仍是 2.5D，不是 3D 实体布尔。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Toggle("螺旋铣", isOn: Binding(get: { spec.doHole && spec.holeMode == .spiral },
                                                set: { v in
                                                    spec.doHole = v && hasHole
                                                    if v && hasHole { spec.holeMode = .spiral }
                                                }))
                        .disabled(!hasHole)
                    Button("参数") { openOp("螺旋铣") }.buttonStyle(.borderless)
                        .font(.system(size: 12, weight: .semibold))
                }
                HStack {
                    Toggle("型腔铣", isOn: $spec.doPocket)
                        .disabled(!hasPocket)
                    Button("参数") { openOp("型腔铣") }.buttonStyle(.borderless)
                        .font(.system(size: 12, weight: .semibold))
                }
                HStack {
                    Toggle("钻孔", isOn: Binding(get: { spec.doHole && (spec.holeMode == .g81 || spec.holeMode == .g83) },
                                                set: { v in
                                                    spec.doHole = v && hasHole
                                                    if v && hasHole && !(spec.holeMode == .g81 || spec.holeMode == .g83) {
                                                        spec.holeMode = .g83
                                                    }
                                                }))
                        .disabled(!hasHole)
                    Picker("", selection: $spec.holeMode) {
                        Text("G81").tag(HoleMode.g81)
                        Text("G83").tag(HoleMode.g83)
                        Text("G84").tag(HoleMode.tap)
                    }
                    .labelsHidden()
                    .frame(width: 86)
                    Button("参数") { openOp("钻孔") }.buttonStyle(.borderless)
                        .font(.system(size: 12, weight: .semibold))
                }
                HStack {
                    Toggle("攻丝", isOn: Binding(get: { spec.doHole && spec.holeMode == .tap },
                                                set: { v in
                                                    spec.doHole = v && hasHole
                                                    if v && hasHole { spec.holeMode = .tap }
                                                }))
                        .disabled(!hasHole)
                    Button("参数") { openOp("攻丝") }.buttonStyle(.borderless)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(hasHole ? "图上识别到孔：可钻孔/螺旋铣/攻丝" : "图上没有孔，孔相关工序已锁")
                    .font(.caption).foregroundStyle(.secondary)
                Text(hasPocket ? "图上识别到型腔/内轮廓：可型腔铣" : "图上没有型腔，型腔铣已锁")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("工序导航器（CAM）") {
                let ops = PartProg.ops(spec)
                HStack {
                    Label("PROGRAM", systemImage: "list.bullet.indent")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Text("T/D · S/F · Z")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("\(ops.count) 道")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    if !spec.opOrder.isEmpty {
                        Button("自动顺序") { resetOpOrder() }
                            .font(.system(size: 9, weight: .semibold))
                            .buttonStyle(.borderless)
                    }
                }
                if ops.isEmpty {
                    Text("没有工序：检查上面的开关和模型").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(ops) { op in
                        let i = (ops.firstIndex(where: { $0.id == op.id }) ?? 0) + 1
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 7) {
                                Text(i == ops.count ? "└" : "├")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Text("\(i)")
                                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                                    .frame(width: 18, height: 18)
                                    .background(Circle().fill(Color(red: 1.0, green: 0.42, blue: 0.10)))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(op.title).font(.system(size: 13, weight: .semibold))
                                    Text(op.kind).font(.system(size: 9)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if opCodeCache[op.id] != nil {
                                    Text(cacheIsStale(op.id) ? "缓存待重算" : "已缓存")
                                        .font(.system(size: 8, weight: .semibold))
                                        .padding(.horizontal, 5).padding(.vertical, 2)
                                        .background(Capsule().fill((cacheIsStale(op.id) ? Color.orange : Color.green).opacity(0.12)))
                                        .foregroundStyle(cacheIsStale(op.id) ? .orange : .green)
                                }
                                Text(opStatusText(op))
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 6).padding(.vertical, 3)
                                    .background(Capsule().fill(opStatusColor(op).opacity(0.14)))
                                    .foregroundStyle(opStatusColor(op))
                            }
                            Text(op.geometry)
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                                .lineLimit(2)
                            HStack(spacing: 8) {
                                Text("T\(op.tool) D\(ncf(op.dia))")
                                Text("S\(op.spindle) F\(op.feed)")
                                Text(op.zRange)
                            }
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                if op.status != .modelOnly {
                                    Button { moveOp(op.id, -1) } label: {
                                        Image(systemName: "chevron.up").font(.system(size: 9))
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(i == 1)
                                    Button { moveOp(op.id, 1) } label: {
                                        Image(systemName: "chevron.down").font(.system(size: 9))
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(i == ops.count)
                                    Button(op.status == .disabled ? "启用" : "禁用") {
                                        pushUndo()
                                        if spec.disabledOps.contains(op.id) {
                                            spec.disabledOps.remove(op.id)
                                        } else {
                                            spec.disabledOps.insert(op.id)
                                        }
                                    }
                                    .font(.system(size: 10, weight: .semibold))
                                    .buttonStyle(.bordered)
                                }
                                Button("单独重算") {
                                    guard op.status != .modelOnly else {
                                        showToastView("\(op.title) 仅参与建模，不生成刀路")
                                        return
                                    }
                                    let single = PartProg.build(spec, only: [op.id])
                                    opCodeTitle = op.title
                                    opCodeText = single
                                    opCodeCache[op.id] = single
                                    opCacheSpecs[op.id] = spec
                                    showOpCode = true
                                }
                                .font(.system(size: 10, weight: .semibold))
                                .buttonStyle(.bordered)
                                if op.status == .modelOnly {
                                    Text("不生成刀路").font(.system(size: 9)).foregroundStyle(.orange)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                if opGenerated {
                    Text("已按当前参数生成；改动参数后会自动回到“可生成”。")
                        .font(.system(size: 9)).foregroundStyle(.green)
                } else if !ops.isEmpty {
                    Text("点“生成程序”后为已生成；每道工序可单独重算，重算结果会优先合并进最终程序。")
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Button {
                        opCodeTitle = "工序单 / 刀具单"
                        opCodeText = setupSheetText()
                        showOpCode = true
                    } label: {
                        Label("查看工序单 / 刀具单", systemImage: "list.clipboard")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    ShareLink(item: setupSheetText()) {
                        Label("分享工序单", systemImage: "square.and.arrow.up")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                }

                if !opCodeCache.isEmpty {
                    let stale = opCodeCache.keys.filter { cacheIsStale($0) }.count
                    Text(stale > 0
                         ? "已缓存 \(opCodeCache.count) 段；\(stale) 段因参数改动待重算，生成程序时只用未过期缓存。"
                         : "已缓存 \(opCodeCache.count) 段单工序程序；改参数会标记需重算，不会直接清掉。")
                        .font(.system(size: 9)).foregroundStyle(stale > 0 ? .orange : .green)
                }
            }

            Section("工序树（按刀具）") {
                let ops = PartProg.ops(spec)
                let groups = Dictionary(grouping: ops, by: { $0.tool })
                    .map { ToolOpGroup(id: $0.key, ops: $0.value) }
                    .sorted { $0.id < $1.id }
                if ops.isEmpty {
                    Text("没有工序：先在上面打开加工方式，或在建模页加孔/型腔。")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(groups) { group in
                        let list = group.ops
                        DisclosureGroup {
                            ForEach(list, id: \.id) { op in
                                toolOpTreeRow(op)
                            }
                        } label: {
                            toolGroupLabel(group)
                        }
                    }
                }
                Text("这是按刀具分组的工序树；同一把刀下的粗加工、精加工和孔工序会排在一起。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("刀具库（T / D）") {
                toolRow("顶面", $spec.faceTool, $spec.faceDia)
                toolRow("轮廓", $spec.contourTool, $spec.contourDia)
                toolRow("孔", $spec.holeTool, $spec.holeDia)
                toolRow("型腔", $spec.pocketTool, $spec.pocketDia)
                toolRow("残料", $spec.restTool, $spec.restDia)
                toolRow("攻丝", $spec.tapTool, $spec.tapDia)
                Text("上面是当前工序用的 T/D；下面的刀具库是常用刀具表，换工程也保留。")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach($toolLibrary) { $tool in
                    DisclosureGroup {
                        HStack(spacing: 6) {
                            Text("T").font(.system(size: 11)).foregroundStyle(.secondary)
                            TextField("1", value: $tool.no, format: .number)
                                .keyboardType(.numberPad).frame(width: 36)
                            Text("D").font(.system(size: 11)).foregroundStyle(.secondary)
                            TextField("6", value: $tool.dia, format: .number)
                                .keyboardType(.decimalPad).frame(width: 56)
                            Picker("", selection: $tool.kind) {
                                ForEach(ToolKind.allCases) { k in Text(k.rawValue).tag(k) }
                            }
                            .labelsHidden()
                            .font(.system(size: 11))
                        }
                        HStack(spacing: 6) {
                            Text("S").font(.system(size: 11)).foregroundStyle(.secondary)
                            TextField("2000", value: $tool.rpm, format: .number)
                                .keyboardType(.numberPad).frame(width: 50)
                            Text("F").font(.system(size: 11)).foregroundStyle(.secondary)
                            TextField("400", value: $tool.feed, format: .number)
                                .keyboardType(.numberPad).frame(width: 50)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(["顶面", "轮廓", "孔", "型腔", "攻丝"], id: \.self) { role in
                                    Button(role) { applyTool(tool, to: role) }
                                        .font(.system(size: 10, weight: .semibold))
                                        .buttonStyle(.bordered)
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text(tool.summary).font(.system(size: 12, weight: .semibold))
                            Spacer()
                            Button {
                                pushUndo()
                                toolLibrary.removeAll { $0.id == tool.id }
                                ToolLibraryStore.save(toolLibrary)
                            } label: {
                                Image(systemName: "trash").foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                HStack {
                    Button {
                        toolLibrary.append(ToolRecord(name: "新刀具", no: (toolLibrary.map(\.no).max() ?? 0) + 1))
                        ToolLibraryStore.save(toolLibrary)
                    } label: { Label("添加刀具", systemImage: "plus.circle") }
                    Spacer()
                    Button {
                        syncToolLibraryFromSpec()
                    } label: { Label("同步当前工序", systemImage: "arrow.down.circle") }
                }
                .font(.system(size: 12, weight: .semibold))
                Text("同一 T 号必须对应同一直径；点上面的角色按钮会把该刀具套到对应工序。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .onChange(of: toolLibrary) { newValue in
                ToolLibraryStore.save(newValue)
            }

            Section("切削") {
                numRow("顶面余量 (mm)", $spec.topStock)
                intRow("转速 S", $spec.spindle)
                intRow("进给 F", $spec.feed)
                numRow("每层切深 (mm)", $spec.stepDown)
                numRow("行距 AE (mm)", $spec.stepOver)
                numRow("安全高度 Z", $spec.safeZ)
            }

            if !PartProg.issues(spec).isEmpty {
                Section("检查") {
                    ForEach(PartProg.issues(spec), id: \.self) { t in
                        Label(t, systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                }
            }

            Section {
                Button {
                    generateProgram()
                } label: {
                    HStack {
                        Spacer()
                        Label("生成程序 · 多工序合并", systemImage: "function")
                        Spacer()
                    }
                    .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
    }

    // MARK: - 行 / 小部件

    private func chip(_ text: String, _ on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8).fill(on ? Color.orange.opacity(0.18) : Color(.secondarySystemBackground)))
                .foregroundStyle(on ? .orange : .primary)
        }
        .buttonStyle(.plain)
    }

    private func viewChip(_ text: String, active: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7)
                    .fill(active ? studioBlue.opacity(0.15) : Color(.secondarySystemBackground)))
                .foregroundStyle(active ? studioBlue : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private func numRow(_ title: String, _ value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 96)
        }
    }

    private func autoNumRow(_ title: String, _ value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 96)
                .onChange(of: value.wrappedValue) { _ in scheduleTemplateRebuild() }
        }
    }

    private func intRow(_ title: String, _ value: Binding<Int>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 96)
        }
    }

    private func miniNum(_ title: String, _ value: Binding<Double>) -> some View {
        HStack(spacing: 3) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                .font(.system(size: 13)).frame(width: 52)
        }
    }

    private func toolRow(_ title: String, _ t: Binding<Int>, _ d: Binding<Double>) -> some View {
        HStack(spacing: 6) {
            Text(title).frame(width: 44, alignment: .leading)
            Text("T").font(.system(size: 11)).foregroundStyle(.secondary)
            TextField("1", value: t, format: .number)
                .keyboardType(.numberPad).multilineTextAlignment(.center).frame(width: 34)
            Text("D").font(.system(size: 11)).foregroundStyle(.secondary)
            TextField("6", value: d, format: .number)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 54)
            Spacer()
        }
        .font(.system(size: 14))
    }

    private func toolGroupLabel(_ group: ToolOpGroup) -> some View {
        HStack {
            Text("T\(group.id) · Ø\(ncf(group.ops.first?.dia ?? 0))")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Text("\(group.ops.count) 道")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private func toolOpTreeRow(_ op: PartOpInfo) -> some View {
        HStack(spacing: 8) {
            Text("└")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(op.title)
                    .font(.system(size: 12, weight: .semibold))
                Text(op.kind + " · " + op.zRange)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(op.status == .disabled ? "停" : "开")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(op.status == .disabled ? Color.secondary : Color.green)
        }
    }

    private func applyTool(_ tool: ToolRecord, to role: String) {
        pushUndo()
        switch role {
        case "顶面":
            spec.faceTool = tool.no; spec.faceDia = tool.dia
        case "轮廓":
            spec.contourTool = tool.no; spec.contourDia = tool.dia
        case "孔":
            spec.holeTool = tool.no; spec.holeDia = tool.dia
        case "型腔":
            spec.pocketTool = tool.no; spec.pocketDia = tool.dia
        case "攻丝":
            spec.tapTool = tool.no; spec.tapDia = tool.dia; spec.tapRpm = tool.rpm
        default:
            return
        }
        spec.spindle = tool.rpm
        spec.feed = tool.feed
        showToastView("\(tool.summary) 已套到\(role)工序")
    }

    private func syncToolLibraryFromSpec() {
        let existing: [(String, Int, Double, ToolKind)] = [
            ("顶面", spec.faceTool, spec.faceDia, .flat),
            ("轮廓", spec.contourTool, spec.contourDia, .flat),
            ("孔", spec.holeTool, spec.holeDia, .drill),
            ("型腔", spec.pocketTool, spec.pocketDia, .flat),
            ("攻丝", spec.tapTool, spec.tapDia, .tap)
        ]
        for (name, no, dia, kind) in existing {
            if let i = toolLibrary.firstIndex(where: { $0.no == no && $0.dia == dia }) {
                toolLibrary[i].name = name
                toolLibrary[i].kind = kind
            } else {
                toolLibrary.append(ToolRecord(name: name, no: no, dia: dia, kind: kind,
                                              rpm: spec.spindle, feed: spec.feed))
            }
        }
        ToolLibraryStore.save(toolLibrary)
        showToastView("已把当前工序刀具同步到刀具库")
    }
}

private struct ToolOpGroup: Identifiable {
    let id: Int
    let ops: [PartOpInfo]
}

// MARK: - 3D 相机

private struct Cam {
    let spec: PartSpec
    let yaw: Double
    let pitch: Double
    let zoom: Double
    let panX: Double
    let panY: Double
    let size: CGSize

    // 缓存投影参数：每帧只算一次，避免每个点都重算包围盒和三角函数
    private let cy: Double
    private let sy: Double
    private let sp: Double
    private let cp: Double
    private let kValue: Double
    private let midX: Double
    private let midY: Double

    init(spec: PartSpec, yaw: Double, pitch: Double, zoom: Double,
         panX: Double = 0, panY: Double = 0, size: CGSize) {
        self.spec = spec
        self.yaw = yaw
        self.pitch = pitch
        self.zoom = zoom
        self.panX = panX
        self.panY = panY
        self.size = size

        let b = PartProg.bbox(spec)
        let zTop = PartProg.maxZ(spec)
        let zBottom = PartProg.minZ(spec)
        let c = cos(yaw), s = sin(yaw)
        let sp0 = sin(pitch), cp0 = cos(pitch)
        self.cy = c
        self.sy = s
        self.sp = sp0
        self.cp = cp0

        var mnx = Double.infinity, mxx = -Double.infinity
        var mny = Double.infinity, mxy = -Double.infinity
        for zz in [zTop, zBottom] {
            for (xx, yy) in [(b.minX, b.minY), (b.maxX, b.minY), (b.maxX, b.maxY), (b.minX, b.maxY)] {
                let rx = Double(xx) * c - Double(yy) * s
                let ry = Double(xx) * s + Double(yy) * c
                let sx = rx
                let syy = -(ry * sp0 + zz * cp0)
                mnx = min(mnx, sx); mxx = max(mxx, sx)
                mny = min(mny, syy); mxy = max(mxy, syy)
            }
        }
        self.midX = (mnx + mxx) / 2
        self.midY = (mny + mxy) / 2
        self.kValue = min((Double(size.width) - 52) / max(mxx - mnx, 1),
                           (Double(size.height) - 52) / max(mxy - mny, 1)) * zoom
    }

    func p(_ x: Double, _ y: Double, _ z: Double) -> CGPoint {
        let rx = x * cy - y * sy
        let ry = x * sy + y * cy
        let syy = -(ry * sp + z * cp)
        return CGPoint(x: Double(size.width) / 2 + panX + (rx - midX) * kValue,
                       y: Double(size.height) / 2 + panY + (syy - midY) * kValue)
    }

    func unprojectTop(_ pt: CGPoint) -> (Double, Double) {
        let sp2 = abs(sp) < 0.15 ? (sp < 0 ? -0.15 : 0.15) : sp
        let rx = (Double(pt.x) - Double(size.width) / 2 - panX) / kValue + midX
        let ry = -((Double(pt.y) - Double(size.height) / 2 - panY) / kValue + midY) / sp2
        let x = rx * cy + ry * sy
        let y = -rx * sy + ry * cy
        return (x, y)
    }
}

// MARK: - 整件旋转/缩放

private struct TransformSheet: View {
    @Binding var spec: PartSpec
    let rotate: Bool
    let onUndo: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var value: Double = 90

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(rotate ? "旋转角度（360=整圈）" : "缩放倍数（1.2=放大20%）")
                        Spacer()
                        TextField("0", value: $value, format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                    }
                }
                Section {
                    Text(rotate ? "孔、型腔、基准一起绕零件中心旋转；矩形转 90° 会交换长宽。"
                                : "外形、孔、型腔、深度、厚度一起按倍数缩放。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(rotate ? "旋转整块零件" : "缩放整块零件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用") {
                        if rotate { rotatePart(value) } else { scalePart(value) }
                        dismiss()
                    }
                    .bold()
                }
            }
        }
        .presentationDetents([.height(250)])
    }

    private func rotatePart(_ deg: Double) {
        onUndo()
        let a = deg.truncatingRemainder(dividingBy: 360)
        if spec.template == .rect && abs(a.truncatingRemainder(dividingBy: 90)) < 0.01 {
            if Int(round(a / 90)) % 2 != 0 {
                let t = spec.rectL; spec.rectL = spec.rectW; spec.rectW = t
            }
        } else {
            if spec.template != .free { toFreeNodes() }
            let rad = a * Double.pi / 180
            let ca = cos(rad), sa = sin(rad)
            for i in spec.nodes.indices {
                let x = spec.nodes[i].x, y = spec.nodes[i].y
                spec.nodes[i].x = x * ca - y * sa
                spec.nodes[i].y = x * sa + y * ca
            }
            if spec.template != .free { spec.template = .free }
        }
        let rad = a * Double.pi / 180
        for i in spec.feats.indices {
            let x = spec.feats[i].x, y = spec.feats[i].y
            spec.feats[i].x = x * cos(rad) - y * sin(rad)
            spec.feats[i].y = x * sin(rad) + y * cos(rad)
        }
        for i in spec.innerLoops.indices {
            let x = spec.innerLoops[i].cx, y = spec.innerLoops[i].cy
            spec.innerLoops[i].cx = x * cos(rad) - y * sin(rad)
            spec.innerLoops[i].cy = x * sin(rad) + y * cos(rad)
            if spec.innerLoops[i].template == .rect && abs(a.truncatingRemainder(dividingBy: 90)) < 0.01
                && Int(round(a / 90)) % 2 != 0 {
                var l = spec.innerLoops[i]
                let t = l.rectL
                l.rectL = l.rectW
                l.rectW = t
                spec.innerLoops[i] = l
            }
        }
        for i in spec.steps.indices {
            let sp = PartProg.pts(spec.steps[i], spec)
            var m = spec.steps[i]
            m.shape.template = .free
            m.shape.nodes = sp.map { q in
                let x = Double(q.x), y = Double(q.y)
                return ContourNode(x: x * cos(rad) - y * sin(rad),
                                   y: x * sin(rad) + y * cos(rad))
            }
            m.shape.cx = 0
            m.shape.cy = 0
            spec.steps[i] = m
        }
    }

    private func scalePart(_ s: Double) {
        guard s > 0.01 else { return }
        onUndo()
        spec.rectL *= s; spec.rectW *= s; spec.rectR *= s
        spec.circleD *= s; spec.slotL *= s; spec.slotW *= s
        for i in spec.nodes.indices {
            spec.nodes[i].x *= s; spec.nodes[i].y *= s; spec.nodes[i].r *= s
        }
        for i in spec.feats.indices {
            spec.feats[i].x *= s; spec.feats[i].y *= s
            spec.feats[i].dia *= s; spec.feats[i].depth *= s
            spec.feats[i].w *= s; spec.feats[i].h *= s
        }
        for i in spec.innerLoops.indices {
            spec.innerLoops[i].cx *= s; spec.innerLoops[i].cy *= s
            spec.innerLoops[i].rectL *= s; spec.innerLoops[i].rectW *= s
            spec.innerLoops[i].rectR *= s; spec.innerLoops[i].circleD *= s
            spec.innerLoops[i].slotL *= s; spec.innerLoops[i].slotW *= s
            spec.innerLoops[i].depth *= s
            for j in spec.innerLoops[i].nodes.indices {
                spec.innerLoops[i].nodes[j].x *= s
                spec.innerLoops[i].nodes[j].y *= s
                spec.innerLoops[i].nodes[j].r *= s
            }
        }
        for i in spec.steps.indices {
            spec.steps[i].z0 *= s
            spec.steps[i].height *= s
            spec.steps[i].shape.cx *= s
            spec.steps[i].shape.cy *= s
            spec.steps[i].shape.rectL *= s
            spec.steps[i].shape.rectW *= s
            spec.steps[i].shape.rectR *= s
            spec.steps[i].shape.circleD *= s
            spec.steps[i].shape.slotL *= s
            spec.steps[i].shape.slotW *= s
            for j in spec.steps[i].shape.nodes.indices {
                spec.steps[i].shape.nodes[j].x *= s
                spec.steps[i].shape.nodes[j].y *= s
                spec.steps[i].shape.nodes[j].r *= s
            }
        }
        spec.height *= s; spec.topStock *= s
    }

    private func toFreeNodes() {
        var d = DrawSpec()
        d.template = spec.template
        d.rectL = spec.rectL; d.rectW = spec.rectW; d.rectR = spec.rectR
        d.circleD = spec.circleD; d.slotL = spec.slotL; d.slotW = spec.slotW
        spec.nodes = ContourGeo.buildNodes(d)
        spec.template = .free
    }
}


// MARK: - 单工序参数（安卓式逐行参数弹框）

private struct OpParamsSheet: View {
    @Binding var spec: PartSpec
    let op: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                switch op {
                case "平面铣":
                    dRow("刀径 Ø (mm)", $spec.faceDia)
                    dRow("顶面余量 (mm)", $spec.topStock)
                    dRow("每层 AP (mm)", $spec.stepDown)
                    iRow("转速 S", $spec.spindle)
                    iRow("进给 F", $spec.feed)
                case "轮廓铣":
                    dRow("刀径 Ø (mm)", $spec.contourDia)
                    dRow("总深 (mm)", $spec.height)
                    dRow("每层 AP (mm)", $spec.stepDown)
                    iRow("T 刀号", $spec.contourTool)
                case "螺旋铣":
                    dRow("刀径 Ø (mm)", $spec.holeDia)
                    dRow("每层 AP (mm)", $spec.stepDown)
                    iRow("转速 S", $spec.spindle)
                    iRow("进给 F", $spec.feed)
                case "型腔铣":
                    dRow("刀径 Ø (mm)", $spec.pocketDia)
                    dRow("每层 AP (mm)", $spec.stepDown)
                case "钻孔":
                    dRow("G83 啄钻 Q (mm)", $spec.peck)
                    iRow("转速 S", $spec.spindle)
                    iRow("进给 F", $spec.feed)
                    iRow("T 刀号", $spec.holeTool)
                case "攻丝":
                    dRow("螺距 P (mm)", $spec.tapPitch)
                    iRow("转速 S", $spec.tapRpm)
                    dRow("丝锥 Ø (mm)", $spec.tapDia)
                    iRow("T 刀号", $spec.tapTool)
                default:
                    Text("没有这个工序")
                }
                Section {
                    Text("改完返回，程序按新参数重新生成；孔/型腔尺寸仍在建模页改。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(op + " 参数")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() }.bold() }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func dRow(_ t: String, _ v: Binding<Double>) -> some View {
        HStack {
            Text(t)
            Spacer()
            TextField("0", value: v, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
        }
    }

    private func iRow(_ t: String, _ v: Binding<Int>) -> some View {
        HStack {
            Text(t)
            Spacer()
            TextField("0", value: v, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
        }
    }
}

// MARK: - UG 式特征命令面板

private struct FeatCommandSheet: View {
    @Binding var feat: PartFeat
    let hostZ: Double
    let isNew: Bool
    let onApply: () -> Void
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private var shortName: String {
        switch feat.kind {
        case .hole: return "孔"
        case .pocket: return "圆型腔"
        case .rectPocket: return "方型腔"
        }
    }

    private var effectiveHost: Double {
        feat.placeZ ?? hostZ
    }

    private var valid: Bool {
        switch feat.kind {
        case .hole:
            switch feat.resolvedHoleKind {
            case .blind, .thread: return feat.dia > 0 && feat.resolvedHoleDepth > 0
            case .counterbore: return feat.dia > 0 && feat.resolvedCbDia > feat.dia && feat.resolvedCbDepth > 0
            case .countersink: return feat.dia > 0 && feat.resolvedCsDia > feat.dia
            case .through: return feat.dia > 0
            }
        case .pocket: return feat.dia > 0 && feat.depth > 0
        case .rectPocket: return feat.w > 0 && feat.h > 0 && feat.depth > 0
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("类型") {
                    Picker("类型", selection: $feat.kind) {
                        ForEach(PartFeatKind.allCases) { k in Text(k.rawValue).tag(k) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("位置") {
                    dRow("X", $feat.x)
                    dRow("Y", $feat.y)
                    Toggle("手动指定放置 Z", isOn: Binding(
                        get: { feat.placeZ != nil },
                        set: { on in
                            feat.placeZ = on ? (feat.placeZ ?? hostZ) : nil
                        }
                    ))
                    if feat.placeZ != nil {
                        dRow("放置 Z", Binding(
                            get: { feat.placeZ ?? hostZ },
                            set: { feat.placeZ = $0 }
                        ))
                    }
                    Text("当前起始面 Z \(ncf(effectiveHost))；关掉手动放置时自动取所在台阶顶面或 Z0")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("尺寸") {
                    switch feat.kind {
                    case .hole:
                        dRow("Ø 孔径", $feat.dia)
                        Picker("孔型", selection: Binding(
                            get: { feat.resolvedHoleKind },
                            set: { feat.holeKind = $0 }
                        )) {
                            ForEach(PartHoleKind.allCases) { k in
                                Text(k.rawValue).tag(k)
                            }
                        }
                        switch feat.resolvedHoleKind {
                        case .through:
                            Text("贯通孔：深度按所在台阶顶面到底面自动计算")
                                .font(.footnote).foregroundStyle(.secondary)
                        case .blind, .thread:
                            dRow("孔深", Binding(
                                get: { feat.resolvedHoleDepth },
                                set: { feat.holeDepth = $0 }
                            ))
                        case .counterbore:
                            dRow("沉头 Ø", Binding(
                                get: { feat.resolvedCbDia },
                                set: { feat.cbDia = $0 }
                            ))
                            dRow("沉头深", Binding(
                                get: { feat.resolvedCbDepth },
                                set: { feat.cbDepth = $0 }
                            ))
                            Text("2.5D 按“顶部大径圆柱 + 下方小孔”近似，不做真 3D 沉头。")
                                .font(.footnote).foregroundStyle(.secondary)
                        case .countersink:
                            dRow("沉孔 Ø", Binding(
                                get: { feat.resolvedCsDia },
                                set: { feat.csDia = $0 }
                            ))
                            dRow("锥角 °", Binding(
                                get: { feat.resolvedCsAngle },
                                set: { feat.csAngle = $0 }
                            ))
                            Text("2.5D 按锥面倒角近似，深度由 Ø 和锥角换算。")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    case .pocket:
                        dRow("Ø 型腔直径", $feat.dia)
                        dRow("深度", $feat.depth)
                    case .rectPocket:
                        dRow("长 L", $feat.w)
                        dRow("宽 W", $feat.h)
                        dRow("深度", $feat.depth)
                    }
                }

                Section("预览") {
                    Text(previewText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.blue)
                    Text("蓝青色虚线是草稿预览；应用/确定后才会写入特征树并重建下游工序。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(isNew ? "新建\(shortName)" : "编辑\(shortName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    Button("应用") { onApply() }
                        .disabled(!valid)
                    Button("确定") { onConfirm() }
                        .bold()
                        .disabled(!valid)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var previewText: String {
        switch feat.kind {
        case .hole:
            return "Ø\(ncf(feat.dia)) \(feat.holeSummary) @ X\(ncf(feat.x)) Y\(ncf(feat.y))"
        case .pocket:
            return "Ø\(ncf(feat.dia)) 深\(ncf(feat.depth)) @ X\(ncf(feat.x)) Y\(ncf(feat.y))"
        case .rectPocket:
            return "\(ncf(feat.w))×\(ncf(feat.h)) 深\(ncf(feat.depth)) @ X\(ncf(feat.x)) Y\(ncf(feat.y))"
        }
    }

    private func dRow(_ title: String, _ value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
        }
    }
}
