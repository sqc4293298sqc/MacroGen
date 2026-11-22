import Foundation
import SwiftUI

// MARK: - 草图结果

enum True3DSketchOutput {
    case base([True3DPoint], curve: True3DProfileCurve)
    case feature(True3DFeatureSpec)
    case features([True3DFeatureSpec])
}

enum True3DSketchTool: String, CaseIterable, Identifiable {
    case polyline = "折线"
    case rectangle = "矩形"
    case circle = "圆"
    case arc = "圆弧"
    case spline = "样条"
    case ellipse = "椭圆"
    case polygon = "多边形"
    case roundedRect = "圆角矩形"
    case slot = "腰形"
    case editPoint = "编辑点"
    case constraint = "约束"
    case trim = "修剪"
    case extend = "延伸"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .polyline: return "scribble.variable"
        case .rectangle: return "rectangle"
        case .circle: return "circle"
        case .arc: return "circle.dashed"
        case .spline: return "scribble"
        case .ellipse: return "oval"
        case .polygon: return "hexagon"
        case .roundedRect: return "rectangle.roundedtop"
        case .slot: return "capsule"
        case .editPoint: return "hand.point.up.left"
        case .constraint: return "lock.fill"
        case .trim: return "scissors"
        case .extend: return "arrow.right.to.line"
        }
    }
}

enum True3DSketchConstraintKind: String, CaseIterable, Identifiable {
    case horizontal = "水平"
    case vertical = "垂直"
    case distance = "距离"
    case fixed = "固定"
    case coincident = "重合"
    case tangent = "相切"
    case radius = "半径"
    case parallel = "平行"
    case perpendicular = "垂直段"
    case equalLength = "等长"
    case angle = "角度"

    var id: String { rawValue }
}

struct True3DSketchConstraint: Identifiable {
    var id = UUID()
    var kind: True3DSketchConstraintKind
    var a: Int
    var b: Int?
    var c: Int? = nil
    var d: Int? = nil
    var members: [Int] = []
    var value: Double = 0
    var anchorX: Double = 0
    var anchorY: Double = 0

    var label: String {
        switch kind {
        case .horizontal: return "水平 P\(a + 1)-P\((b ?? a) + 1)"
        case .vertical: return "垂直 P\(a + 1)-P\((b ?? a) + 1)"
        case .distance: return "距离 P\(a + 1)-P\((b ?? a) + 1) = \(String(format: "%.1f", value))"
        case .fixed: return "固定 P\(a + 1)"
        case .coincident: return "重合 P\(a + 1)=P\((b ?? a) + 1)"
        case .tangent: return "相切 P\(a + 1) 共点两段"
        case .radius: return "半径 P\(a + 1) 组 = \(String(format: "%.1f", value))"
        case .parallel: return "平行 P\(a + 1)-P\((b ?? a) + 1) ∥ P\((c ?? a) + 1)-P\((d ?? a) + 1)"
        case .perpendicular: return "垂直段 P\(a + 1)-P\((b ?? a) + 1) ⊥ P\((c ?? a) + 1)-P\((d ?? a) + 1)"
        case .equalLength: return "等长 P\(a + 1)-P\((b ?? a) + 1) = P\((c ?? a) + 1)-P\((d ?? a) + 1)"
        case .angle: return "角度 P\(c ?? a) 段 = \(String(format: "%.1f", value))°"
        }
    }
}

enum True3DSketchOperation: String, CaseIterable, Identifiable {
    case base = "作为基础轮廓"
    case boss = "拉伸凸台"
    case cut = "拉伸切除"

    var id: String { rawValue }
}

// MARK: - 草图页

/// 2D 草图：在基础块顶面网格上画折线 / 矩形 / 圆，闭合后直接拉伸凸台或切除，
/// 也可以把闭合轮廓设成基础轮廓。坐标单位 mm，原点在基础块中心。
private struct True3DLineSegment {
    var start: True3DPoint
    var end: True3DPoint
}

private enum True3DSketchTab: String, CaseIterable, Identifiable {
    case annotate = "批注"
    case draw = "绘制"
    case edit = "编辑"
    case layers = "图层"
    case constraints = "约束"
    case dimensions = "尺寸"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .annotate: return "text.bubble"
        case .draw: return "pencil.tip"
        case .edit: return "square.and.pencil"
        case .layers: return "square.stack.3d.up"
        case .constraints: return "lock"
        case .dimensions: return "ruler"
        }
    }
}

struct True3DSketchScreen: View {
    var embedded: Bool = false
    var onBaseChange: ((Double, Double) -> Void)? = nil
    var onBack: (() -> Void)? = nil
    let onDraftChange: (([True3DPoint], Bool, True3DSketchTool, [[True3DPoint]]) -> Void)?
    let onCommit: (True3DSketchOutput) -> Void

    @State private var canvasWidth: Double
    @State private var canvasDepth: Double

    init(
        width: Double,
        depth: Double,
        embedded: Bool = false,
        initialProfile: [True3DPoint] = [],
        initialClosed: Bool = false,
        initialTool: True3DSketchTool = .polyline,
        initialOperation: True3DSketchOperation = .base,
        initialSavedProfiles: [[True3DPoint]] = [],
        onBaseChange: ((Double, Double) -> Void)? = nil,
        onBack: (() -> Void)? = nil,
        onDraftChange: (([True3DPoint], Bool, True3DSketchTool, [[True3DPoint]]) -> Void)? = nil,
        onCommit: @escaping (True3DSketchOutput) -> Void
    ) {
        self.embedded = embedded
        self.onBaseChange = onBaseChange
        self.onBack = onBack
        self.onDraftChange = onDraftChange
        self.onCommit = onCommit
        _canvasWidth = State(initialValue: max(width, 1))
        _canvasDepth = State(initialValue: max(depth, 1))
        _points = State(initialValue: initialProfile)
        _closed = State(initialValue: initialClosed)
        _lastShapeTool = State(initialValue: initialTool)
        _tool = State(initialValue: initialTool)
        _operation = State(initialValue: initialOperation)
        _savedProfiles = State(initialValue: initialSavedProfiles)
        let xs = initialProfile.map(\.x)
        let ys = initialProfile.map(\.y)
        _dimensionW = State(initialValue: (xs.max() ?? 0) - (xs.min() ?? 0))
        _dimensionH = State(initialValue: (ys.max() ?? 0) - (ys.min() ?? 0))
        _selectedEntity = State(initialValue: initialClosed && initialProfile.count > 2)
    }

    @Environment(\.dismiss) private var dismiss

    @State private var tool: True3DSketchTool = .polyline
    @State private var points: [True3DPoint] = []
    @State private var previewPoints: [True3DPoint] = []
    @State private var arcPoints: [True3DPoint] = []
    @State private var dimensionW: Double = 0
    @State private var dimensionH: Double = 0
    @State private var closed = false
    @State private var gridStep: Double = 5
    @State private var snap = true
    @State private var showGrid = false
    @State private var operation: True3DSketchOperation = .base
    @State private var extrudeDepth: Double = 5
    @State private var error: String?
    @State private var canvasSize: CGSize = .zero
    @State private var dragStart: CGPoint?
    @State private var showToolDrawer = false
    @State private var polygonSides: Int = 6
    @State private var cornerRadius: Double = 5
    @State private var slotWidth: Double = 20
    @State private var offsetDistance: Double = 5
    @State private var editingPointIndex: Int?
    @State private var savedProfiles: [[True3DPoint]] = []
    @State private var patternRows = 2
    @State private var patternCols = 2
    @State private var patternPitchX: Double = 30
    @State private var patternPitchY: Double = 20
    @State private var constraints: [True3DSketchConstraint] = []
    @State private var constraintSelections: [Int] = []
    @State private var constraintDistance: Double = 20
    @State private var constraintAngle: Double = 90
    @State private var constraintRadius: Double = 20
    @State private var sketchTab: True3DSketchTab = .draw
    @State private var isSelectMode = false
    @State private var selectedEntity = false
    @State private var lastShapeTool: True3DSketchTool = .polyline
    @State private var selectionStartPoints: [True3DPoint] = []
    @State private var selectionDragOrigin: True3DPoint?
    @State private var showDimensionEditor = false
    @State private var dimensionDraft: Double = 0
    @State private var dimensionDraftH: Double = 0
    @State private var dimensionUsesRadius = false
    @State private var entityColorIndex = 0
    @State private var entityLineWidth: Double = 2
    @State private var entityDashed = false
    @State private var annotationText = ""
    @State private var showAnnotationEditor = false
    @State private var showLayerPanel = false
    @State private var layerVisible = true
    @State private var redoStack: [True3DPoint] = []
    @State private var redoClosed = false
    @State private var showAngles = false
    @State private var darkCanvas = false
    @State private var isLineMode = false
    @State private var openSegments: [True3DLineSegment] = []
    @State private var showFinishPanel = false
    @State private var marqueeStart: CGPoint?
    @State private var marqueeCurrent: CGPoint?

    private var baseWidth: CGFloat { CGFloat(max(canvasWidth, 1)) }
    private var baseDepth: CGFloat { CGFloat(max(canvasDepth, 1)) }

    var body: some View {
        ZStack {
            (darkCanvas ? SwiftUI.Color(red: 0.10, green: 0.12, blue: 0.15) : SwiftUI.Color(red: 0.91, green: 0.92, blue: 0.94))
                .ignoresSafeArea()

            sketchCanvas
                .padding(.horizontal, 12)
                .padding(.top, 116)
                .padding(.bottom, 92)

            if points.isEmpty {
                Text("从左侧选择绘制工具，右侧调节图层与约束")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(darkCanvas ? .white.opacity(0.55) : .black.opacity(0.34))
            }

            VStack(spacing: 8) {
                sketchTopBar
                sketchFilterBar
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)

            HStack(alignment: .top, spacing: 0) {
                sketchLeftRail
                Spacer(minLength: 0)
                sketchRightRail
            }
            .padding(.horizontal, 10)
            .padding(.top, 118)
            .padding(.bottom, 88)

            VStack(spacing: 7) {
                Spacer()
                if selectedEntity {
                    sketchContextBar
                }
                Text(bottomHint)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(darkCanvas ? .white.opacity(0.65) : .black.opacity(0.68))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)

            if let error {
                Text(error)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.red.opacity(0.82), in: Capsule())
                    .padding(.bottom, 190)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }

            if showToolDrawer {
                Color.black.opacity(0.18).ignoresSafeArea()
                    .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { showToolDrawer = false } }
                HStack {
                    Spacer()
                    sketchDrawer
                        .frame(width: min(320, UIScreen.main.bounds.width * 0.84))
                }
                .padding(.trailing, 8)
                .padding(.top, 110)
                .padding(.bottom, 40)
                .transition(.move(edge: .trailing))
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: closed) { newValue in
            if newValue {
                syncDimensions()
                selectedEntity = true
            }
            reportDraft()
        }
        .onChange(of: points) { _ in reportDraft() }
        .onChange(of: lastShapeTool) { _ in reportDraft() }
        .onChange(of: savedProfiles) { _ in reportDraft() }
        .onAppear { reportDraft() }
        .sheet(isPresented: $showDimensionEditor) {
            dimensionEditorCard
                .padding(18)
                .presentationDetents([.height(250)])
        }
        .sheet(isPresented: $showAnnotationEditor) {
            annotationCard
                .padding(18)
                .presentationDetents([.height(220)])
        }
        .sheet(isPresented: $showLayerPanel) {
            layerCard
                .padding(18)
                .presentationDetents([.height(220)])
        }
        .sheet(isPresented: $showFinishPanel) {
            finishCard
                .padding(18)
                .presentationDetents([.height(300)])
        }
    }

    private var sketchLeftRail: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 2) {
                sketchSideButton("选择", icon: "cursorarrow", active: isSelectMode) {
                    isSelectMode = true
                    isLineMode = false
                    tool = .editPoint
                    selectedEntity = !points.isEmpty
                }
                sketchSideButton("直线", icon: "line.diagonal", active: isLineMode) {
                    isLineMode = true
                    isSelectMode = false
                    selectedEntity = false
                    tool = .polyline
                }
                ForEach([True3DSketchTool.polyline, .rectangle, .circle, .arc, .polygon, .spline], id: \.id) { item in
                    sketchSideButton(item.rawValue, icon: item.symbol, active: !isSelectMode && !isLineMode && tool == item) {
                        tool = item
                        isSelectMode = false
                        isLineMode = false
                        selectedEntity = false
                    }
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 4)
        }
        .frame(width: 60)
        .frame(maxHeight: 380)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var sketchRightRail: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 2) {
                ForEach(True3DSketchTab.allCases) { tab in
                    sketchSideButton(tab.rawValue, icon: tab.icon, active: sketchTab == tab) {
                        selectSketchTab(tab)
                    }
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 4)
        }
        .frame(width: 60)
        .frame(maxHeight: 300)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func sketchSideButton(_ title: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 15, weight: .medium))
                Text(title).font(.system(size: 9, weight: .medium)).lineLimit(1)
            }
            .foregroundStyle(active ? SwiftUI.Color(red: 0.12, green: 0.44, blue: 0.92) : (darkCanvas ? .white.opacity(0.72) : .black.opacity(0.66)))
            .frame(width: 50, height: 40)
            .background(active ? SwiftUI.Color(red: 0.12, green: 0.44, blue: 0.92).opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func selectSketchTab(_ tab: True3DSketchTab) {
        sketchTab = tab
        switch tab {
        case .annotate: showAnnotationEditor = true
        case .layers: showLayerPanel = true
        case .constraints: showToolDrawer = true
        case .dimensions: beginDimensionEdit()
        default: break
        }
    }

    private var sketchTopBar: some View {
        HStack(spacing: 6) {
            Button {
                if let onBack { onBack() } else { dismiss() }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(darkCanvas ? .white : .black.opacity(0.78))
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)

            Text("未命名图纸-4.dxf")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(darkCanvas ? .white : .black.opacity(0.82))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(.ultraThinMaterial, in: Capsule())

            Spacer(minLength: 2)

            HStack(spacing: 0) {
                Button { undo() } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .frame(width: 36, height: 38)
                }
                .disabled(points.isEmpty && !closed && arcPoints.isEmpty)
                Rectangle().fill(Color.black.opacity(0.12)).frame(width: 0.5, height: 22)
                Button { redo() } label: {
                    Image(systemName: "arrow.uturn.forward")
                        .frame(width: 36, height: 38)
                }
                .disabled(redoStack.isEmpty)
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(darkCanvas ? .white.opacity(0.82) : .black.opacity(0.66))
            .background(.ultraThinMaterial, in: Capsule())

            Button {
                withAnimation(.easeOut(duration: 0.2)) { showFinishPanel.toggle() }
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(SwiftUI.Color(red: 0.12, green: 0.44, blue: 0.92), in: Circle())
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.easeOut(duration: 0.2)) { showToolDrawer.toggle() }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(darkCanvas ? .white : .black.opacity(0.78))
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var sketchFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                filterChip("框选", icon: "rectangle.dashed", active: isSelectMode) {
                    isSelectMode.toggle()
                    if isSelectMode {
                        tool = .editPoint
                        selectedEntity = !points.isEmpty
                    } else {
                        selectedEntity = false
                    }
                }
                filterChip("全图", icon: "arrow.up.left.and.arrow.down.right", active: false) {
                    selectedEntity = false
                    isSelectMode = false
                    if let box = bounds, box.maxX - box.minX > 0.1, box.maxY - box.minY > 0.1 {
                        canvasWidth = (box.maxX - box.minX) * 1.18
                        canvasDepth = (box.maxY - box.minY) * 1.18
                        onBaseChange?(canvasWidth, canvasDepth)
                        error = nil
                    } else {
                        error = "还没有图元可显示"
                    }
                }
                filterChip("对象捕捉", icon: "scope", active: snap) {
                    snap.toggle()
                }
                filterChip("角度", icon: "angle", active: showAngles) {
                    showAngles.toggle()
                }
                filterChip("明暗", icon: darkCanvas ? "sun.max" : "moon", active: darkCanvas) {
                    darkCanvas.toggle()
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
    }

    private func filterChip(_ title: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 13, weight: .medium))
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(active ? SwiftUI.Color(red: 0.12, green: 0.44, blue: 0.92) : (darkCanvas ? .white.opacity(0.7) : .black.opacity(0.58)))
            .padding(.horizontal, 9)
            .frame(height: 36)
            .background {
                if active {
                    Capsule().fill(SwiftUI.Color(red: 0.12, green: 0.44, blue: 0.92).opacity(0.12))
                } else {
                    Capsule().fill(.ultraThinMaterial)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var bottomHint: String {
        if showDimensionEditor { return "尺寸 · 输入新值后确定" }
        if isSelectMode { return "选择 · 点选图元 · 拖动平移" }
        if isLineMode { return "直线 · 拖动画一条开放线" }
        if selectedEntity { return "已选中图元 · 可移动 / 复制 / 改属性" }
        switch tool {
        case .polyline: return "折线 · 逐点点击，回到起点闭合"
        case .rectangle: return "矩形 · 对角拖动生成"
        case .circle: return "圆 · 从圆心向外拖动"
        case .arc: return "圆弧 · 点圆心 → 起点 → 终点"
        case .polygon: return "多边形 · 从中心向外拖动"
        case .spline: return "样条 · 逐点点击，闭合后圆滑"
        default: return "\(tool.rawValue) · 在画布上拖动"
        }
    }

    @ViewBuilder
    private var sketchModePanel: some View {
        switch sketchTab {
        case .draw:
            if selectedEntity { sketchContextBar } else { sketchToolStrip }
        case .edit:
            if selectedEntity { sketchContextBar } else { emptyEditBar }
        case .layers:
            layerBar
        case .constraints:
            constraintBar
        case .dimensions:
            dimensionBar
        case .annotate:
            annotationBar
        }
    }

    private var sketchToolStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                toolButton("选择", icon: "cursorarrow", active: isSelectMode) {
                    isSelectMode = true
                    isLineMode = false
                    tool = .editPoint
                    selectedEntity = !points.isEmpty
                }
                toolButton("直线", icon: "line.diagonal", active: isLineMode) {
                    isLineMode = true
                    isSelectMode = false
                    selectedEntity = false
                    tool = .polyline
                }
                ForEach([True3DSketchTool.polyline, .rectangle, .circle, .arc, .polygon, .spline], id: \.id) { item in
                    toolButton(item.rawValue, icon: item.symbol, active: !isSelectMode && !isLineMode && tool == item) {
                        tool = item
                        isSelectMode = false
                        isLineMode = false
                        selectedEntity = false
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func toolButton(_ title: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 18, weight: .medium))
                Text(title).font(.system(size: 10.5, weight: .medium))
            }
            .foregroundStyle(active ? SwiftUI.Color(red: 0.12, green: 0.44, blue: 0.92) : (darkCanvas ? .white.opacity(0.65) : .black.opacity(0.55)))
            .frame(minWidth: 40)
            .padding(.horizontal, 1)
            .padding(.vertical, 4)
            .background(active ? SwiftUI.Color(red: 0.12, green: 0.44, blue: 0.92).opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var sketchTabBar: some View {
        HStack(spacing: 0) {
            ForEach(True3DSketchTab.allCases) { tab in
                Button {
                    sketchTab = tab
                    switch tab {
                    case .annotate: showAnnotationEditor = true
                    case .layers: showLayerPanel = true
                    case .constraints: showToolDrawer = true
                    case .dimensions: beginDimensionEdit()
                    default: break
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon).font(.system(size: 18, weight: .regular))
                        Text(tab.rawValue).font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(sketchTab == tab ? SwiftUI.Color(red: 0.12, green: 0.44, blue: 0.92) : (darkCanvas ? .white.opacity(0.55) : .black.opacity(0.55)))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(sketchTab == tab ? SwiftUI.Color(red: 0.12, green: 0.44, blue: 0.92).opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var sketchContextBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                contextButton("移动", icon: "arrow.up.and.down.and.arrow.left.and.right") {
                    isSelectMode = true
                    tool = .editPoint
                }
                contextButton("复制", icon: "doc.on.doc") { duplicateSelectedProfile() }
                Menu {
                    Button("橙色") { entityColorIndex = 0 }
                    Button("蓝色") { entityColorIndex = 1 }
                    Button("黑色") { entityColorIndex = 2 }
                } label: {
                    contextLabel("颜色", icon: "circle.fill")
                }
                Menu {
                    Button("实线") { entityDashed = false }
                    Button("虚线") { entityDashed = true }
                } label: {
                    contextLabel("线型", icon: "line.3.horizontal")
                }
                Menu {
                    Button("细 1.2") { entityLineWidth = 1.2 }
                    Button("中 2.0") { entityLineWidth = 2.0 }
                    Button("粗 3.0") { entityLineWidth = 3.0 }
                } label: {
                    contextLabel("线宽", icon: "lineweight")
                }
                contextButton("分解", icon: "square.on.square.dashed") {
                    closed = false
                    selectedEntity = false
                    error = "已分解为控制点"
                }
                contextButton("删除", icon: "trash", destructive: true) {
                    clear()
                    selectedEntity = false
                }
                contextButton("更多", icon: "ellipsis") {
                    showToolDrawer = true
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 7)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func contextButton(_ title: String, icon: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 17, weight: .medium))
                Text(title).font(.system(size: 10.5, weight: .medium))
            }
            .foregroundStyle(destructive ? SwiftUI.Color.red.opacity(0.78) : (darkCanvas ? .white.opacity(0.72) : .black.opacity(0.62)))
            .frame(minWidth: 40)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func contextLabel(_ title: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 17, weight: .medium))
            Text(title).font(.system(size: 10.5, weight: .medium))
        }
        .foregroundStyle(darkCanvas ? .white.opacity(0.72) : .black.opacity(0.62))
        .frame(minWidth: 40)
        .padding(.vertical, 4)
    }

    private var emptyEditBar: some View {
        Text("先点“选择”，再点一个图元")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(darkCanvas ? .white.opacity(0.6) : .black.opacity(0.48))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var dimensionBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "ruler").foregroundStyle(SwiftUI.Color(red: 0.12, green: 0.44, blue: 0.92))
            Text(dimensionLabelText ?? "还没有可标注的图元")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(darkCanvas ? .white.opacity(0.72) : .black.opacity(0.62))
            Spacer(minLength: 0)
            Button("修改尺寸") { beginDimensionEdit() }
                .font(.system(size: 12, weight: .semibold))
                .buttonStyle(.borderedProminent)
                .tint(SwiftUI.Color(red: 0.12, green: 0.44, blue: 0.92))
                .disabled(!closed)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var layerBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.stack.3d.up").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("默认图层").font(.system(size: 12, weight: .semibold))
                Text("\(points.count) 个控制点 · \(savedProfiles.count) 个已保存轮廓")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("显示", isOn: $layerVisible).font(.system(size: 11)).fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var constraintBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                quickConstraint("水平", .horizontal)
                quickConstraint("垂直", .vertical)
                quickConstraint("距离", .distance)
                quickConstraint("固定", .fixed)
                quickConstraint("重合", .coincident)
                quickConstraint("角度", .angle)
                quickConstraint("半径", .radius)
                Button("更多约束") { showToolDrawer = true }
                    .font(.system(size: 11, weight: .semibold))
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func quickConstraint(_ title: String, _ kind: True3DSketchConstraintKind) -> some View {
        Button(title) { addConstraint(kind) }
            .font(.system(size: 11, weight: .semibold))
            .buttonStyle(.bordered)
            .disabled(!closed && points.count < 2)
    }

    private var annotationBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.bubble").foregroundStyle(.secondary)
            Text(annotationText.isEmpty ? "还没有批注" : annotationText)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            Spacer()
            Button("编辑批注") { showAnnotationEditor = true }
                .font(.system(size: 12, weight: .semibold))
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var dimensionEditorCard: some View {
        VStack(spacing: 10) {
            HStack {
                Text(dimensionUsesRadius ? "修改半径" : "修改尺寸")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { showDimensionEditor = false } label: { Image(systemName: "xmark") }
            }
            if dimensionUsesRadius {
                HStack {
                    Text("R").font(.system(size: 13, weight: .semibold))
                    TextField("半径", value: $dimensionDraft, format: .number.precision(.fractionLength(2)))
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                    Text("mm").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 8) {
                    Text("宽").font(.system(size: 11))
                    TextField("宽", value: $dimensionDraft, format: .number.precision(.fractionLength(2)))
                        .keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                    Text("高").font(.system(size: 11))
                    TextField("高", value: $dimensionDraftH, format: .number.precision(.fractionLength(2)))
                        .keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                    Text("mm").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            Button("确定") { applyDimensionEdit() }
                .font(.system(size: 13, weight: .semibold))
                .buttonStyle(.borderedProminent)
                .tint(SwiftUI.Color(red: 0.12, green: 0.44, blue: 0.92))
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
    }

    private var annotationCard: some View {
        VStack(spacing: 10) {
            HStack {
                Text("批注").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { showAnnotationEditor = false } label: { Image(systemName: "xmark") }
            }
            TextField("输入批注文字", text: $annotationText)
                .textFieldStyle(.roundedBorder)
            Button("完成") { showAnnotationEditor = false }
                .font(.system(size: 13, weight: .semibold))
                .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var layerCard: some View {
        VStack(spacing: 10) {
            HStack {
                Text("图层").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { showLayerPanel = false } label: { Image(systemName: "xmark") }
            }
            HStack {
                Image(systemName: "square.stack.3d.up.fill").foregroundStyle(.secondary)
                Text("默认图层").font(.system(size: 12, weight: .medium))
                Spacer()
                Toggle("", isOn: $layerVisible).labelsHidden()
            }
            Text("当前草图只有一个默认图层；颜色、线型、线宽会作用在选中图元上。")
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var finishCard: some View {
        VStack(spacing: 10) {
            HStack {
                Text("完成草图 → 3D").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { showFinishPanel = false } label: { Image(systemName: "xmark") }
            }
            Picker("操作", selection: $operation) {
                ForEach(True3DSketchOperation.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            if operation != .base {
                HStack {
                    Text("拉伸高度").font(.system(size: 11))
                    TextField("高度", value: $extrudeDepth, format: .number.precision(.fractionLength(1)))
                        .keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                    Text("mm").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            Button {
                commit()
                showFinishPanel = false
            } label: {
                Text("生成建模特征")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(SwiftUI.Color(red: 0.12, green: 0.44, blue: 0.92))
            .disabled(!closed && savedProfiles.isEmpty)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
    }

    private var sketchToolRail: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 2) {
                ForEach(True3DSketchTool.allCases) { item in
                    Button {
                        tool = item
                        previewPoints = []
                        arcPoints = []
                        error = nil
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 15, weight: .medium))
                            Text(item.rawValue)
                                .font(.system(size: 9, weight: .medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(tool == item ? SwiftUI.Color(red: 0.12, green: 0.42, blue: 0.85) : SwiftUI.Color.primary.opacity(0.74))
                        .frame(width: 52, height: 42)
                        .background(
                            tool == item
                                ? SwiftUI.Color(red: 0.12, green: 0.42, blue: 0.85).opacity(0.12)
                                : SwiftUI.Color.clear,
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { showToolDrawer = true }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "plus.square")
                            .font(.system(size: 15, weight: .medium))
                        Text("更多")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundStyle(SwiftUI.Color.primary.opacity(0.74))
                    .frame(width: 52, height: 42)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 4)
        }
        .frame(width: 60)
        .frame(maxHeight: 470)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var sketchDrawer: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("草图工具")
                        .font(.system(size: 18, weight: .bold))
                    Spacer()
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { showToolDrawer = false }
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(True3DSketchTool.allCases) { item in
                        Button {
                            tool = item
                            previewPoints = []
                            arcPoints = []
                            showToolDrawer = false
                        } label: {
                            Label(item.rawValue, systemImage: item.symbol)
                                .font(.system(size: 12, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(tool == item ? Color(red: 1.0, green: 0.42, blue: 0.10) : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 9))
                                .foregroundStyle(tool == item ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("基础块尺寸").font(.system(size: 12, weight: .semibold))
                HStack(spacing: 7) {
                    TextField("宽", value: $canvasWidth, format: .number.precision(.fractionLength(1)))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        .frame(width: 64).textFieldStyle(.roundedBorder)
                    Text("×").font(.system(size: 10)).foregroundStyle(.secondary)
                    TextField("深", value: $canvasDepth, format: .number.precision(.fractionLength(1)))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        .frame(width: 64).textFieldStyle(.roundedBorder)
                    Button("应用") {
                        onBaseChange?(max(canvasWidth,1), max(canvasDepth,1))
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .buttonStyle(.bordered)
                }

                if tool == .polygon {
                    Stepper("多边形边数 \(polygonSides)", value: $polygonSides, in: 3...12)
                        .font(.system(size: 11))
                }
                if tool == .roundedRect {
                    HStack {
                        Text("圆角 R").font(.system(size: 11))
                        TextField("R", value: $cornerRadius, format: .number.precision(.fractionLength(1)))
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                            .frame(width: 58).textFieldStyle(.roundedBorder)
                    }
                }
                if tool == .slot {
                    HStack {
                        Text("槽宽 W").font(.system(size: 11))
                        TextField("W", value: $slotWidth, format: .number.precision(.fractionLength(1)))
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                            .frame(width: 58).textFieldStyle(.roundedBorder)
                    }
                }

                Text("编辑").font(.system(size: 12, weight: .semibold))
                HStack(spacing: 6) {
                    Button("撤销") { undo() }.buttonStyle(.bordered)
                    Button("闭合") { closeProfile() }.buttonStyle(.bordered)
                    Button("清空") { clear() }.buttonStyle(.bordered)
                }
                .font(.system(size: 11))
                Divider()
                Text("约束求解").font(.system(size: 12, weight: .semibold))
                Text("切到“约束”工具点选控制点；已选 \(constraintSelections.count) 个，自由度 \(constraintDOF)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                HStack(spacing: 5) {
                    Button("水平") { addConstraint(.horizontal) }.buttonStyle(.bordered)
                    Button("垂直") { addConstraint(.vertical) }.buttonStyle(.bordered)
                    Button("固定") { addConstraint(.fixed) }.buttonStyle(.bordered)
                    Button("重合") { addConstraint(.coincident) }.buttonStyle(.bordered)
                }
                .font(.system(size: 10))
                .disabled(constraintSelections.isEmpty)
                HStack(spacing: 5) {
                    Button("平行") { addConstraint(.parallel) }.buttonStyle(.bordered)
                    Button("垂直段") { addConstraint(.perpendicular) }.buttonStyle(.bordered)
                    Button("等长") { addConstraint(.equalLength) }.buttonStyle(.bordered)
                }
                .font(.system(size: 10))
                .disabled(constraintSelections.count < 4)
                HStack(spacing: 5) {
                    TextField("距离", value: $constraintDistance, format: .number.precision(.fractionLength(1)))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        .frame(width: 52).textFieldStyle(.roundedBorder)
                    Button("距离") { addConstraint(.distance) }
                        .font(.system(size: 10)).buttonStyle(.bordered)
                        .disabled(constraintSelections.count < 2)
                    TextField("角度°", value: $constraintAngle, format: .number.precision(.fractionLength(1)))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        .frame(width: 48).textFieldStyle(.roundedBorder)
                    Button("角度") { addConstraint(.angle) }
                        .font(.system(size: 10)).buttonStyle(.bordered)
                        .disabled(constraintSelections.count < 4)
                }
                HStack(spacing: 5) {
                    Button("相切") { addConstraint(.tangent) }
                        .font(.system(size: 10)).buttonStyle(.bordered)
                        .disabled(constraintSelections.count < 3)
                    TextField("R", value: $constraintRadius, format: .number.precision(.fractionLength(1)))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        .frame(width: 48).textFieldStyle(.roundedBorder)
                    Button("半径") { addConstraint(.radius) }
                        .font(.system(size: 10)).buttonStyle(.bordered)
                        .disabled(constraintSelections.count < 3)
                }
                Button("求解全部约束") { solveConstraints() }
                    .font(.system(size: 11, weight: .semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 1.0, green: 0.42, blue: 0.10))
                    .disabled(constraints.isEmpty)
                if !constraints.isEmpty {
                    ForEach(constraints) { c in
                        HStack(spacing: 6) {
                            Image(systemName: "lock").font(.system(size: 9))
                            Text(c.label).font(.system(size: 10))
                            Spacer()
                            Button {
                                constraints.removeAll { $0.id == c.id }
                                solveConstraints()
                            } label: {
                                Image(systemName: "xmark.circle").font(.system(size: 10))
                            }
                            .buttonStyle(.plain).foregroundStyle(.red.opacity(0.7))
                        }
                    }
                }
                Divider()
                Text("草图阵列").font(.system(size: 12, weight: .semibold))
                HStack(spacing: 6) {
                    Stepper("行 \(patternRows)", value: $patternRows, in: 1...6)
                        .font(.system(size: 10))
                    Stepper("列 \(patternCols)", value: $patternCols, in: 1...6)
                        .font(.system(size: 10))
                }
                HStack(spacing: 6) {
                    TextField("X 距", value: $patternPitchX, format: .number.precision(.fractionLength(1)))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        .frame(width: 62).textFieldStyle(.roundedBorder)
                    TextField("Y 距", value: $patternPitchY, format: .number.precision(.fractionLength(1)))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        .frame(width: 62).textFieldStyle(.roundedBorder)
                    Button("生成阵列") { patternProfiles() }
                        .font(.system(size: 10, weight: .semibold))
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 1.0, green: 0.42, blue: 0.10))
                }
                Divider()
                if closed {
                    Button("存为轮廓并新建 \(savedProfiles.count + 1)") { stashProfile() }
                        .font(.system(size: 11, weight: .semibold))
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 1.0, green: 0.42, blue: 0.10))
                }
                if !savedProfiles.isEmpty {
                    HStack {
                        Text("已存 \(savedProfiles.count) 个闭合轮廓").font(.system(size: 10)).foregroundStyle(.secondary)
                        Spacer()
                        Button("清空已存") { savedProfiles.removeAll() }
                            .font(.system(size: 10)).buttonStyle(.bordered)
                    }
                    ForEach(Array(savedProfiles.enumerated()), id: \.offset) { index, profile in
                        HStack(spacing: 6) {
                            Image(systemName: "square.dashed").font(.system(size: 10))
                            Text("轮廓 \(index + 1) · \(profile.count) 点")
                                .font(.system(size: 10))
                            Spacer()
                            Button {
                                savedProfiles.remove(at: index)
                            } label: {
                                Image(systemName: "trash").font(.system(size: 10))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.red.opacity(0.7))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 6))
                    }
                }

                HStack(spacing: 6) {
                    Button("旋转90°") { rotateSketch() }.buttonStyle(.bordered)
                    Button("水平镜像") { mirrorSketch(horizontal: true) }.buttonStyle(.bordered)
                    Button("垂直镜像") { mirrorSketch(horizontal: false) }.buttonStyle(.bordered)
                }
                .font(.system(size: 10))

                if closed {
                    Text("轮廓编辑").font(.system(size: 12, weight: .semibold))
                    HStack(spacing: 6) {
                        TextField("偏置", value: $offsetDistance, format: .number.precision(.fractionLength(1)))
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                            .frame(width: 54).textFieldStyle(.roundedBorder)
                        Button("外偏置") { offsetProfile(by: abs(offsetDistance)) }.buttonStyle(.bordered)
                        Button("内偏置") { offsetProfile(by: -abs(offsetDistance)) }.buttonStyle(.bordered)
                    }
                    .font(.system(size: 10))
                    HStack(spacing: 6) {
                        Button("圆角 R\(fmt(cornerRadius))") { roundProfileCorners(radius: cornerRadius) }.buttonStyle(.bordered)
                        Button("反向") { reverseProfile() }.buttonStyle(.bordered)
                        Button("清除约束") { syncDimensions() }.buttonStyle(.bordered)
                    }
                    .font(.system(size: 10))
                }
            }
            .padding(14)
            .padding(.bottom, 30)
        }
        .background(.regularMaterial)
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.black.opacity(0.12)).frame(width: 0.5)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: 顶部工具条

    private var topBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { showToolDrawer = true }
                } label: {
                    Label("工具 · \(tool.rawValue)", systemImage: "square.grid.2x2")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color(red: 1.0, green: 0.42, blue: 0.10), in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Divider().frame(height: 22)

                Toggle("吸附", isOn: $snap)
                    .font(.system(size: 12))
                    .fixedSize()
                Toggle("网格", isOn: $showGrid)
                    .font(.system(size: 12))
                    .fixedSize()
                Text("格 \(String(format: "%.0f", gridStep))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { showToolDrawer = true }
                } label: {
                    Label("基础 \(fmt(canvasWidth))×\(fmt(canvasDepth))", systemImage: "cube")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    // MARK: 基础块缩放

    private var baseBar: some View {
        HStack(spacing: 7) {
            Image(systemName: "cube")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("基础块")
                .font(.system(size: 11, weight: .semibold))
            TextField("宽", value: $canvasWidth, format: .number.precision(.fractionLength(1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 62)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
            Text("×")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            TextField("深", value: $canvasDepth, format: .number.precision(.fractionLength(1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 62)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
            Button("应用") {
                canvasWidth = max(canvasWidth, 1)
                canvasDepth = max(canvasDepth, 1)
                onBaseChange?(canvasWidth, canvasDepth)
                error = nil
            }
            .font(.system(size: 11, weight: .semibold))
            .buttonStyle(.bordered)
            Spacer(minLength: 4)
            Text("画超范围自动扩")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: 画布

    private var sketchCanvas: some View {
        GeometryReader { geo in
            Canvas { context, size in
                drawGrid(context: &context, size: size)
                drawSavedProfiles(context: &context, size: size)
                drawOpenSegments(context: &context, size: size)
                drawProfile(context: &context, size: size)
                drawDimension(context: &context, size: size)
                drawMarquee(context: &context)
                drawPreview(context: &context, size: size)
            }
            .background(Color(red: 0.96, green: 0.97, blue: 0.98))
            .overlay(alignment: .topLeading) {
                Text(tool == .arc
                     ? "点圆心 → 起点 → 终点，自动用弦闭合"
                     : tool == .spline
                     ? "逐点画样条；点回起点或按“闭合轮廓”自动圆滑"
                     : tool == .polyline
                     ? "逐点点击画折线；点回起点或按“闭合轮廓”结束"
                     : tool == .editPoint
                     ? "拖动已有控制点修改轮廓；松手即更新尺寸"
                     : tool == .constraint
                     ? "点选控制点（最多 4 个）加约束：2 点用于水平/垂直/距离，4 点用于平行/垂直段/等长/角度"
                     : tool == .trim
                     ? "点中要删除的控制点，轮廓自动把两侧线段接起来"
                     : tool == .extend
                     ? "点最后一个控制点外侧，末段沿延长线拉到你点的位置"
                     : "按住拖动画\(tool.rawValue)，松开生成闭合轮廓")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.88), in: Capsule())
                    .padding(10)
            }
            .overlay {
                if let point = dimensionLabelPoint(in: geo.size) {
                    Button { beginDimensionEdit() } label: {
                        Text(dimensionLabelText ?? "")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SwiftUI.Color(red: 0.10, green: 0.42, blue: 0.90))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.clear)
                    }
                    .buttonStyle(.plain)
                    .position(point)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let b = worldPoint(value.location, in: geo.size)
                        if isLineMode {
                            let a = worldPoint(value.startLocation, in: geo.size)
                            previewPoints = [a, b]
                            return
                        }
                        if isSelectMode {
                            if selectionDragOrigin == nil {
                                selectionDragOrigin = b
                                selectionStartPoints = points
                                selectedEntity = pointInsideProfile(b)
                                if !selectedEntity {
                                    marqueeStart = value.startLocation
                                    marqueeCurrent = value.location
                                }
                            }
                            if selectedEntity, let origin = selectionDragOrigin {
                                let dx = b.x - origin.x
                                let dy = b.y - origin.y
                                points = selectionStartPoints.map { True3DPoint(x: $0.x + dx, y: $0.y + dy) }
                                return
                            }
                            if marqueeStart != nil {
                                marqueeCurrent = value.location
                            }
                            return
                        }
                        if tool == .constraint || tool == .trim || tool == .extend { return }
                        if tool == .editPoint {
                            guard closed else { return }
                            if dragStart == nil {
                                dragStart = value.startLocation
                                editingPointIndex = nearestPointIndex(to: b)
                            }
                            if let index = editingPointIndex, index < points.count {
                                points[index] = snapped(b)
                                ensureCanvasContains(points)
                                solveConstraints(quiet: true)
                            }
                            return
                        }
                        guard tool != .polyline, !closed else { return }
                        if dragStart == nil { dragStart = value.startLocation }
                        let a = worldPoint(value.startLocation, in: geo.size)
                        previewPoints = shapePoints(from: a, to: b)
                    }
                    .onEnded { value in
                        defer {
                            dragStart = nil
                            previewPoints = []
                            editingPointIndex = nil
                        }
                        if selectedEntity, !isSelectMode,
                           hypot(value.translation.width, value.translation.height) < 4,
                           !pointInsideProfile(worldPoint(value.location, in: geo.size)) {
                            selectedEntity = false
                            previewPoints = []
                            return
                        }
                        if isLineMode {
                            let a = worldPoint(value.startLocation, in: geo.size)
                            let b = worldPoint(value.location, in: geo.size)
                            if hypot(b.x - a.x, b.y - a.y) > 0.5 {
                                openSegments.append(True3DLineSegment(start: a, end: b))
                            }
                            previewPoints = []
                            error = nil
                            return
                        }
                        if isSelectMode {
                            if let start = marqueeStart, let end = marqueeCurrent {
                                let rect = CGRect(
                                    x: min(start.x, end.x),
                                    y: min(start.y, end.y),
                                    width: abs(end.x - start.x),
                                    height: abs(end.y - start.y)
                                )
                                if rect.width > 8, rect.height > 8, rect.intersects(profileScreenRect(in: geo.size)) {
                                    selectedEntity = true
                                }
                            }
                            marqueeStart = nil
                            marqueeCurrent = nil
                            selectionDragOrigin = nil
                            selectionStartPoints = []
                            syncDimensions()
                            error = nil
                            return
                        }
                        if tool == .editPoint { solveConstraints(quiet: true); syncDimensions(); error = nil; return }
                        let a = worldPoint(value.startLocation, in: geo.size)
                        let b = worldPoint(value.location, in: geo.size)
                        if tool == .constraint {
                            handleConstraintTap(snapped(b))
                            return
                        }
                        if tool == .trim {
                            trimNearestPoint(snapped(b))
                            return
                        }
                        if tool == .extend {
                            extendLastPoint(to: snapped(b))
                            return
                        }
                        guard !closed else { return }
                        switch tool {
                        case .editPoint, .constraint, .trim, .extend:
                            break
                        case .polyline:
                            addPolylinePoint(snapped(b))
                        case .arc:
                            handleArcTap(snapped(b))
                        case .spline:
                            addPolylinePoint(snapped(b), maximumPoints: 32)
                        case .rectangle, .circle, .ellipse, .polygon, .roundedRect, .slot:
                            let shape = shapePoints(from: a, to: b)
                            guard shape.count >= 3 else {
                                error = "轮廓太小，至少画 \(String(format: "%.0f", gridStep)) mm"
                                return
                            }
                            ensureCanvasContains(shape)
                            points = shape
                            closed = true
                            lastShapeTool = tool
                            selectedEntity = true
                            error = nil
                        }
                    }
            )
            .onAppear { canvasSize = geo.size }
            .onChange(of: geo.size) { newSize in canvasSize = newSize }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .frame(maxHeight: .infinity)
    }

    private func drawGrid(context: inout GraphicsContext, size: CGSize) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(darkCanvas ? Color(red: 0.10, green: 0.12, blue: 0.15) : Color(red: 0.91, green: 0.92, blue: 0.94)))

        let s = scale(for: size)
        let halfW = baseWidth / 2
        let halfD = baseDepth / 2
        let rect = CGRect(
            x: size.width / 2 - halfW * s,
            y: size.height / 2 - halfD * s,
            width: baseWidth * s,
            height: baseDepth * s
        )
        guard showGrid else { return }
        context.fill(Path(rect), with: .color(darkCanvas ? Color(red: 0.15, green: 0.17, blue: 0.21) : Color.white))
        context.stroke(Path(rect), with: .color(darkCanvas ? Color.white.opacity(0.16) : Color.black.opacity(0.16)), lineWidth: 1.5)
        let step = max(gridStep, 0.5) * Double(s)
        guard step > 3 else { return }

        var x = rect.minX
        while x <= rect.maxX + 0.5 {
            var p = Path()
            p.move(to: CGPoint(x: x, y: rect.minY))
            p.addLine(to: CGPoint(x: x, y: rect.maxY))
            context.stroke(p, with: .color(darkCanvas ? Color.white.opacity(0.06) : Color.black.opacity(0.055)), lineWidth: 0.7)
            x += step
        }
        var y = rect.minY
        while y <= rect.maxY + 0.5 {
            var p = Path()
            p.move(to: CGPoint(x: rect.minX, y: y))
            p.addLine(to: CGPoint(x: rect.maxX, y: y))
            context.stroke(p, with: .color(darkCanvas ? Color.white.opacity(0.06) : Color.black.opacity(0.055)), lineWidth: 0.7)
            y += step
        }

        var axisX = Path()
        axisX.move(to: CGPoint(x: rect.minX, y: rect.midY))
        axisX.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        context.stroke(axisX, with: .color(Color.blue.opacity(0.18)), lineWidth: 0.8)
        var axisY = Path()
        axisY.move(to: CGPoint(x: rect.midX, y: rect.minY))
        axisY.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        context.stroke(axisY, with: .color(Color.blue.opacity(0.18)), lineWidth: 0.8)
    }

    private func drawSavedProfiles(context: inout GraphicsContext, size: CGSize) {
        for profile in savedProfiles where profile.count > 1 {
            let mapped = profile.map { viewPoint($0, in: size) }
            var path = Path()
            path.move(to: mapped[0])
            for p in mapped.dropFirst() { path.addLine(to: p) }
            path.closeSubpath()
            context.fill(path, with: .color(Color(red: 0.25, green: 0.35, blue: 0.45).opacity(0.07)))
            context.stroke(path, with: .color(Color(red: 0.25, green: 0.35, blue: 0.45).opacity(0.55)), lineWidth: 1.2)
        }
    }

    private func profileScreenRect(in size: CGSize) -> CGRect {
        guard !points.isEmpty else { return .zero }
        let mapped = points.map { viewPoint($0, in: size) }
        let minX = mapped.map(\.x).min() ?? 0
        let maxX = mapped.map(\.x).max() ?? 0
        let minY = mapped.map(\.y).min() ?? 0
        let maxY = mapped.map(\.y).max() ?? 0
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func drawMarquee(context: inout GraphicsContext) {
        guard let start = marqueeStart, let end = marqueeCurrent else { return }
        let rect = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
        let path = Path(rect)
        context.fill(path, with: .color(Color(red: 0.12, green: 0.44, blue: 0.92).opacity(0.08)))
        context.stroke(
            path,
            with: .color(Color(red: 0.12, green: 0.44, blue: 0.92).opacity(0.7)),
            style: StrokeStyle(lineWidth: 1, dash: [5, 4])
        )
    }

    private func drawOpenSegments(context: inout GraphicsContext, size: CGSize) {
        for segment in openSegments {
            var path = Path()
            path.move(to: viewPoint(segment.start, in: size))
            path.addLine(to: viewPoint(segment.end, in: size))
            context.stroke(path, with: .color(Color(red: 0.20, green: 0.44, blue: 0.72)), lineWidth: 1.6)
        }
    }

    private func drawProfile(context: inout GraphicsContext, size: CGSize) {
        guard points.count > 1, layerVisible else { return }
        let mapped = points.map { viewPoint($0, in: size) }
        var path = Path()
        path.move(to: mapped[0])
        for p in mapped.dropFirst() { path.addLine(to: p) }
        if closed { path.closeSubpath() }

        if closed {
            let fillAlpha = selectedEntity ? 0.16 : 0.07
            context.fill(path, with: .color(Color(red: 0.95, green: 0.32, blue: 0.06).opacity(fillAlpha)))
        }
        var style = StrokeStyle(lineWidth: CGFloat(entityLineWidth), dash: entityDashed ? [7, 5] : [])
        style.lineWidth = selectedEntity ? max(CGFloat(entityLineWidth) + 0.6, 2) : CGFloat(entityLineWidth)
        context.stroke(path, with: .color(entityColor), style: style)

        guard selectedEntity else { return }
        let handlePoints: [CGPoint]
        if let circle = circleGeometry {
            let center = viewPoint(circle.center, in: size)
            let r = CGFloat(circle.radius) * scale(for: size)
            handlePoints = [
                CGPoint(x: center.x, y: center.y - r),
                CGPoint(x: center.x + r, y: center.y),
                CGPoint(x: center.x, y: center.y + r),
                CGPoint(x: center.x - r, y: center.y),
                center
            ]
        } else {
            handlePoints = mapped
        }
        for p in handlePoints {
            let rect = CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)
            context.fill(Path(rect), with: .color(.white))
            context.stroke(Path(rect), with: .color(Color(red: 0.10, green: 0.42, blue: 0.90)), lineWidth: 1.8)
        }
    }

    private var entityColor: Color {
        switch entityColorIndex {
        case 1: return Color(red: 0.10, green: 0.42, blue: 0.90)
        case 2: return Color.black.opacity(0.72)
        default: return Color(red: 0.95, green: 0.32, blue: 0.06)
        }
    }

    private func angleAtFirstVertex() -> Double? {
        guard points.count >= 3 else { return nil }
        let a = points[points.count - 1]
        let b = points[0]
        let c = points[1]
        let v1 = (a.x - b.x, a.y - b.y)
        let v2 = (c.x - b.x, c.y - b.y)
        let l1 = hypot(v1.0, v1.1)
        let l2 = hypot(v2.0, v2.1)
        guard l1 > 0.01, l2 > 0.01 else { return nil }
        let cosValue = max(-1, min(1, (v1.0 * v2.0 + v1.1 * v2.1) / (l1 * l2)))
        return acos(cosValue) * 180 / .pi
    }

    private func drawDimension(context: inout GraphicsContext, size: CGSize) {
        guard closed, points.count > 2, let box = bounds else { return }
        if let circle = circleGeometry {
            let center = viewPoint(circle.center, in: size)
            let radius = CGFloat(circle.radius) * scale(for: size)
            let label = CGPoint(x: center.x + radius * 0.58, y: center.y - radius * 0.58)
            var path = Path()
            path.move(to: center)
            path.addLine(to: label)
            context.stroke(path, with: .color(Color(red: 0.10, green: 0.42, blue: 0.90)), lineWidth: 1.2)
            let tick = Path(ellipseIn: CGRect(x: label.x - 3, y: label.y - 3, width: 6, height: 6))
            context.stroke(tick, with: .color(Color(red: 0.10, green: 0.42, blue: 0.90)), lineWidth: 1.2)
        } else {
            let topY = viewPoint(True3DPoint(x: 0, y: box.maxY), in: size).y
            let left = viewPoint(True3DPoint(x: box.minX, y: box.maxY), in: size)
            let right = viewPoint(True3DPoint(x: box.maxX, y: box.maxY), in: size)
            var path = Path()
            path.move(to: CGPoint(x: left.x, y: topY - 14))
            path.addLine(to: CGPoint(x: right.x, y: topY - 14))
            context.stroke(path, with: .color(Color(red: 0.10, green: 0.42, blue: 0.90)), lineWidth: 1.1)

            if showAngles, points.count >= 3, let angle = angleAtFirstVertex() {
                let labelPoint = CGPoint(x: viewPoint(points[0], in: size).x + 24, y: viewPoint(points[0], in: size).y - 14)
                context.draw(
                    Text(String(format: "%.1f°", angle))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(red: 0.10, green: 0.42, blue: 0.90)),
                    at: labelPoint
                )
            }
        }
    }

    private func drawPreview(context: inout GraphicsContext, size: CGSize) {
        guard previewPoints.count > 1 else { return }
        let mapped = previewPoints.map { viewPoint($0, in: size) }
        var path = Path()
        path.move(to: mapped[0])
        for p in mapped.dropFirst() { path.addLine(to: p) }
        path.closeSubpath()
        context.fill(path, with: .color(Color(red: 1.0, green: 0.42, blue: 0.10).opacity(0.10)))
        context.stroke(path, with: .color(Color.orange.opacity(0.7)), lineWidth: 1.2)
    }

    // MARK: 尺寸摘要 / 底部操作

    private var summaryBar: some View {
        let box = bounds
        return HStack(spacing: 14) {
            Text("\(savedProfiles.count + (closed ? 1 : 0)) 轮廓 · \(points.count) 点")
            Text(closed ? "已闭合" : "未闭合")
                .foregroundStyle(closed ? .green : .orange)
            if let box {
                Text("X \(fmt(box.maxX - box.minX)) × Y \(fmt(box.maxY - box.minY)) mm")
            }
            Spacer()
            if closed {
                Button("存为轮廓") { stashProfile() }
                    .font(.system(size: 12, weight: .semibold))
            }
            Button(closed ? "重新画" : "闭合轮廓") {
                if closed {
                    points = []
                    closed = false
                    dimensionW = 0
                    dimensionH = 0
                } else {
                    closeProfile()
                }
            }
            .font(.system(size: 12, weight: .semibold))
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if closed {
                HStack(spacing: 6) {
                    Text("尺寸").font(.system(size: 10)).foregroundStyle(.secondary)
                    TextField("宽", value: $dimensionW, format: .number.precision(.fractionLength(1)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 52)
                        .textFieldStyle(.roundedBorder)
                    Text("×").font(.system(size: 10)).foregroundStyle(.secondary)
                    TextField("高", value: $dimensionH, format: .number.precision(.fractionLength(1)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 52)
                        .textFieldStyle(.roundedBorder)
                    Button("应用") { applyDimensions() }
                        .font(.system(size: 11, weight: .semibold))
                        .buttonStyle(.bordered)
                    Button("水平/垂直") { applyOrthoConstraints() }
                        .font(.system(size: 11, weight: .semibold))
                        .buttonStyle(.bordered)
                }
            }
            HStack(spacing: 10) {
                Picker("操作", selection: $operation) {
                    ForEach(True3DSketchOperation.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.menu)
                .font(.system(size: 12))

                if operation != .base {
                    HStack(spacing: 4) {
                        Text(operation == .boss ? "高度" : "深度")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        TextField("5", value: $extrudeDepth, format: .number.precision(.fractionLength(1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 58)
                            .textFieldStyle(.roundedBorder)
                        Text("mm").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    commit()
                } label: {
                    Label("生成建模特征", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 1.0, green: 0.42, blue: 0.10))
                .disabled((points.count < 3 || !closed) && savedProfiles.isEmpty)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: 几何辅助

    private func scale(for size: CGSize) -> CGFloat {
        let usableW = max(size.width - 44, 1)
        let usableH = max(size.height - 44, 1)
        return min(usableW / baseWidth, usableH / baseDepth)
    }

    private func viewPoint(_ p: True3DPoint, in size: CGSize) -> CGPoint {
        let s = scale(for: size)
        return CGPoint(
            x: size.width / 2 + CGFloat(p.x) * s,
            y: size.height / 2 - CGFloat(p.y) * s
        )
    }

    private func worldPoint(_ p: CGPoint, in size: CGSize) -> True3DPoint {
        let s = scale(for: size)
        return True3DPoint(
            x: Double((p.x - size.width / 2) / max(s, 0.1)),
            y: Double((size.height / 2 - p.y) / max(s, 0.1))
        )
    }

    // MARK: 修剪 / 延伸

    private func trimNearestPoint(_ p: True3DPoint) {
        guard points.count > 3 else {
            error = "至少保留 3 个点"
            return
        }
        guard let index = nearestPointIndex(to: p) else {
            error = "点中要修剪掉的控制点"
            return
        }
        points.remove(at: index)
        constraints = []
        constraintSelections = []
        if closed, points.count < 3 { closed = false }
        syncDimensions()
        error = nil
    }

    private func extendLastPoint(to target: True3DPoint) {
        guard !closed, points.count >= 2 else {
            error = "延伸只作用于未闭合的折线/样条末段"
            return
        }
        let a = points[points.count - 2]
        let b = points[points.count - 1]
        let dx = b.x - a.x, dy = b.y - a.y
        let len = hypot(dx, dy)
        guard len > 1e-6 else {
            error = "末段长度为 0，无法延伸"
            return
        }
        let ux = dx / len, uy = dy / len
        let projection = (target.x - a.x) * ux + (target.y - a.y) * uy
        guard projection > len + 1e-6 else {
            error = "点在末段内侧；请点到末点外侧的延长线上"
            return
        }
        points[points.count - 1] = True3DPoint(x: a.x + ux * projection, y: a.y + uy * projection)
        ensureCanvasContains(points)
        constraints = []
        constraintSelections = []
        syncDimensions()
        error = nil
    }

    // MARK: 约束求解

    private func circumcenter(_ a: True3DPoint, _ b: True3DPoint, _ c: True3DPoint) -> True3DPoint? {
        let d = 2 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
        guard abs(d) > 1e-7 else { return nil }
        let a2 = a.x * a.x + a.y * a.y
        let b2 = b.x * b.x + b.y * b.y
        let c2 = c.x * c.x + c.y * c.y
        let ux = (a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / d
        let uy = (a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / d
        return True3DPoint(x: ux, y: uy)
    }

    /// 当前轮廓应按折线还是平滑曲线拉伸。圆/椭圆/圆角矩形/腰形/样条都走平滑。
    private func curveKind(for points: [True3DPoint]) -> True3DProfileCurve {
        if points.count >= 24 { return .smooth }
        if [True3DSketchTool.spline, .ellipse, .roundedRect, .slot, .circle].contains(lastShapeTool) {
            return .smooth
        }
        return .polyline
    }

    private func cleanedProfile(_ source: [True3DPoint]) -> [True3DPoint] {
        var result: [True3DPoint] = []
        for p in source {
            if let last = result.last, hypot(p.x - last.x, p.y - last.y) < 0.05 { continue }
            result.append(p)
        }
        if result.count > 2, let first = result.first, let last = result.last,
           hypot(first.x - last.x, first.y - last.y) < 0.05 {
            result.removeLast()
        }
        return result
    }

    private var constraintDOF: Int {
        var dof = points.count * 2
        for c in constraints {
            if c.kind == .fixed { dof -= 2 }
            else if c.kind == .coincident { dof -= 2 }
            else { dof -= 1 }
        }
        return max(dof, 0)
    }

    private func handleConstraintTap(_ p: True3DPoint) {
        guard let index = nearestPointIndex(to: p) else {
            error = "没点中控制点；切到“约束”工具后点蓝色圆点"
            return
        }
        if let existing = constraintSelections.firstIndex(of: index) {
            constraintSelections.remove(at: existing)
        } else {
            if constraintSelections.count >= 4 { constraintSelections.removeFirst() }
            constraintSelections.append(index)
        }
        error = nil
    }

    private func addConstraint(_ kind: True3DSketchConstraintKind) {
        guard !points.isEmpty else {
            error = "先画轮廓再添加约束"
            return
        }
        let needed: Int
        switch kind {
        case .fixed: needed = 1
        case .tangent, .radius: needed = 3
        case .parallel, .perpendicular, .equalLength, .angle: needed = 4
        case .horizontal, .vertical, .distance, .coincident: needed = 2
        }
        guard constraintSelections.count >= needed else {
            error = "\(kind.rawValue)约束需要先选 \(needed) 个控制点"
            return
        }
        let a = constraintSelections[0]
        let b = needed > 1 ? constraintSelections[1] : nil
        let c = needed >= 3 ? constraintSelections[2] : nil
        let d = needed == 4 ? constraintSelections[3] : nil
        let maxIndex = points.count - 1
        guard a >= 0, a <= maxIndex,
              (b ?? 0) <= maxIndex,
              (c ?? 0) <= maxIndex,
              (d ?? 0) <= maxIndex else {
            constraintSelections = []
            return
        }
        if kind == .distance, constraintDistance <= 0.01 {
            error = "距离必须大于 0.01 mm"
            return
        }
        if kind == .angle, constraintAngle <= 0.01 || constraintAngle >= 180 {
            error = "角度必须在 0°～180° 之间"
            return
        }
        if kind == .radius, constraintRadius <= 0.01 {
            error = "半径必须大于 0.01 mm"
            return
        }
        var members: [Int] = []
        var value: Double = 0
        if kind == .distance { value = constraintDistance }
        if kind == .angle { value = constraintAngle }
        if kind == .radius {
            value = constraintRadius
            let c1 = points[a]
            let c2 = points[b ?? a]
            let c3 = points[c ?? a]
            if let center = circumcenter(c1, c2, c3) {
                let base = (hypot(c1.x - center.x, c1.y - center.y)
                    + hypot(c2.x - center.x, c2.y - center.y)
                    + hypot(c3.x - center.x, c3.y - center.y)) / 3
                members = points.indices.filter { idx in
                    let d = hypot(points[idx].x - center.x, points[idx].y - center.y)
                    return d > base * 0.55 && d < base * 1.45
                }
            }
        }
        constraints.append(True3DSketchConstraint(
            kind: kind, a: a, b: b, c: c, d: d, members: members, value: value,
            anchorX: points[a].x, anchorY: points[a].y
        ))
        constraintSelections = []
        solveConstraints()
    }

    private func solveConstraints(quiet: Bool = false) {
        guard !constraints.isEmpty, points.count >= 2 else { return }
        var p = points
        for _ in 0..<80 {
            for c in constraints {
                guard c.a >= 0, c.a < p.count else { continue }
                switch c.kind {
                case .horizontal:
                    if let b = c.b, b >= 0, b < p.count {
                        let y = (p[c.a].y + p[b].y) / 2
                        p[c.a].y = y; p[b].y = y
                    }
                case .vertical:
                    if let b = c.b, b >= 0, b < p.count {
                        let x = (p[c.a].x + p[b].x) / 2
                        p[c.a].x = x; p[b].x = x
                    }
                case .distance:
                    if let b = c.b, b >= 0, b < p.count, c.value > 0.001 {
                        let dx = p[b].x - p[c.a].x
                        let dy = p[b].y - p[c.a].y
                        let len = hypot(dx, dy)
                        if len > 1e-9 {
                            let ux = dx / len, uy = dy / len
                            let target = c.value
                            let mx = (p[c.a].x + p[b].x) / 2
                            let my = (p[c.a].y + p[b].y) / 2
                            p[c.a].x = mx - ux * target / 2
                            p[c.a].y = my - uy * target / 2
                            p[b].x = mx + ux * target / 2
                            p[b].y = my + uy * target / 2
                        } else {
                            p[b].x = p[c.a].x + c.value
                        }
                    }
                case .coincident:
                    if let b = c.b, b >= 0, b < p.count {
                        p[b].x = p[c.a].x; p[b].y = p[c.a].y
                    }
                case .tangent:
                    guard let b = c.b, let cIdx = c.c, b >= 0, b < p.count, cIdx >= 0, cIdx < p.count else { continue }
                    let l1x = p[b].x - p[c.a].x, l1y = p[b].y - p[c.a].y
                    let l2x = p[cIdx].x - p[c.a].x, l2y = p[cIdx].y - p[c.a].y
                    let len1 = hypot(l1x, l1y), len2 = hypot(l2x, l2y)
                    guard len1 > 1e-8, len2 > 1e-8 else { continue }
                    var tx = l1x / len1 - l2x / len2
                    var ty = l1y / len1 - l2y / len2
                    if hypot(tx, ty) < 1e-8 { tx = l1x / len1; ty = l1y / len1 }
                    let tl = hypot(tx, ty)
                    tx /= tl; ty /= tl
                    p[b].x = p[c.a].x + tx * len1; p[b].y = p[c.a].y + ty * len1
                    p[cIdx].x = p[c.a].x - tx * len2; p[cIdx].y = p[c.a].y - ty * len2
                case .radius:
                    guard let b = c.b, let cIdx = c.c, !c.members.isEmpty,
                          b >= 0, b < p.count, cIdx >= 0, cIdx < p.count else { continue }
                    let rr = max(c.value, 0.05)
                    let center = circumcenter(p[c.a], p[b], p[cIdx])
                        ?? True3DPoint(x: (p[c.a].x + p[b].x + p[cIdx].x) / 3,
                                       y: (p[c.a].y + p[b].y + p[cIdx].y) / 3)
                    for idx in c.members where idx >= 0 && idx < p.count {
                        let dx = p[idx].x - center.x, dy = p[idx].y - center.y
                        let d = hypot(dx, dy)
                        if d > 1e-9 {
                            p[idx].x = center.x + dx / d * rr
                            p[idx].y = center.y + dy / d * rr
                        }
                    }
                case .parallel, .perpendicular, .equalLength, .angle:
                    guard let b = c.b, let cIdx = c.c, let d = c.d,
                          b >= 0, b < p.count, cIdx >= 0, cIdx < p.count, d >= 0, d < p.count else { continue }
                    let ax = p[b].x - p[c.a].x, ay = p[b].y - p[c.a].y
                    let cx = p[d].x - p[cIdx].x, cy = p[d].y - p[cIdx].y
                    let len1 = hypot(ax, ay), len2 = hypot(cx, cy)
                    guard len1 > 1e-8, len2 > 1e-8 else { continue }
                    let ux1 = ax / len1, uy1 = ay / len1
                    let ux2 = cx / len2, uy2 = cy / len2
                    if c.kind == .equalLength {
                        let avg = (len1 + len2) / 2
                        let m1x = (p[c.a].x + p[b].x) / 2
                        let m1y = (p[c.a].y + p[b].y) / 2
                        p[c.a].x = m1x - ux1 * avg / 2; p[c.a].y = m1y - uy1 * avg / 2
                        p[b].x = m1x + ux1 * avg / 2; p[b].y = m1y + uy1 * avg / 2
                        let m2x = (p[cIdx].x + p[d].x) / 2
                        let m2y = (p[cIdx].y + p[d].y) / 2
                        p[cIdx].x = m2x - ux2 * avg / 2; p[cIdx].y = m2y - uy2 * avg / 2
                        p[d].x = m2x + ux2 * avg / 2; p[d].y = m2y + uy2 * avg / 2
                    } else {
                        let dirX: Double
                        let dirY: Double
                        switch c.kind {
                        case .parallel:
                            let sign: Double = (ux1 * ux2 + uy1 * uy2) >= 0 ? 1 : -1
                            dirX = ux1 * sign; dirY = uy1 * sign
                        case .perpendicular:
                            let cand1 = (-uy1, ux1)
                            let cand2 = (uy1, -ux1)
                            let dot1 = cand1.0 * ux2 + cand1.1 * uy2
                            let dot2 = cand2.0 * ux2 + cand2.1 * uy2
                            if dot1 >= dot2 { dirX = cand1.0; dirY = cand1.1 }
                            else { dirX = cand2.0; dirY = cand2.1 }
                        case .angle:
                            let rad = min(max(c.value, 0.1), 179.9) * .pi / 180
                            let ca = cos(rad), sa = sin(rad)
                            var candX = ux1 * ca - uy1 * sa
                            var candY = ux1 * sa + uy1 * ca
                            let dot = candX * ux2 + candY * uy2
                            if dot < 0 {
                                candX = ux1 * ca + uy1 * sa
                                candY = -ux1 * sa + uy1 * ca
                            }
                            dirX = candX; dirY = candY
                        default:
                            dirX = ux1; dirY = uy1
                        }
                        p[d].x = p[cIdx].x + dirX * len2
                        p[d].y = p[cIdx].y + dirY * len2
                    }
                case .fixed:
                    p[c.a].x = c.anchorX
                    p[c.a].y = c.anchorY
                }
            }
        }
        points = p
        if !quiet {
            ensureCanvasContains(points)
            syncDimensions()
            error = nil
        }
    }

    private func nearestPointIndex(to p: True3DPoint) -> Int? {
        guard !points.isEmpty else { return nil }
        var best: (Int, Double)?
        for (i, q) in points.enumerated() {
            let d = hypot(q.x - p.x, q.y - p.y)
            if best == nil || d < best!.1 { best = (i, d) }
        }
        guard let best, best.1 <= max(gridStep, 2) else { return nil }
        return best.0
    }

    private func snapped(_ p: True3DPoint) -> True3DPoint {
        guard snap else { return p }
        var candidates = points
        for segment in openSegments {
            candidates.append(segment.start)
            candidates.append(segment.end)
        }
        let tolerance = max(gridStep * 0.45, 0.6)
        if let nearest = candidates.min(by: { hypot($0.x - p.x, $0.y - p.y) < hypot($1.x - p.x, $1.y - p.y) }),
           hypot(nearest.x - p.x, nearest.y - p.y) <= tolerance {
            return nearest
        }
        return p
    }

    private func shapePoints(from a: True3DPoint, to b: True3DPoint) -> [True3DPoint] {
        switch tool {
        case .polyline:
            return []
        case .rectangle:
            let minX = min(a.x, b.x), maxX = max(a.x, b.x)
            let minY = min(a.y, b.y), maxY = max(a.y, b.y)
            guard maxX - minX > 0.1, maxY - minY > 0.1 else { return [] }
            return [
                True3DPoint(x: minX, y: minY),
                True3DPoint(x: maxX, y: minY),
                True3DPoint(x: maxX, y: maxY),
                True3DPoint(x: minX, y: maxY)
            ]
        case .circle:
            let r = hypot(b.x - a.x, b.y - a.y)
            guard r > 0.1 else { return [] }
            return (0..<48).map { i in
                let angle = Double(i) / 48.0 * 2 * .pi
                return True3DPoint(x: a.x + r * cos(angle), y: a.y + r * sin(angle))
            }
        case .arc, .spline, .editPoint, .constraint, .trim, .extend:
            return []
        case .ellipse:
            let rx = abs(b.x - a.x), ry = abs(b.y - a.y)
            guard rx > 0.1, ry > 0.1 else { return [] }
            return (0..<64).map { i in
                let angle = Double(i) / 64.0 * 2 * .pi
                return True3DPoint(x: a.x + rx * cos(angle), y: a.y + ry * sin(angle))
            }
        case .polygon:
            let r = hypot(b.x - a.x, b.y - a.y)
            guard r > 0.1, polygonSides >= 3 else { return [] }
            let start = atan2(b.y - a.y, b.x - a.x)
            return (0..<polygonSides).map { i in
                let angle = start + Double(i) / Double(polygonSides) * 2 * .pi
                return True3DPoint(x: a.x + r * cos(angle), y: a.y + r * sin(angle))
            }
        case .roundedRect:
            let minX = min(a.x, b.x), maxX = max(a.x, b.x)
            let minY = min(a.y, b.y), maxY = max(a.y, b.y)
            let w = maxX - minX, h = maxY - minY
            guard w > 0.1, h > 0.1 else { return [] }
            let r = min(max(cornerRadius, 0), min(w, h) / 2 - 0.001)
            if r < 0.05 {
                return [
                    True3DPoint(x: minX, y: minY), True3DPoint(x: maxX, y: minY),
                    True3DPoint(x: maxX, y: maxY), True3DPoint(x: minX, y: maxY)
                ]
            }
            var result: [True3DPoint] = []
            let centers = [
                (True3DPoint(x: maxX - r, y: maxY - r), 0.0),
                (True3DPoint(x: minX + r, y: maxY - r), Double.pi / 2),
                (True3DPoint(x: minX + r, y: minY + r), Double.pi),
                (True3DPoint(x: maxX - r, y: minY + r), 3 * Double.pi / 2)
            ]
            for (center, start) in centers {
                for i in 0...8 {
                    let angle = start + Double(i) / 8.0 * Double.pi / 2
                    result.append(True3DPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle)))
                }
            }
            return result
        case .slot:
            let dx = b.x - a.x, dy = b.y - a.y
            let dist = hypot(dx, dy)
            let r = min(max(slotWidth, 0.2), 200) / 2
            guard dist > 0.1 else { return [] }
            let angle = atan2(dy, dx)
            var result: [True3DPoint] = []
            for i in 0...10 {
                let a1 = angle - Double.pi / 2 + Double(i) / 10.0 * Double.pi
                result.append(True3DPoint(x: b.x + r * cos(a1), y: b.y + r * sin(a1)))
            }
            for i in 0...10 {
                let a1 = angle + Double.pi / 2 + Double(i) / 10.0 * Double.pi
                result.append(True3DPoint(x: a.x + r * cos(a1), y: a.y + r * sin(a1)))
            }
            return result
        }
    }

    /// 三点圆弧：圆心 → 起点 → 终点。生成逆时针圆弧后用弦直接闭合，
    /// 让圆弧轮廓可以直接作为基础轮廓或拉伸特征。
    private func handleArcTap(_ p: True3DPoint) {
        guard !closed else { return }
        ensureCanvasContains([p])
        arcPoints.append(p)
        previewPoints = arcPoints
        guard arcPoints.count == 3 else {
            error = nil
            return
        }
        let center = arcPoints[0]
        let start = arcPoints[1]
        let end = arcPoints[2]
        let radius = hypot(start.x - center.x, start.y - center.y)
        guard radius > max(gridStep, 0.5) else {
            error = "圆弧半径太小"
            arcPoints = []
            previewPoints = []
            return
        }
        let a0 = atan2(start.y - center.y, start.x - center.x)
        let a1 = atan2(end.y - center.y, end.x - center.x)
        var sweep = a1 - a0
        if sweep <= 0 { sweep += 2 * .pi }
        let count = max(16, Int(sweep * radius / 2.0))
        let arc = (0...count).map { i -> True3DPoint in
            let a = a0 + sweep * Double(i) / Double(count)
            return True3DPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a))
        }
        ensureCanvasContains(arc)
        points = arc
        closed = true
        lastShapeTool = .arc
        selectedEntity = true
        arcPoints = []
        previewPoints = []
        error = nil
    }

    private func addPolylinePoint(_ p: True3DPoint, maximumPoints: Int = 200) {
        if points.count >= 3, let first = points.first, hypot(p.x - first.x, p.y - first.y) < max(gridStep, 0.5) {
            closed = true
            lastShapeTool = tool == .spline ? .spline : .polyline
            selectedEntity = true
            error = nil
            return
        }
        ensureCanvasContains([p])
        guard points.count < maximumPoints else {
            error = "点数已达上限，按“闭合轮廓”生成曲线"
            return
        }
        points.append(p)
        closed = false
        error = nil
    }

    private func ensureCanvasContains(_ pts: [True3DPoint]) {
        guard let maxX = pts.map({ abs($0.x) }).max(),
              let maxY = pts.map({ abs($0.y) }).max() else { return }
        let neededW = ceil((maxX * 2 + 6) / 10) * 10
        let neededD = ceil((maxY * 2 + 6) / 10) * 10
        if neededW > canvasWidth { canvasWidth = max(neededW, 20) }
        if neededD > canvasDepth { canvasDepth = max(neededD, 20) }
    }

    private var dimensionLabelText: String? {
        guard closed, points.count > 2, let box = bounds else { return nil }
        if let circle = circleGeometry {
            return "R\(String(format: "%.2f", circle.radius))"
        }
        return "\(String(format: "%.1f", box.maxX - box.minX)) × \(String(format: "%.1f", box.maxY - box.minY))"
    }

    private func dimensionLabelPoint(in size: CGSize) -> CGPoint? {
        guard closed, points.count > 2, let box = bounds else { return nil }
        if let circle = circleGeometry {
            let center = viewPoint(circle.center, in: size)
            let radius = CGFloat(circle.radius) * scale(for: size)
            return CGPoint(x: center.x + radius * 0.58, y: center.y - radius * 0.58)
        }
        let midX = (box.minX + box.maxX) / 2
        return CGPoint(x: viewPoint(True3DPoint(x: midX, y: box.maxY), in: size).x, y: viewPoint(True3DPoint(x: midX, y: box.maxY), in: size).y - 22)
    }

    private func beginDimensionEdit() {
        guard closed, points.count > 2, let box = bounds else {
            error = "先画一个闭合图元"
            return
        }
        if let circle = circleGeometry {
            dimensionUsesRadius = true
            dimensionDraft = circle.radius
        } else {
            dimensionUsesRadius = false
            dimensionDraft = box.maxX - box.minX
            dimensionDraftH = box.maxY - box.minY
        }
        showDimensionEditor = true
    }

    private func applyDimensionEdit() {
        guard closed, points.count > 2, let box = bounds else { return }
        if dimensionUsesRadius, let circle = circleGeometry {
            guard dimensionDraft > 0.1 else { error = "半径必须大于 0.1 mm"; return }
            let radius = dimensionDraft
            points = (0..<48).map { i in
                let angle = Double(i) / 48.0 * 2 * .pi
                return True3DPoint(x: circle.center.x + radius * cos(angle), y: circle.center.y + radius * sin(angle))
            }
            lastShapeTool = .circle
        } else {
            guard dimensionDraft > 0.1, dimensionDraftH > 0.1 else { error = "尺寸必须大于 0.1 mm"; return }
            dimensionW = dimensionDraft
            dimensionH = dimensionDraftH
            applyDimensions()
        }
        syncDimensions()
        dimensionDraft = dimensionUsesRadius ? (circleGeometry?.radius ?? dimensionDraft) : (box.maxX - box.minX)
        showDimensionEditor = false
        selectedEntity = true
        error = nil
    }

    private func duplicateSelectedProfile() {
        guard closed, points.count > 2 else { return }
        savedProfiles.append(points.map { True3DPoint(x: $0.x + 8, y: $0.y + 8) })
        error = "已复制一份，偏移 8 mm"
    }

    private func reportDraft() {
        onDraftChange?(points, closed, lastShapeTool, savedProfiles)
    }

    private func syncDimensions() {
        guard let box = bounds else { return }
        dimensionW = box.maxX - box.minX
        dimensionH = box.maxY - box.minY
    }

    private func applyDimensions() {
        guard let box = bounds else { return }
        let sourceW = box.maxX - box.minX
        let sourceH = box.maxY - box.minY
        guard sourceW > 0.01, sourceH > 0.01, dimensionW > 0.1, dimensionH > 0.1 else {
            error = "尺寸必须大于 0.1 mm"
            return
        }
        let cx = (box.minX + box.maxX) / 2
        let cy = (box.minY + box.maxY) / 2
        let sx = dimensionW / sourceW
        let sy = dimensionH / sourceH
        let scaled = points.map {
            True3DPoint(x: cx + ($0.x - cx) * sx, y: cy + ($0.y - cy) * sy)
        }
        ensureCanvasContains(scaled)
        points = scaled
        error = nil
    }

    private func applyOrthoConstraints() {
        guard points.count >= 3 else { return }
        var adjusted = points
        for i in 1..<adjusted.count {
            let prev = adjusted[i - 1]
            let cur = adjusted[i]
            let dx = abs(cur.x - prev.x)
            let dy = abs(cur.y - prev.y)
            if dx < 1e-6 { continue }
            if dy < 1e-6 { continue }
            if dx < dy * 0.5 {
                adjusted[i].x = prev.x
            } else if dy < dx * 0.5 {
                adjusted[i].y = prev.y
            }
        }
        points = adjusted
        syncDimensions()
        error = nil
    }

    private func rotateSketch() {
        guard !points.isEmpty else { return }
        let rotated = points.map { True3DPoint(x: -$0.y, y: $0.x) }
        ensureCanvasContains(rotated)
        points = rotated
        error = nil
    }

    private func mirrorSketch(horizontal: Bool) {
        guard !points.isEmpty else { return }
        points = points.map {
            horizontal
                ? True3DPoint(x: -$0.x, y: $0.y)
                : True3DPoint(x: $0.x, y: -$0.y)
        }
        error = nil
    }

    private func offsetProfile(by delta: Double) {
        guard closed, points.count >= 3, abs(delta) > 0.01 else {
            error = "先把轮廓闭合，偏置量要大于 0.01 mm"
            return
        }
        let pts = points
        let n = pts.count
        let area = signedArea(pts)
        let orient: Double = area >= 0 ? 1 : -1
        var lines: [(p: True3DPoint, e: True3DPoint)] = []
        for i in 0..<n {
            let a = pts[i], b = pts[(i + 1) % n]
            let dx = b.x - a.x, dy = b.y - a.y
            let len = max(hypot(dx, dy), 0.0001)
            let ex = dx / len, ey = dy / len
            let outward = True3DPoint(x: orient * ey, y: -orient * ex)
            lines.append((True3DPoint(x: a.x + outward.x * delta, y: a.y + outward.y * delta), True3DPoint(x: ex, y: ey)))
        }
        var result: [True3DPoint] = []
        for i in 0..<n {
            let prev = lines[(i - 1 + n) % n]
            let cur = lines[i]
            let cross = prev.e.x * cur.e.y - prev.e.y * cur.e.x
            if abs(cross) < 1e-9 {
                result.append(True3DPoint(x: cur.p.x, y: cur.p.y))
                continue
            }
            let qx = cur.p.x - prev.p.x, qy = cur.p.y - prev.p.y
            let t = (qx * cur.e.y - qy * cur.e.x) / cross
            let x = prev.p.x + prev.e.x * t
            let y = prev.p.y + prev.e.y * t
            result.append(True3DPoint(x: x, y: y))
        }
        let changed = result.filter { $0.x.isFinite && $0.y.isFinite }
        guard changed.count == n else {
            error = "偏置后轮廓自交，减小偏置量"
            return
        }
        ensureCanvasContains(changed)
        points = changed
        syncDimensions()
        error = nil
    }

    private func roundProfileCorners(radius: Double) {
        guard closed, points.count >= 3, radius > 0.05 else {
            error = "圆角半径必须大于 0.05 mm"
            return
        }
        let pts = points
        let n = pts.count
        var result: [True3DPoint] = []
        for i in 0..<n {
            let prev = pts[(i - 1 + n) % n]
            let cur = pts[i]
            let next = pts[(i + 1) % n]
            let lenPrev = max(hypot(cur.x - prev.x, cur.y - prev.y), 0.0001)
            let lenNext = max(hypot(next.x - cur.x, next.y - cur.y), 0.0001)
            let d = min(radius, lenPrev / 2, lenNext / 2)
            let start = True3DPoint(
                x: cur.x + (prev.x - cur.x) * d / lenPrev,
                y: cur.y + (prev.y - cur.y) * d / lenPrev
            )
            let end = True3DPoint(
                x: cur.x + (next.x - cur.x) * d / lenNext,
                y: cur.y + (next.y - cur.y) * d / lenNext
            )
            for j in 0...8 {
                let t = Double(j) / 8.0
                let mt = 1 - t
                result.append(True3DPoint(
                    x: mt * mt * start.x + 2 * mt * t * cur.x + t * t * end.x,
                    y: mt * mt * start.y + 2 * mt * t * cur.y + t * t * end.y
                ))
            }
        }
        ensureCanvasContains(result)
        points = result
        syncDimensions()
        error = nil
    }

    private func reverseProfile() {
        guard points.count >= 3 else { return }
        points.reverse()
        error = nil
    }

    private func signedArea(_ pts: [True3DPoint]) -> Double {
        guard pts.count >= 3 else { return 0 }
        var sum = 0.0
        for i in 0..<pts.count {
            let a = pts[i], b = pts[(i + 1) % pts.count]
            sum += a.x * b.y - b.x * a.y
        }
        return sum / 2
    }

    private func patternProfiles() {
        var bases = savedProfiles.map { cleanedProfile($0) }.filter { $0.count >= 3 }
        if closed, points.count >= 3 {
            bases.append(cleanedProfile(points))
        }
        guard !bases.isEmpty else {
            error = "先画一个闭合轮廓，或存入至少一个轮廓"
            return
        }
        let rows = max(1, min(patternRows, 6))
        let cols = max(1, min(patternCols, 6))
        guard rows * cols <= 36 else {
            error = "阵列数量过多，最多 36 个"
            return
        }
        var all: [[True3DPoint]] = []
        for base in bases {
            for r in 0..<rows {
                for c in 0..<cols {
                    if r == 0 && c == 0 { continue }
                    let offsetX = Double(c) * patternPitchX
                    let offsetY = Double(r) * patternPitchY
                    all.append(base.map { True3DPoint(x: $0.x + offsetX, y: $0.y + offsetY) })
                }
            }
        }
        savedProfiles = bases + all
        points = []
        constraints = []
        constraintSelections = []
        closed = false
        dimensionW = 0
        dimensionH = 0
        ensureCanvasContains(savedProfiles.flatMap { $0 })
        error = nil
    }

    private func stashProfile() {
        guard closed, points.count >= 3 else {
            error = "当前轮廓还没闭合"
            return
        }
        savedProfiles.append(cleanedProfile(points))
        points = []
        constraints = []
        constraintSelections = []
        closed = false
        dimensionW = 0
        dimensionH = 0
        error = nil
    }

    private func closeProfile() {
        guard points.count >= 3 else {
            error = "至少需要 3 个点才能闭合"
            return
        }
        if tool == .spline, !closed {
            let smoothed = smoothClosed(points, samples: 8)
            ensureCanvasContains(smoothed)
            points = smoothed
            constraints = []
            constraintSelections = []
        }
        closed = true
        lastShapeTool = tool == .spline ? .spline : .polyline
        selectedEntity = true
        error = nil
    }

    /// 闭合 Catmull-Rom 样条，把逐点折线变成连续光滑轮廓。
    private func smoothClosed(_ points: [True3DPoint], samples: Int) -> [True3DPoint] {
        guard points.count >= 3 else { return points }
        let n = points.count
        var result: [True3DPoint] = []
        result.reserveCapacity(n * samples)
        for i in 0..<n {
            let p0 = points[(i - 1 + n) % n]
            let p1 = points[i]
            let p2 = points[(i + 1) % n]
            let p3 = points[(i + 2) % n]
            for j in 0..<samples {
                let t = Double(j) / Double(samples)
                let t2 = t * t
                let t3 = t2 * t
                let x = 0.5 * ((2 * p1.x) + (-p0.x + p2.x) * t
                    + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2
                    + (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3)
                let y = 0.5 * ((2 * p1.y) + (-p0.y + p2.y) * t
                    + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2
                    + (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3)
                result.append(True3DPoint(x: x, y: y))
            }
        }
        return result
    }

    private func undo() {
        if !arcPoints.isEmpty {
            arcPoints.removeLast()
            previewPoints = arcPoints
        } else if closed {
            redoStack = points
            redoClosed = true
            closed = false
        } else if !points.isEmpty {
            redoStack.append(points.removeLast())
            redoClosed = false
        }
        constraints = constraints.compactMap { c in
            let maxIndex = points.count - 1
            guard c.a <= maxIndex, (c.b ?? 0) <= maxIndex else { return nil }
            return c
        }
        constraintSelections = constraintSelections.filter { $0 <= points.count - 1 }
        error = nil
    }

    private func redo() {
        if redoClosed {
            guard !redoStack.isEmpty else { return }
            points = redoStack
            redoStack = []
            redoClosed = false
            closed = true
            selectedEntity = true
            syncDimensions()
            error = nil
            return
        }
        guard !redoStack.isEmpty else { return }
        points.append(redoStack.removeLast())
        closed = false
        error = nil
    }

    private func clear() {
        points = []
        previewPoints = []
        arcPoints = []
        closed = false
        constraints = []
        constraintSelections = []
        lastShapeTool = .polyline
        selectedEntity = false
        redoStack = []
        redoClosed = false
        openSegments = []
        error = nil
    }

    private var isCircleProfile: Bool {
        closed && lastShapeTool == .circle && points.count >= 3
    }

    private var circleGeometry: (center: True3DPoint, radius: Double)? {
        guard isCircleProfile, let box = bounds else { return nil }
        let center = True3DPoint(x: (box.minX + box.maxX) / 2, y: (box.minY + box.maxY) / 2)
        let radius = max(box.maxX - box.minX, box.maxY - box.minY) / 2
        return (center, radius)
    }

    private func pointInsideProfile(_ p: True3DPoint) -> Bool {
        guard closed, points.count >= 3 else { return false }
        if let circle = circleGeometry {
            return hypot(p.x - circle.center.x, p.y - circle.center.y) <= circle.radius * 1.05
        }
        var inside = false
        var j = points.count - 1
        for i in 0..<points.count {
            let a = points[i], b = points[j]
            if (a.y > p.y) != (b.y > p.y) {
                let x = (b.x - a.x) * (p.y - a.y) / ((b.y - a.y) == 0 ? 0.000001 : (b.y - a.y)) + a.x
                if p.x < x { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    private var bounds: (minX: Double, maxX: Double, minY: Double, maxY: Double)? {
        guard let minX = points.map(\.x).min(),
              let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(),
              let maxY = points.map(\.y).max() else { return nil }
        return (minX, maxX, minY, maxY)
    }

    private func commit() {
        let currentIsValid = closed && points.count >= 3
        guard currentIsValid || !savedProfiles.isEmpty else {
            error = "至少需要 1 个闭合轮廓"
            return
        }
        if currentIsValid, let box = bounds, box.maxX - box.minX <= 0.1 || box.maxY - box.minY <= 0.1 {
            error = "当前草图尺寸太小"
            return
        }

        if operation == .base {
            guard currentIsValid else {
                error = "基础轮廓需要一个当前闭合轮廓"
                return
            }
            guard savedProfiles.isEmpty else {
                error = "多轮廓不能同时作为基础轮廓；请只保留一个轮廓，或改用凸台/切除"
                return
            }
        }

        onBaseChange?(canvasWidth, canvasDepth)
        switch operation {
        case .base:
            onCommit(.base(cleanedProfile(points), curve: curveKind(for: points)))
        case .boss, .cut:
            var profiles = savedProfiles
            if currentIsValid { profiles.append(points) }
            let specs = profiles.compactMap { profile -> True3DFeatureSpec? in
                let clean = cleanedProfile(profile)
                guard clean.count >= 3 else { return nil }
                var feature = True3DFeatureSpec(kind: operation == .boss ? .profileBoss : .profileCut)
                feature.name = operation == .boss ? "草图凸台" : "草图切除"
                feature.profile = clean
                feature.profileCurve = curveKind(for: clean)
                feature.depth = max(extrudeDepth, 0.1)
                feature.bossHeight = max(extrudeDepth, 0.1)
                return feature
            }
            if specs.count == 1 {
                onCommit(.feature(specs[0]))
            } else {
                onCommit(.features(specs))
            }
        }
        if !embedded { dismiss() }
    }

    private func fmt(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.0001 { return String(format: "%.0f", value) }
        return String(format: "%.1f", value)
    }
}
