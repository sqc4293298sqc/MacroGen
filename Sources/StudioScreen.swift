import SwiftUI
import UIKit

/// 建模编程（iOS 对齐安卓四步）：草图 → 建模 → 出图 → 加工
struct StudioScreen: View {
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
    @State private var dragFeatID: UUID? = nil
    @State private var showDimEdit = false
    @State private var dimEditTitle = ""
    @State private var dimEditText = ""
    @State private var dimTarget: DimTarget = .none

    private enum DimTarget: Equatable {
        case none, rectL, rectW, circleD, slotL
        case nodeLen(Int), nodeAngle(Int), nodeR(Int)
    }

    init() {
        var s = PartSpec()
        s.feats = []
        _spec = State(initialValue: s)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("步骤", selection: $step) {
                Text("1 草图").tag(0)
                Text("2 建模").tag(1)
                Text("3 出图").tag(2)
                Text("4 加工").tag(3)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 4)

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
        .navigationTitle("建模编程")
        .navigationBarTitleDisplayMode(.inline)
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
        .alert("改尺寸", isPresented: $showDimEdit) {
            TextField("数值", text: $dimEditText).keyboardType(.decimalPad)
            Button("确定") { applyDimEdit() }
            Button("取消", role: .cancel) { }
        } message: {
            Text(dimEditTitle + "：输入新的毫米值 / 角度值")
        }
    }

    // MARK: - 1 草图

    private var sketchPage: some View {
        VStack(spacing: 0) {
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
                    if sketchTool == "直线" {
                        addPointAt(v.location, size: geo.size)
                    }
                })
                .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { v in
                    pickDim(at: v.location, size: geo.size)
                })
            }
            .frame(height: 320)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 4)

            Form {
                sketchControls
            }
        }
    }

    @ViewBuilder
    private var sketchControls: some View {
        Section("草图工具 · 绘制") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    chip("直线", spec.template == .free) { makeLine() }
                    chip("多段线", spec.template == .free && sketchTool == "直线") { makeLine() }
                    chip("矩形", spec.template == .rect) { sketchTool = ""; spec.template = .rect }
                    chip("中心矩形", spec.template == .rect) { sketchTool = ""; spec.template = .rect }
                    chip("圆角矩形", spec.template == .rect && spec.rectR > 0) { sketchTool = ""; spec.template = .rect; spec.rectR = 8 }
                    chip("圆", spec.template == .circle) { sketchTool = ""; spec.template = .circle }
                    chip("三点圆", sketchTool == "三点圆") { sketchTool = "三点圆" }
                    chip("圆弧", sketchTool == "圆弧") { sketchTool = "圆弧" }
                    chip("椭圆", false) { sketchTool = ""; makeEllipse() }
                    chip("多边形", false) { sketchTool = ""; makePolygon(6) }
                    chip("五角星", false) { sketchTool = ""; makeStar() }
                    chip("样条", false) { sketchTool = ""; makeSpline() }
                    chip("腰形槽", spec.template == .slot) { sketchTool = ""; spec.template = .slot }
                    chip("平行四边形", false) { sketchTool = ""; makeParallelogram() }
                    chip("点", sketchTool == "点") { sketchTool = "点" }
                    chip("自由", spec.template == .free) { sketchTool = ""; spec.template = .free; if spec.nodes.isEmpty { fillRectNodes() } }
                }
                .padding(.vertical, 2)
            }
        }

        Section("草图工具 · 编辑") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    chip("内圆", false) { addInner(.circle) }
                    chip("内方", false) { addInner(.rect) }
                    chip("修剪", false) { trimLast() }
                    chip("延伸", false) { extendLast(10) }
                    chip("打断", false) { breakLast() }
                    chip("圆角", false) { filletOuter(filletR) }
                    chip("倒角", false) { chamferOuter(chamferC) }
                    chip("围栏修剪", false) { regionTrim() }
                    chip("区域修剪", false) { regionTrim() }
                    chip("几何约束", false) { constrain(horizontal: true) }
                    chip("水平约束", false) { constrain(horizontal: true) }
                    chip("竖直约束", false) { constrain(horizontal: false) }
                    chip("等长约束", false) { equalizeSegments() }
                    chip("镜像", false) { mirrorOuter() }
                    chip("偏置", false) { offsetOuter(offsetD) }
                    chip("阵列", false) { arrayInner() }
                    chip("三点圆", false) { threePointCircle() }
                    chip("圆弧", false) { threePointArc() }
                    chip("移动轮廓", false) { moveOuter() }
                    chip("旋转零件", false) { showRotate = true }
                    chip("缩放零件", false) { showScale = true }
                    chip("清空内轮廓", false) { spec.innerLoops.removeAll() }
                }
                .padding(.vertical, 2)
            }
            Text("内圆/内方会叠在外轮廓里，建模时自动当挖穿或型腔；外轮廓和每个内轮廓都能单独改尺寸、深度。")
                .font(.caption).foregroundStyle(.secondary)
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
                Button("阵列内轮廓") { arrayInner() }
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

    private func moveSketchNode(_ loc: CGPoint, size: CGSize) {
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
        }
        guard let i = dragNode, i < spec.nodes.count else { return }
        var nx = b.midX + (Double(loc.x) - Double(size.width) / 2) / k
        var ny = b.midY - (Double(loc.y) - Double(size.height) / 2) / k
        if snapGrid, gridStep > 0.01 {
            nx = round(nx / gridStep) * gridStep
            ny = round(ny / gridStep) * gridStep
        }
        spec.nodes[i].x = nx
        spec.nodes[i].y = ny
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
            for n in spec.nodes {
                let q = P(n.x, n.y)
                ctx.fill(Path(ellipseIn: CGRect(x: q.x - 4, y: q.y - 4, width: 8, height: 8)),
                         with: .color(.blue))
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
        case .circleD:
            if v > 0.1 { spec.circleD = v }
        case .slotL:
            if v > 0.1 { spec.slotL = v }
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
        guard let f = pts.first else { return CGRect(x: -50, y: -30, width: 100, height: 60) }
        var mnx = f.x, mxx = f.x, mny = f.y, mxy = f.y
        for q in pts {
            mnx = min(mnx, q.x); mxx = max(mxx, q.x)
            mny = min(mny, q.y); mxy = max(mxy, q.y)
        }
        return CGRect(x: mnx, y: mny, width: max(mxx - mnx, 1), height: max(mxy - mny, 1))
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
        if sketchTool == "点" || sketchTool == "三点圆" || sketchTool == "圆弧" {
            refPoints.append(CGPoint(x: px, y: py))
            if sketchTool == "三点圆" && refPoints.count >= 3 { threePointCircle() }
            if sketchTool == "圆弧" && refPoints.count >= 3 { threePointArc() }
            return
        }
        if spec.nodes.isEmpty {
            spec.nodes.append(ContourNode(x: x, y: y))
        } else if let last = spec.nodes.last, hypot(x - last.x, y - last.y) > 0.2 {
            spec.nodes.append(ContourNode(x: x, y: y))
        }
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
        VStack(spacing: 0) {
            GeometryReader { geo in
                Canvas { context, size in
                    drawModel(context: context, size: size)
                }
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { g in
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
                            pitch = min(1.55, max(-1.55, pitch - dy * 0.010))
                        }
                        .onEnded { _ in lastDrag = .zero; dragFeatID = nil }
                )
                .simultaneousGesture(MagnificationGesture()
                    .onChanged { v in zoom = min(3.0, max(0.4, zoomBase * Double(v))) }
                    .onEnded { _ in zoomBase = zoom }
                )
                .simultaneousGesture(SpatialTapGesture().onEnded { v in
                    guard tapOnModel else { return }
                    let xy = modelXY(at: v.location, size: geo.size)
                    ptrX = xy.0; ptrY = xy.1; hasPtr = true
                })
                .onTapGesture(count: 2) {
                    yaw = 0.78; pitch = 0.62; zoom = 1; zoomBase = 1
                }
            }
            .frame(height: 400)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 4)

            Form {
                modelControls
            }
        }
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
    }

    private func addFeat(_ kind: PartFeatKind) {
        let b = PartProg.bbox(spec)
        var f = PartFeat(kind: kind)
        f.x = hasPtr ? ptrX : Double(b.midX)
        f.y = hasPtr ? ptrY : Double(b.midY)
        f.dia = kind == .hole ? 10 : 30
        f.depth = min(5, max(1, spec.height / 2))
        spec.feats.append(f)
    }

    private func modelCam(size: CGSize) -> Cam {
        Cam(spec: spec, yaw: yaw, pitch: pitch, zoom: zoom, size: size)
    }

    private func modelXY(at p: CGPoint, size: CGSize) -> (Double, Double) {
        modelCam(size: size).unprojectTop(p)
    }

    private func drawModel(context: GraphicsContext, size: CGSize) {
        var ctx = context
        let cam = modelCam(size: size)
        let pts = PartProg.pts(spec)
        guard pts.count > 2 else { return }
        let depth = max(spec.height, 0.1)

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

        let bottom = ringPath(-depth)
        ctx.fill(bottom, with: .color(Color.orange.opacity(0.10)))
        ctx.stroke(bottom, with: .color(Color(red: 0.70, green: 0.72, blue: 0.76)), lineWidth: 1)

        let layers = max(1, Int(ceil(depth / max(spec.stepDown, 0.1))))
        if layers > 1 {
            for i in 1..<layers {
                let z = -min(depth, Double(i) * spec.stepDown)
                ctx.stroke(ringPath(z), with: .color(Color.orange.opacity(0.20)), lineWidth: 0.7)
            }
        }
        for i in Swift.stride(from: 0, to: pts.count, by: max(1, pts.count / 30)) {
            let q = pts[i]
            ctx.stroke(Path { p in
                p.move(to: cam.p(q.x, q.y, 0))
                p.addLine(to: cam.p(q.x, q.y, -depth))
            }, with: .color(Color(red: 0.78, green: 0.80, blue: 0.83)), lineWidth: 0.8)
        }

        ctx.fill(ringPath(0), with: .color(Color.orange.opacity(0.08)))
        ctx.stroke(ringPath(0), with: .color(.orange), lineWidth: 2)

        for l in spec.innerLoops {
            let d = PartProg.drawForLoop(l, spec, depth: l.through ? spec.height + 1 : l.depth,
                                         dia: max(spec.pocketDia, 1), hNo: spec.pocketTool)
            let segs = ContourGeo.segments(ContourGeo.buildNodes(d))
            let flat = ContourGeo.flatten(segs, arcStep: 24)
            let cut = l.through ? spec.height : min(l.depth, spec.height)
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
            ctx.stroke(loopPath(-cut), with: .color(Color.red.opacity(0.55)), lineWidth: 0.9)
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

        for f in spec.feats {
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
                continue
            }
            let r = f.dia / 2
            if f.kind == .hole {
                let c = circle(f.x, f.y, 0, r)
                ctx.fill(c, with: .color(Color(white: 0.28).opacity(0.55)))
                ctx.stroke(c, with: .color(Color(white: 0.35)), lineWidth: 1.4)
                ctx.stroke(circle(f.x, f.y, -depth, r), with: .color(Color(white: 0.45)), lineWidth: 0.9)
                label(ctx, cam, f, "Ø\(ncf(f.dia))")
            } else {
                let d = min(f.depth, spec.height)
                let c = circle(f.x, f.y, 0, r)
                ctx.fill(c, with: .color(Color(red: 1.0, green: 0.42, blue: 0.10).opacity(0.18)))
                ctx.stroke(c, with: .color(Color(red: 0.95, green: 0.55, blue: 0.20)), lineWidth: 1.4)
                ctx.stroke(circle(f.x, f.y, -d, r), with: .color(Color(red: 0.95, green: 0.55, blue: 0.20).opacity(0.75)), lineWidth: 1)
                label(ctx, cam, f, "Ø\(ncf(f.dia)) 深\(ncf(f.depth))")
            }
        }

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

    private func viewChip(_ text: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color(.secondarySystemBackground)))
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

    private var b: CGRect { PartProg.bbox(spec) }
    private var depth: Double { max(spec.height, 0.1) }

    private var k: Double {
        let cy = cos(yaw), sy = sin(yaw), sp = sin(pitch), cp = cos(pitch)
        var mnx = Double.infinity, mxx = -Double.infinity
        var mny = Double.infinity, mxy = -Double.infinity
        for zz in [0.0, -depth] {
            for (xx, yy) in [(b.minX, b.minY), (b.maxX, b.minY), (b.maxX, b.maxY), (b.minX, b.maxY)] {
                let rx = Double(xx) * cy - Double(yy) * sy
                let ry = Double(xx) * sy + Double(yy) * cy
                let sx = rx
                let syy = -(ry * sp + zz * cp)
                mnx = min(mnx, sx); mxx = max(mxx, sx)
                mny = min(mny, syy); mxy = max(mxy, syy)
            }
        }
        return min((Double(size.width) - 52) / max(mxx - mnx, 1),
                   (Double(size.height) - 52) / max(mxy - mny, 1)) * zoom
    }

    private var mid: (Double, Double) {
        let cy = cos(yaw), sy = sin(yaw), sp = sin(pitch), cp = cos(pitch)
        var mnx = Double.infinity, mxx = -Double.infinity
        var mny = Double.infinity, mxy = -Double.infinity
        for zz in [0.0, -depth] {
            for (xx, yy) in [(b.minX, b.minY), (b.maxX, b.minY), (b.maxX, b.maxY), (b.minX, b.maxY)] {
                let rx = Double(xx) * cy - Double(yy) * sy
                let ry = Double(xx) * sy + Double(yy) * cy
                let sx = rx
                let syy = -(ry * sp + zz * cp)
                mnx = min(mnx, sx); mxx = max(mxx, sx)
                mny = min(mny, syy); mxy = max(mxy, syy)
            }
        }
        return ((mnx + mxx) / 2, (mny + mxy) / 2)
    }

    func p(_ x: Double, _ y: Double, _ z: Double) -> CGPoint {
        let cy = cos(yaw), sy = sin(yaw), sp = sin(pitch), cp = cos(pitch)
        let rx = x * cy - y * sy
        let ry = x * sy + y * cy
        let sx = rx
        let syy = -(ry * sp + z * cp)
        let m = mid
        return CGPoint(x: Double(size.width) / 2 + (sx - m.0) * k,
                       y: Double(size.height) / 2 + (syy - m.1) * k)
    }

    func unprojectTop(_ pt: CGPoint) -> (Double, Double) {
        let cy = cos(yaw), sy = sin(yaw), sp = sin(pitch)
        let m = mid
        let rx = (Double(pt.x) - Double(size.width) / 2) / k + m.0
        let sp2 = abs(sp) < 0.15 ? (sp < 0 ? -0.15 : 0.15) : sp
        let ry = -((Double(pt.y) - Double(size.height) / 2) / k + m.1) / sp2
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
