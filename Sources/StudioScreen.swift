import SwiftUI
import UIKit
import PhotosUI

/// 建模编程（iOS 对齐安卓四步）：草图 → 建模 → 出图 → 加工
struct StudioScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var spec = PartSpec()
    @State private var step = 0
    @State private var code = ""
    @State private var showResult = false

    // 3D 视角
    @State private var yaw = 0.78
    @State private var pitch = 0.62
    @State private var zoom = 1.0
    @State private var zoomBase = 1.0
    @State private var lastDrag: CGSize = .zero

    // 3D 指针
    @State private var ptrX = 0.0
    @State private var ptrY = 0.0
    @State private var hasPtr = false
    @State private var tapOnModel = false

    @State private var showRotate = false
    @State private var showScale = false
    @State private var showOpSheet = false
    @State private var opSheetName = ""
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
    @State private var showModelTools = false
    @State private var drawInner = false
    @State private var innerDraft: [ContourNode] = []
    @State private var undoStack: [PartSpec] = []
    @State private var redoStack: [PartSpec] = []

    // Digit 式界面状态
    @State private var modelPanel: StudioModelPanel = .none
    @State private var bodyVisible = true
    @State private var selectedTreeID: String? = nil
    @State private var hiddenTreeIDs: Set<String> = []
    @State private var selectedNode: Int? = nil
    @State private var continuousDraw = true
    @State private var gridAuto = true
    @State private var sketchFixed = false
    @State private var sectionOn = false
    @State private var sectionAxis: SectionAxis = .z
    @State private var sectionT = 0.45
    @State private var sectionReverse = false
    @State private var sectionHandles = true
    @State private var sectionLines = true
    @State private var measureOn = false
    @State private var measureTarget: MeasureTarget = .body
    @State private var material: StudioMaterial = .abs
    @State private var toastText: String = ""
    @State private var showToast = false
    @State private var arrayCount = 6
    @State private var arrayRadius = 36.0

    // 拍照图纸
    @State private var showPhotoMenu = false
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
        case nodeLen(Int), nodeAngle(Int), nodeR(Int)
    }

    private enum StudioModelPanel: Equatable {
        case none, tree, body, extrude, section, measure, display, tools
    }

    private enum SketchSidePanel: Hashable {
        case none, tools, params, dim, angle
    }

    private enum SectionAxis: String, CaseIterable, Identifiable {
        case x = "X", y = "Y", z = "Z"
        var id: String { rawValue }
    }

    private enum MeasureTarget: String, CaseIterable, Identifiable {
        case point = "点", edge = "边", face = "面", body = "体", compound = "复合"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .point: return "smallcircle.filled.circle"
            case .edge: return "line.diagonal"
            case .face: return "square.on.square"
            case .body: return "cube"
            case .compound: return "circle.grid.2x2"
            }
        }
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
    }

    init() {
        var s = PartSpec()
        // 打开草图先是一张空白网格，不预放圆/矩形
        s.template = .free
        s.nodes = []
        s.innerLoops = []
        s.feats = []
        _spec = State(initialValue: s)
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
        .sheet(isPresented: $showRotate) {
            TransformSheet(spec: $spec, rotate: true)
        }
        .sheet(isPresented: $showScale) {
            TransformSheet(spec: $spec, rotate: false)
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
                Text("示例 · 参数化 2.5D")
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
    private var bodyTint: Color { Color(red: 0.08, green: 0.56, blue: 0.46) }


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
                    if isDrawTool(sketchTool) || drawInner {
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
                sketchConstraintRail
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            VStack {
                Spacer()
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
                railButton("矩形", "rectangle", active: spec.template == .rect && !drawInner) { selectSketchTool("矩形") }
                railButton("圆", "circle", active: spec.template == .circle && !drawInner) { selectSketchTool("圆") }
                railButton("圆弧", "arrow.turn.up.left", active: sketchTool == "圆弧") { selectSketchTool("圆弧") }
                railButton("样条", "scribble", active: false) { selectSketchTool("样条曲线") }
                railButton("多边形", "hexagon", active: false) { selectSketchTool("多边形") }
                railButton("椭圆", "oval", active: false) { selectSketchTool("椭圆") }

                Divider().padding(.vertical, 2)
                railButton("线阵", "square.grid.3x1.folder.badge.plus", active: false) { arrayInner() }
                railButton("圆阵", "circle.grid.cross", active: false) { circularArrayInner() }
                railButton("镜像", "arrow.left.and.right", active: false) { pushUndo(); mirrorOuter() }

                Divider().padding(.vertical, 2)
                railButton("修剪", "scissors", active: false) { pushUndo(); trimLast() }
                railButton("延伸", "arrow.up.right", active: false) { pushUndo(); extendLast(10) }
                railButton("圆角", "square.bottomleft", active: false) { pushUndo(); filletOuter(filletR) }
                railButton("倒角", "square.topright", active: false) { pushUndo(); chamferOuter(chamferC) }

                railButton("更多", "square.grid.2x2", active: sketchSidePanel == .tools) {
                    sketchSidePanel = sketchSidePanel == .tools ? .none : .tools
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

    private var sketchConstraintRail: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 3) {
                railButton("尺寸", "ruler", active: sketchSidePanel == .dim) {
                    sketchSidePanel = sketchSidePanel == .dim ? .none : .dim
                }
                railButton("角度", "angle", active: sketchSidePanel == .angle) {
                    sketchSidePanel = sketchSidePanel == .angle ? .none : .angle
                }
                railButton("水平", "line.3.horizontal", active: false) { pushUndo(); constrain(horizontal: true) }
                railButton("竖直", "line.3.horizontal.decrease", active: false) { pushUndo(); constrain(horizontal: false) }
                railButton("固定", "pin", active: sketchFixed) { sketchFixed.toggle() }
                railButton("重合", "circle.circle", active: false) { pushUndo(); snapLastToFirst() }
                railButton("中点", "smallcircle.filled.circle", active: false) { pushUndo(); centerSketch() }
                railButton("平行", "equal", active: false) { pushUndo(); makeParallel() }
                railButton("垂直", "plus", active: false) { pushUndo(); makePerpendicular() }
                railButton("相切", "circle.dashed", active: false) { showToastView("相切：圆/圆弧工具已按三点定圆处理") }
                railButton("同心", "circle.and.line.horizontal", active: false) { pushUndo(); makeConcentric() }
                railButton("等长", "equal.circle", active: false) { pushUndo(); equalizeSegments() }
                railButton("清除", "xmark.circle", active: false) {
                    sketchFixed = false
                    showToastView("已清除固定状态")
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

            Text(isDrawTool(sketchTool) || drawInner ? "连续落点 · 点画布添加" : "点线选点 · 双击改尺寸")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Button { step = 1 } label: {
                Label("完成", systemImage: "checkmark")
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
                    sketchToolGridPanel
                case .params:
                    Form { sketchControls }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .background(Color.white)
                case .dim:
                    sketchDimPanel
                case .angle:
                    sketchAnglePanel
                case .none:
                    EmptyView()
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
                        pushUndo()
                        drawInner.toggle()
                        innerDraft.removeAll()
                        sketchTool = drawInner ? "多段线" : ""
                        sketchSidePanel = .none
                    } label: {
                        Label(drawInner ? "结束手画" : "手画", systemImage: "pencil.tip")
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
                    Text("手绘轮廓：外形尺寸按下面每段长度控制。")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }

                if spec.nodes.count > 1 {
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
                    EmptyView()
                }

                if spec.nodes.count > 2 {
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

    @ViewBuilder
    private var sketchControls: some View {
        Section("绘制") {
            ForEach(drawToolNames, id: \.self) { name in
                toolRow(name, active: sketchTool == name) { selectSketchTool(name) }
                Divider()
            }
        }

        Section("编辑") {
            ForEach(editToolNames, id: \.self) { name in
                toolRow(name, active: false) { selectSketchTool(name) }
                Divider()
            }
            Text("修剪/延伸/打断按当前轮廓的末段处理；圆角/倒角/偏置对整条外轮廓生效。")
                .font(.caption).foregroundStyle(.secondary)
        }

        Section("内轮廓（和外轮廓叠在同一张草图）") {
            HStack {
                Button { addInner(.circle) } label: { Label("内圆", systemImage: "circle") }
                Spacer()
                Button { addInner(.rect) } label: { Label("内方", systemImage: "rectangle") }
                Spacer()
                Button {
                    pushUndo()
                    drawInner.toggle()
                    innerDraft.removeAll()
                    sketchTool = drawInner ? "多段线" : ""
                } label: {
                    Label(drawInner ? "正在画内轮廓" : "手画内轮廓", systemImage: "pencil.tip")
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
                numRow("圆角 R (mm)", $filletR)
                numRow("倒角 C (mm)", $chamferC)
                HStack(spacing: 6) {
                    miniNum("X0", $trimX0)
                    miniNum("Y0", $trimY0)
                    miniNum("X1", $trimX1)
                    miniNum("Y1", $trimY1)
                }
                Button("按这个方框围栏修剪") { regionTrim() }
                    .font(.system(size: 13, weight: .semibold))
                HStack(spacing: 6) {
                    miniNum("dx", $moveDX)
                    miniNum("dy", $moveDY)
                    Button("移动轮廓") { moveOuter() }
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
                Button("阵列内轮廓") { pushUndo(); arrayInner() }
                    .font(.system(size: 13, weight: .semibold))
                HStack(spacing: 6) {
                    Stepper("圆阵 \(arrayCount) 个", value: $arrayCount, in: 2...12)
                    miniNum("R", $arrayRadius)
                }
                Button("圆形阵列内轮廓") { circularArrayInner() }
                    .font(.system(size: 13, weight: .semibold))
            }
        }

        Section("内轮廓（和外形叠在同一张草图）") {
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
    @State private var refPoints: [CGPoint] = []
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
         "阵列", "几何约束", "移动", "旋转", "缩放", "延伸", "打断"]
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
        default:
            break
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
        case "阵列":
            arrayInner()
        case "几何约束":
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
    }

    private func selectSketchNode(at loc: CGPoint, size: CGSize) {
        guard spec.template == .free, !spec.nodes.isEmpty else {
            showToastView("当前是模板轮廓，点“更多”可转成自由轮廓")
            return
        }
        let b = sketchBBox()
        let k = sketchScale(b: b, size: size)
        var best = 30.0
        var bestIndex: Int? = nil
        for (i, n) in spec.nodes.enumerated() {
            let sx = size.width / 2 + (n.x - b.midX) * k
            let sy = size.height / 2 - (n.y - b.midY) * k
            let d = hypot(Double(loc.x) - sx, Double(loc.y) - sy)
            if d < best { best = d; bestIndex = i }
        }
        if let i = bestIndex {
            selectedNode = i
            showToastView("已选中点 \(i + 1)")
        } else {
            selectedNode = nil
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
        for f in spec.feats where !hiddenTreeIDs.contains("feat-\(f.id.uuidString)") {
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

        // 自由轮廓节点
        if spec.template == .free {
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
    }

    private func sketchDrawSpec() -> DrawSpec {
        var d = DrawSpec()
        d.template = spec.template
        d.rectL = spec.rectL
        d.rectW = spec.rectW
        d.rectR = spec.rectR
        d.circleD = spec.circleD
        d.slotL = spec.slotL
        d.slotW = spec.slotW
        d.nodes = spec.nodes
        return d
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
        spec.nodes = []
        spec.template = .free
        refPoints.removeAll()
    }

    private func makePolyline() {
        sketchTool = "多段线"
        spec.nodes = []
        spec.template = .free
        refPoints.removeAll()
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
        if snapVertex, let near = spec.nodes.min(by: {
            hypot($0.x - px, $0.y - py) < hypot($1.x - px, $1.y - py)
        }), hypot(near.x - px, near.y - py) < 8 {
            px = near.x; py = near.y
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
        if spec.nodes.isEmpty {
            pushUndo()
            spec.nodes.append(ContourNode(x: px, y: py))
        } else if let last = spec.nodes.last, hypot(px - last.x, py - last.y) > 0.2 {
            pushUndo()
            spec.nodes.append(ContourNode(x: px, y: py))
        }
        selectedNode = spec.nodes.isEmpty ? nil : spec.nodes.count - 1
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

    private func arrayInner() {
        let base = spec.innerLoops
        guard !base.isEmpty else { return }
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
        spec.nodes = pts.map { ContourNode(x: Double($0.x), y: Double($0.y)) }
        spec.template = .free
    }

    private func trimLast() {
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
                            if tapOnModel {
                                if dragFeatID == nil {
                                    let cam = modelCam(size: geo.size)
                                    var best = 40.0
                                    for f in spec.feats {
                                        let q = cam.p(f.x, f.y, 0)
                                        let d = hypot(Double(g.startLocation.x) - Double(q.x),
                                                      Double(g.startLocation.y) - Double(q.y))
                                        if d < best { best = d; dragFeatID = f.id }
                                    }
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

            viewCube
                .padding(.trailing, 74)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .trailing)

            VStack {
                Spacer()
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
        }
    }

    private var modelLeftRail: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 3) {
                railButton("草图", "pencil", active: false) { step = 0 }
                railButton("拉伸", "arrow.up.right.square", active: modelPanel == .extrude) {
                    modelPanel = modelPanel == .extrude ? .none : .extrude
                }
                railButton("孔", "circle.circle", active: false) {
                    pushUndo(); let f = addFeat(.hole)
                    selectedTreeID = "feat-\(f.id.uuidString)"
                    modelPanel = .none
                    showToastView("孔已加到 X\(ncf(f.x)) Y\(ncf(f.y))")
                }
                railButton("圆腔", "circle.dashed", active: false) {
                    pushUndo(); let f = addFeat(.pocket)
                    selectedTreeID = "feat-\(f.id.uuidString)"
                    modelPanel = .none
                    showToastView("圆腔已加到 X\(ncf(f.x)) Y\(ncf(f.y))")
                }
                railButton("方腔", "rectangle.dashed", active: false) {
                    pushUndo(); let f = addFeat(.rectPocket)
                    selectedTreeID = "feat-\(f.id.uuidString)"
                    modelPanel = .none
                    showToastView("方腔已加到 X\(ncf(f.x)) Y\(ncf(f.y))")
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
                railButton("测量", "ruler", active: modelPanel == .measure) {
                    modelPanel = modelPanel == .measure ? .none : .measure
                    if modelPanel == .measure { measureOn = true }
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
                    .frame(width: 38, height: 20)
                    .background(Color.white.opacity(0.85))
            }
            .buttonStyle(.plain)
            HStack(spacing: 2) {
                Button { applyView("正视", 0, 0) } label: {
                    Text("前").font(.system(size: 9, weight: .bold))
                        .frame(width: 18, height: 28)
                        .background(Color.white.opacity(0.85))
                }
                .buttonStyle(.plain)
                Button { applyView("右视", 1.5708, 0) } label: {
                    Text("右").font(.system(size: 9, weight: .bold))
                        .frame(width: 18, height: 28)
                        .background(Color(red: 0.78, green: 0.80, blue: 0.84))
                }
                .buttonStyle(.plain)
            }
            Text("视图").font(.system(size: 8)).foregroundStyle(.white)
                .frame(width: 38, height: 15)
                .background(studioBlue.opacity(0.85))
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.9), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
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
            Text("单指 360° · 双指缩放 · 点选顶面")
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
            case .section:
                sectionPanel
            case .measure:
                measurePanel
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
        case .section: return "X/Y/Z · 实时预览"
        case .measure: return "体积/重量/尺寸/面积"
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
                detail: f.kind == .hole ? "Ø\(ncf(f.dia)) 通孔" : "\(ncf(f.w))×\(ncf(f.h)) 深\(ncf(f.depth))",
                canMove: true, canDelete: true))
        }
        out.append(StudioTreeItem(
            id: "extrude", index: out.count + 1, title: "拉伸",
            icon: "arrow.up.right.square",
            detail: "H \(ncf(spec.height)) mm",
            canMove: false, canDelete: false))
        return out
    }

    private var modelTreePanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(treeItems.count) 项")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 13)
            .padding(.bottom, 4)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(treeItems) { item in
                        HStack(spacing: 6) {
                            Image(systemName: item.icon)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(item.id == selectedTreeID ? studioBlue : .secondary)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(item.index) · \(item.title)")
                                    .font(.system(size: 12, weight: item.id == selectedTreeID ? .bold : .medium))
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
                        .onTapGesture { selectedTreeID = item.id }
                        Divider().padding(.leading, 34)
                    }
                }
            }
        }
        .frame(maxHeight: 500)
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
        }
    }

    private func editTreeItem(_ item: StudioTreeItem) {
        selectedTreeID = item.id
        if item.id == "sketch" {
            step = 0
        } else if item.id == "extrude" {
            modelPanel = .extrude
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

                metricCard("外形尺寸", "\(ncf(Double(partBBox.width))) × \(ncf(Double(partBBox.height))) × \(ncf(spec.height)) mm")
                metricCard("体积", "\(ncf(partVolume)) mm³")
                metricCard("重量", "\(ncf(partWeight)) g（\(material.rawValue)）")
                metricCard("材料", material.rawValue)
                metricCard("特征", "\(spec.innerLoops.count) 内轮廓 · \(spec.feats.count) 孔/型腔")

                Picker("材料", selection: $material) {
                    ForEach(StudioMaterial.allCases) { m in Text(m.rawValue).tag(m) }
                }
                .pickerStyle(.menu)

                HStack {
                    Button("高亮实体") { modelPanel = .none; showToastView("实体已在画布中高亮") }
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
                     ? "Z 向是真实等高剖切：只显示剖切面以上的实体，橙色面为截面。"
                     : "X/Y 向显示剖切平面和截面试算；当前内核为 2.5D，复杂曲面截面暂不计算。")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 13)
            .padding(.bottom, 14)
        }
    }

    private var measurePanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("测量目标").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text(measureTarget.rawValue).font(.system(size: 11, weight: .bold)).foregroundStyle(studioBlue)
                }
                HStack(spacing: 5) {
                    ForEach(MeasureTarget.allCases) { t in
                        Button { measureTarget = t } label: {
                            VStack(spacing: 2) {
                                Image(systemName: t.icon).font(.system(size: 12))
                                Text(t.rawValue).font(.system(size: 9, weight: .medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 8)
                                .fill(measureTarget == t ? studioBlue.opacity(0.14) : Color(.secondarySystemBackground)))
                            .foregroundStyle(measureTarget == t ? studioBlue : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    Text("材料").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Picker("", selection: $material) {
                        ForEach(StudioMaterial.allCases) { m in Text(m.rawValue).tag(m) }
                    }
                    .labelsHidden()
                    .frame(width: 105)
                }
                Toggle("显示测量框", isOn: $measureOn).tint(studioBlue)
                metricCard("体积", "\(ncf(partVolume)) mm³")
                metricCard("重量", "\(ncf(partWeight)) g（\(material.rawValue)）")
                metricCard("价格", "¥\(ncf(partPrice))")
                metricCard("包容体积", "\(ncf(partBBoxVolume)) mm³")
                metricCard("尺寸", "\(ncf(Double(partBBox.width))) × \(ncf(Double(partBBox.height))) × \(ncf(spec.height)) mm")
                metricCard("投影面积", "\(ncf(partProjectedArea)) mm²")
                Text("体积按外形面积×厚度，再减去孔/型腔/内轮廓；重量按材料密度换算，价格为参考估价。")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 13)
            .padding(.bottom, 14)
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
                            modelPanel = .none
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
                        modelPanel = .none
                        showToastView(v ? "参考网格已打开" : "参考网格已关闭")
                    }))
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
                Text("网格吸附、节点吸附在草图页“参数”里设置，只影响草图落点。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Divider()
                Text("单指自由旋转（俯仰不锁 ±90°），双指缩放；切换视角后面板自动收起。")
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

    private var partBBox: CGRect { PartProg.bbox(spec) }

    private var outerSurfaceArea: Double {
        abs(ContourGeo.signedArea(PartProg.pts(spec)))
    }

    private var cutVolume: Double {
        var cut = 0.0
        for l in spec.innerLoops {
            let a = abs(ContourGeo.signedArea(PartProg.loopPoints(l)))
            cut += a * (l.through ? spec.height : min(max(l.depth, 0), spec.height))
        }
        for f in spec.feats {
            if f.kind == .hole {
                cut += Double.pi * (f.dia / 2) * (f.dia / 2) * spec.height
            } else if f.kind == .rectPocket {
                cut += f.w * f.h * min(max(f.depth, 0), spec.height)
            } else {
                cut += Double.pi * (f.dia / 2) * (f.dia / 2) * min(max(f.depth, 0), spec.height)
            }
        }
        return cut
    }

    private var partVolume: Double {
        max(0, outerSurfaceArea * spec.height - cutVolume)
    }

    private var partWeight: Double { partVolume * material.density / 1000 }

    private var partPrice: Double { partWeight / 1000 * material.pricePerKg }

    private var partBBoxVolume: Double {
        Double(partBBox.width) * Double(partBBox.height) * spec.height
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
                    viewChip("等轴") { setView(0.78, 0.62) }
                    viewChip("俯视") { setView(0, 1.5) }
                    viewChip("正视") { setView(0, 0) }
                    viewChip("右视") { setView(1.5708, 0) }
                    viewChip("仰视") { setView(0, -1.5) }
                    viewChip("适合窗口") { setView(0.78, 0.62) }
                }
                .padding(.vertical, 2)
            }
            Text("画布已独立，手指左右拖可一直转（360°不限），上下翻到仰视；双指缩放，不再带着页面上下跑。")
                .font(.caption).foregroundStyle(.secondary)
        }

        Section("指针 / 加特征") {
            Toggle("点图上顶面取 XY", isOn: $tapOnModel)
            HStack {
                miniNum("X", $ptrX)
                miniNum("Y", $ptrY)
                Button("用这个点加孔") { addFeat(.hole) }
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
                            spec.feats.removeAll { $0.id == f.id }
                        } label: {
                            Image(systemName: "trash").foregroundStyle(.red)
                        }
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
                    Text(f.kind == .hole ? "Ø\(ncf(f.dia)) 通孔"
                         : (f.kind == .rectPocket ? "\(ncf(f.w))×\(ncf(f.h)) 深\(ncf(f.depth))"
                            : "Ø\(ncf(f.dia)) 深\(ncf(f.depth))"))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            HStack {
                Button { addFeat(.hole) } label: { Label("加孔", systemImage: "circle.circle") }
                Spacer()
                Button { addFeat(.pocket) } label: { Label("加圆腔", systemImage: "circle.dashed") }
                Spacer()
                Button { addFeat(.rectPocket) } label: { Label("加方腔", systemImage: "rectangle.dashed") }
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

    @discardableResult
    private func addFeat(_ kind: PartFeatKind) -> PartFeat {
        let b = PartProg.bbox(spec)
        var f = PartFeat(kind: kind)
        f.x = hasPtr ? ptrX : Double(b.midX)
        f.y = hasPtr ? ptrY : Double(b.midY)
        f.dia = kind == .hole ? 10 : 30
        f.depth = min(5, max(1, spec.height / 2))
        spec.feats.append(f)
        return f
    }

    private func modelCam(size: CGSize) -> Cam {
        Cam(spec: spec, yaw: yaw, pitch: pitch, zoom: zoom, size: size)
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
        let visibleDepth = showZCut
            ? max(0.2, depth * (sectionReverse ? (1 - sectionT) : sectionT))
            : depth

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

        func selectedMarker(_ f: PartFeat, radius: Double) {
            let r = max(radius, 1)
            ctx.stroke(circle(f.x, f.y, 0, r), with: .color(studioBlue), lineWidth: 2)
            let q = cam.p(f.x, f.y, 0)
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: q.x - 7, y: q.y)); p.addLine(to: CGPoint(x: q.x + 7, y: q.y))
                p.move(to: CGPoint(x: q.x, y: q.y - 7)); p.addLine(to: CGPoint(x: q.x, y: q.y + 7))
            }, with: .color(studioBlue), lineWidth: 1.2)
        }

        // 建模页参考网格：让“显示”里的网格步距有真实反馈
        if showModelGrid, gridStep > 0.01 {
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

        let bottom = ringPath(-visibleDepth)
        ctx.fill(bottom, with: .color(bodyTint.opacity(0.14)))
        ctx.stroke(bottom, with: .color(bodyTint.opacity(0.55)), lineWidth: 1)

        for i in pts.indices {
            let a = pts[i], b = pts[(i + 1) % pts.count]
            var side = Path()
            side.move(to: cam.p(a.x, a.y, 0))
            side.addLine(to: cam.p(b.x, b.y, 0))
            side.addLine(to: cam.p(b.x, b.y, -visibleDepth))
            side.addLine(to: cam.p(a.x, a.y, -visibleDepth))
            side.closeSubpath()
            ctx.fill(side, with: .color(bodyTint.opacity(0.16)))
        }

        let layers = max(1, Int(ceil(visibleDepth / max(spec.stepDown, 0.1))))
        if layers > 1 {
            for i in 1..<layers {
                let z = -min(visibleDepth, Double(i) * spec.stepDown)
                ctx.stroke(ringPath(z), with: .color(bodyTint.opacity(0.22)), lineWidth: 0.7)
            }
        }
        for i in Swift.stride(from: 0, to: pts.count, by: max(1, pts.count / 30)) {
            let q = pts[i]
            ctx.stroke(Path { p in
                p.move(to: cam.p(q.x, q.y, 0))
                p.addLine(to: cam.p(q.x, q.y, -visibleDepth))
            }, with: .color(bodyTint.opacity(0.35)), lineWidth: 0.8)
        }

        ctx.fill(ringPath(0), with: .color(bodyTint.opacity(0.30)))
        ctx.stroke(ringPath(0), with: .color(bodyTint), lineWidth: 2)

        if showZCut {
            ctx.fill(ringPath(-visibleDepth), with: .color(Color.orange.opacity(0.42)))
            ctx.stroke(ringPath(-visibleDepth), with: .color(.orange), lineWidth: 2)
        }

        for l in spec.innerLoops where !hiddenTreeIDs.contains("inner-\(l.id.uuidString)") {
            let d = PartProg.drawForLoop(l, spec, depth: l.through ? spec.height + 1 : l.depth,
                                         dia: max(spec.pocketDia, 1), hNo: spec.pocketTool)
            let segs = ContourGeo.segments(ContourGeo.buildNodes(d))
            let flat = ContourGeo.flatten(segs, arcStep: 24)
            let cut = l.through ? spec.height : min(l.depth, spec.height)
            let loopCut = min(cut, visibleDepth)
            func loopPath(_ z: Double) -> Path {
                var p = Path()
                guard let f = flat.first else { return p }
                p.move(to: cam.p(f.x + l.cx, f.y + l.cy, z))
                for q in flat.dropFirst() { p.addLine(to: cam.p(q.x + l.cx, q.y + l.cy, z)) }
                return p
            }
            let topLoop = loopPath(0)
            ctx.fill(topLoop, with: .color(Color.red.opacity(0.12)))
            ctx.stroke(topLoop, with: .color(.red),
                       style: StrokeStyle(lineWidth: 1.4, dash: [4, 3]))
            ctx.stroke(loopPath(-loopCut), with: .color(Color.red.opacity(0.55)), lineWidth: 0.9)
            let c = cam.p(l.cx, l.cy, 0)
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

        for f in spec.feats where !hiddenTreeIDs.contains("feat-\(f.id.uuidString)") {
            let isSelected = selectedTreeID == "feat-\(f.id.uuidString)"
            if f.kind == .rectPocket {
                let d = min(f.depth, spec.height)
                var top = Path()
                let x0 = f.x - f.w / 2, x1 = f.x + f.w / 2
                let y0 = f.y - f.h / 2, y1 = f.y + f.h / 2
                top.move(to: cam.p(x0, y0, 0))
                top.addLine(to: cam.p(x1, y0, 0))
                top.addLine(to: cam.p(x1, y1, 0))
                top.addLine(to: cam.p(x0, y1, 0))
                top.closeSubpath()
                ctx.fill(top, with: .color(Color(red: 1.0, green: 0.42, blue: 0.10).opacity(0.18)))
                ctx.stroke(top, with: .color(Color(red: 0.95, green: 0.55, blue: 0.20)), lineWidth: 1.4)
                var bot = Path()
                bot.move(to: cam.p(x0, y0, -d))
                bot.addLine(to: cam.p(x1, y0, -d))
                bot.addLine(to: cam.p(x1, y1, -d))
                bot.addLine(to: cam.p(x0, y1, -d))
                bot.closeSubpath()
                ctx.stroke(bot, with: .color(Color(red: 0.95, green: 0.55, blue: 0.20).opacity(0.75)), lineWidth: 1)
                label(ctx, cam, f, "\(ncf(f.w))×\(ncf(f.h)) 深\(ncf(f.depth))")
                if isSelected { selectedMarker(f, radius: max(f.w, f.h) / 2 + 4) }
                continue
            }
            let r = f.dia / 2
            if f.kind == .hole {
                let c = circle(f.x, f.y, 0, r)
                ctx.fill(c, with: .color(Color(white: 0.28).opacity(0.55)))
                ctx.stroke(c, with: .color(Color(white: 0.35)), lineWidth: 1.4)
                ctx.stroke(circle(f.x, f.y, -min(depth, visibleDepth), r), with: .color(Color(white: 0.45)), lineWidth: 0.9)
                label(ctx, cam, f, "Ø\(ncf(f.dia))")
                if isSelected { selectedMarker(f, radius: r + 4) }
            } else {
                let d = min(f.depth, spec.height)
                let c = circle(f.x, f.y, 0, r)
                ctx.fill(c, with: .color(Color(red: 1.0, green: 0.42, blue: 0.10).opacity(0.18)))
                ctx.stroke(c, with: .color(Color(red: 0.95, green: 0.55, blue: 0.20)), lineWidth: 1.4)
                ctx.stroke(circle(f.x, f.y, -d, r), with: .color(Color(red: 0.95, green: 0.55, blue: 0.20).opacity(0.75)), lineWidth: 1)
                label(ctx, cam, f, "Ø\(ncf(f.dia)) 深\(ncf(f.depth))")
                if isSelected { selectedMarker(f, radius: r + 4) }
            }
        }

        if sectionOn {
            drawSectionPlane(&ctx, cam, size: size)
        }
        if measureOn {
            drawMeasureBox(&ctx, cam)
        }

        drawAxisTriad(&ctx, size: size)

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

    private func drawSectionPlane(_ ctx: inout GraphicsContext, _ cam: Cam, size: CGSize) {
        let b = partBBox
        let depth = max(spec.height, 0.1)
        let z = -depth * (sectionReverse ? (1 - sectionT) : sectionT)
        let x = Double(b.minX) + Double(b.width) * sectionT
        let y = Double(b.minY) + Double(b.height) * sectionT
        var corners: [(Double, Double, Double)] = []
        switch sectionAxis {
        case .z:
            corners = [(Double(b.minX), Double(b.minY), z), (Double(b.maxX), Double(b.minY), z),
                       (Double(b.maxX), Double(b.maxY), z), (Double(b.minX), Double(b.maxY), z)]
        case .x:
            corners = [(x, Double(b.minY), 0), (x, Double(b.maxY), 0),
                       (x, Double(b.maxY), -depth), (x, Double(b.minY), -depth)]
        case .y:
            corners = [(Double(b.minX), y, 0), (Double(b.maxX), y, 0),
                       (Double(b.maxX), y, -depth), (Double(b.minX), y, -depth)]
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
        let depth = max(spec.height, 0.1)
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
        ctx.stroke(boxPath(0), with: .color(.orange), lineWidth: 1.6)
        ctx.stroke(boxPath(-depth), with: .color(.orange.opacity(0.55)), lineWidth: 1)
        for q in bottom {
            ctx.stroke(Path { p in
                p.move(to: cam.p(q.0, q.1, 0))
                p.addLine(to: cam.p(q.0, q.1, -depth))
            }, with: .color(.orange.opacity(0.45)), lineWidth: 1)
        }
        let q = cam.p(Double(b.midX), Double(b.midY), 0)
        ctx.draw(Text("体积 \(ncf(partVolume)) mm³").font(.system(size: 10, weight: .semibold)).foregroundColor(.orange),
                 at: CGPoint(x: q.x, y: q.y - 26))
        ctx.draw(Text("\(ncf(Double(b.width))) × \(ncf(Double(b.height))) × \(ncf(spec.height))")
                    .font(.system(size: 9)).foregroundColor(.orange),
                 at: CGPoint(x: q.x, y: q.y - 13))
    }

    private func label(_ ctx: GraphicsContext, _ cam: Cam, _ f: PartFeat, _ text: String) {
        let q = cam.p(f.x, f.y, 0)
        ctx.draw(Text(text).font(.system(size: 9, weight: .semibold)).foregroundColor(.black),
                 at: CGPoint(x: q.x, y: q.y - 10))
    }

    // MARK: - 3 出图

    private var drawingPage: some View {
        Group {
            Section("出图 · 尺寸图") {
                GeometryReader { geo in
                    Canvas { context, size in
                        drawDrawing(context: context, size: size)
                    }
                }
                .frame(height: 390)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            Section("图纸信息") {
                let b = PartProg.bbox(spec)
                Text("外形 \(ncf(Double(b.width))) × \(ncf(Double(b.height))) × 厚 \(ncf(spec.height))")
                Text("孔 \(spec.feats.filter { $0.kind == .hole }.count) 个 · 型腔 \(spec.feats.filter { $0.kind == .pocket }.count) 个")
                    .font(.caption).foregroundStyle(.secondary)
                Text("尺寸按草图与特征自动标注，改建模参数这里会同步。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
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

        for f in spec.feats {
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
        ctx.draw(Text("厚度 \(ncf(spec.height))").font(.system(size: 10, weight: .medium)).foregroundColor(.blue),
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

    private var camPage: some View {
        Group {
            Section("工件坐标系") {
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
                    Button("自定义") { }
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
                    Button("参数") { openOp("平面铣") }.buttonStyle(.borderless)
                        .font(.system(size: 12, weight: .semibold))
                }
                HStack {
                    Toggle("轮廓铣（闭合外形）", isOn: $spec.doContour)
                    Button("参数") { openOp("轮廓铣") }.buttonStyle(.borderless)
                        .font(.system(size: 12, weight: .semibold))
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

            Section("本次程序包含") {
                let ops = PartProg.opList(spec)
                if ops.isEmpty {
                    Text("没有工序：检查上面的开关和模型").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(ops.indices, id: \.self) { i in
                        Button { openOp(for: ops[i]) } label: {
                        HStack(spacing: 8) {
                            Text("\(i + 1)")
                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                                .frame(width: 19, height: 19)
                                .background(Circle().fill(Color(red: 1.0, green: 0.42, blue: 0.10)))
                            Text(ops[i]).font(.system(size: 13))
                            Spacer()
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                        }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section("刀具（T / D）") {
                toolRow("顶面", $spec.faceTool, $spec.faceDia)
                toolRow("轮廓", $spec.contourTool, $spec.contourDia)
                if spec.holeMode == .spiral {
                    toolRow("孔", $spec.holeTool, $spec.holeDia)
                }
                if spec.doPocket {
                    toolRow("型腔", $spec.pocketTool, $spec.pocketDia)
                }
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
                    code = PartProg.build(spec)
                    showResult = true
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
}

// MARK: - 3D 相机

private struct Cam {
    let spec: PartSpec
    let yaw: Double
    let pitch: Double
    let zoom: Double
    let size: CGSize

    // 缓存投影参数：每帧只算一次，避免每个点都重算包围盒和三角函数
    private let cy: Double
    private let sy: Double
    private let sp: Double
    private let cp: Double
    private let kValue: Double
    private let midX: Double
    private let midY: Double

    init(spec: PartSpec, yaw: Double, pitch: Double, zoom: Double, size: CGSize) {
        self.spec = spec
        self.yaw = yaw
        self.pitch = pitch
        self.zoom = zoom
        self.size = size

        let b = PartProg.bbox(spec)
        let depth = max(spec.height, 0.1)
        let c = cos(yaw), s = sin(yaw)
        let sp0 = sin(pitch), cp0 = cos(pitch)
        self.cy = c
        self.sy = s
        self.sp = sp0
        self.cp = cp0

        var mnx = Double.infinity, mxx = -Double.infinity
        var mny = Double.infinity, mxy = -Double.infinity
        for zz in [0.0, -depth] {
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
        return CGPoint(x: Double(size.width) / 2 + (rx - midX) * kValue,
                       y: Double(size.height) / 2 + (syy - midY) * kValue)
    }

    func unprojectTop(_ pt: CGPoint) -> (Double, Double) {
        let sp2 = abs(sp) < 0.15 ? (sp < 0 ? -0.15 : 0.15) : sp
        let rx = (Double(pt.x) - Double(size.width) / 2) / kValue + midX
        let ry = -((Double(pt.y) - Double(size.height) / 2) / kValue + midY) / sp2
        let x = rx * cy + ry * sy
        let y = -rx * sy + ry * cy
        return (x, y)
    }
}

// MARK: - 整件旋转/缩放

private struct TransformSheet: View {
    @Binding var spec: PartSpec
    let rotate: Bool
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
    }

    private func scalePart(_ s: Double) {
        guard s > 0.01 else { return }
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
