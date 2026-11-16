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

            Form {
                switch step {
                case 0: sketchPage
                case 1: modelPage
                case 2: drawingPage
                default: camPage
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
    }

    // MARK: - 1 草图

    private var sketchPage: some View {
        Group {
            Section("草图工具") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip("矩形", spec.template == .rect) { spec.template = .rect }
                        chip("圆", spec.template == .circle) { spec.template = .circle }
                        chip("腰形槽", spec.template == .slot) { spec.template = .slot }
                        chip("自由轮廓", spec.template == .free) { spec.template = .free }
                        chip("按矩形填入", false) { fillRectNodes() }
                        chip("加点", false) { addNode() }
                    }
                    .padding(.vertical, 2)
                }
            }

            Section("画布 · 尺寸可直接核对") {
                GeometryReader { geo in
                    Canvas { context, size in
                        drawSketch(context: context, size: size)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in moveSketchNode(value.location, size: geo.size) }
                            .onEnded { _ in dragNode = nil }
                    )
                }
                .frame(height: 330)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                Text("橙色是轮廓，蓝色尺寸是长度/角度；自由轮廓可直接拖节点，右侧数字改尺寸")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("外形尺寸") {
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
                numRow("零件厚度 H (mm)", $spec.height)
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
                }
            }

            Section {
                Button {
                    spec.template = .free
                    fillRectNodes()
                } label: {
                    Label("把当前外形转成可拖动轮廓", systemImage: "scribble")
                }
            }
        }
    }

    @State private var dragNode: Int? = nil

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
        spec.nodes[i].x = b.midX + (Double(loc.x) - Double(size.width) / 2) / k
        spec.nodes[i].y = b.midY - (Double(loc.y) - Double(size.height) / 2) / k
    }

    private func drawSketch(context: GraphicsContext, size: CGSize) {
        var ctx = context
        let b = sketchBBox()
        let k = sketchScale(b: b, size: size)
        let ox = size.width / 2, oy = size.height / 2

        func P(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: ox + (x - b.midX) * k, y: oy - (y - b.midY) * k)
        }

        // 网格 10mm
        let stepMM = 10.0
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

    // MARK: - 2 建模

    private var modelPage: some View {
        Group {
            Section("建模视图（手指 360° 旋转 / 缩放）") {
                GeometryReader { geo in
                    Canvas { context, size in
                        drawModel(context: context, size: size)
                    }
                    .contentShape(Rectangle())
                    .simultaneousGesture(DragGesture(minimumDistance: 2)
                        .onChanged { g in
                            guard !tapOnModel else { return }
                            let dx = Double(g.translation.width - lastDrag.width)
                            let dy = Double(g.translation.height - lastDrag.height)
                            lastDrag = g.translation
                            yaw += dx * 0.012
                            pitch = min(1.55, max(-1.55, pitch - dy * 0.010))
                        }
                        .onEnded { _ in lastDrag = .zero }
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
                .frame(height: 360)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                HStack(spacing: 5) {
                    viewChip("等轴") { setView(0.78, 0.62) }
                    viewChip("俯视") { setView(0, 1.5) }
                    viewChip("正视") { setView(0, 0) }
                    viewChip("右视") { setView(1.5708, 0) }
                    viewChip("仰视") { setView(0, -1.5) }
                    viewChip("复位") { yaw = 0.78; pitch = 0.62; zoom = 1; zoomBase = 1 }
                }
            }

            Section("指针 / 加特征") {
                Toggle("点图上顶面取 XY", isOn: $tapOnModel)
                HStack {
                    miniNum("X", $ptrX)
                    miniNum("Y", $ptrY)
                    Button("用这个点加孔") {
                        addFeat(.hole)
                    }
                    .font(.system(size: 12, weight: .semibold))
                }
                Text(hasPtr ? "当前指针 X\(ncf(ptrX)) Y\(ncf(ptrY))" : "还没落点：打开上面的开关，再点一下零件顶面")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("特征（孔 / 型腔）") {
                ForEach($spec.feats) { $f in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
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
                            miniNum("Ø", $f.dia)
                            miniNum("深", $f.depth)
                        }
                        Text(f.kind == .hole ? "Ø\(ncf(f.dia)) 通孔"
                             : "Ø\(ncf(f.dia)) 深\(ncf(f.depth))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Button { addFeat(.hole) } label: { Label("加孔", systemImage: "circle.circle") }
                    Spacer()
                    Button { addFeat(.pocket) } label: { Label("加型腔", systemImage: "circle.dashed") }
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
                    Button("适合窗口") { yaw = 0.78; pitch = 0.62; zoom = 1; zoomBase = 1 }
                }
                .font(.system(size: 13, weight: .semibold))
            }
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

        for f in spec.feats {
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

        for f in spec.feats {
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

    private var camPage: some View {
        Group {
            Section("加工工序（自动识别）") {
                Toggle("平面铣（顶面余量 > 0）", isOn: $spec.doFace)
                Toggle("轮廓铣（闭合外形）", isOn: $spec.doContour)
                Toggle("孔加工", isOn: $spec.doHole)
                Picker("孔方式", selection: $spec.holeMode) {
                    ForEach(HoleMode.allCases) { m in Text(m.rawValue).tag(m) }
                }
                if spec.holeMode == .g83 {
                    numRow("G83 啄钻 Q (mm)", $spec.peck)
                }
                if spec.holeMode == .tap {
                    numRow("攻丝螺距 P (mm)", $spec.tapPitch)
                    intRow("攻丝转速 S", $spec.tapRpm)
                    toolRow("丝锥", $spec.tapTool, $spec.tapDia)
                }
                Toggle("型腔铣", isOn: $spec.doPocket)
                Picker("工件坐标系", selection: $spec.coord) {
                    ForEach([54, 55, 56, 57, 58, 59], id: \.self) { n in Text("G\(n)").tag(n) }
                }
            }

            Section("本次程序包含") {
                let ops = PartProg.opList(spec)
                if ops.isEmpty {
                    Text("没有工序：检查上面的开关和模型").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(ops.indices, id: \.self) { i in
                        HStack(spacing: 8) {
                            Text("\(i + 1)")
                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                                .frame(width: 19, height: 19)
                                .background(Circle().fill(Color(red: 1.0, green: 0.42, blue: 0.10)))
                            Text(ops[i]).font(.system(size: 13))
                            Spacer()
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
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
        for i in spec.feats.indices {
            let x = spec.feats[i].x, y = spec.feats[i].y
            let rad = a * Double.pi / 180
            spec.feats[i].x = x * cos(rad) - y * sin(rad)
            spec.feats[i].y = x * sin(rad) + y * cos(rad)
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
