import SwiftUI
import UIKit

/// 绘图编程（三段式）：草图 → 立体 → 加工
struct PartScreen: View {
    @State private var spec = PartSpec()
    @State private var step = 0
    @State private var code = ""
    @State private var showResult = false

    @State private var yaw = 0.78
    @State private var pitch = 0.62
    @State private var zoom = 1.0
    @State private var zoomBase = 1.0
    @State private var lastDrag: CGSize = .zero

    var body: some View {
        VStack(spacing: 0) {
            Picker("步骤", selection: $step) {
                Text("草图").tag(0)
                Text("立体").tag(1)
                Text("加工").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)

            Form {
                if step == 0 {
                    sketchSection
                } else if step == 1 {
                    solidSection
                } else {
                    camSection
                }
            }
        }
        .navigationTitle("绘图编程")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showResult) {
            PartResultView(code: code)
        }
    }

    // MARK: - 草图

    @ViewBuilder
    private var sketchSection: some View {
        Section("外形草图") {
            Picker("形状", selection: $spec.template) {
                ForEach(ContourTemplate.allCases) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)

            switch spec.template {
            case .rect:
                numRow("长 L (mm)", $spec.rectL)
                numRow("宽 W (mm)", $spec.rectW)
                numRow("四角 R（0 = 直角）", $spec.rectR)
            case .circle:
                numRow("直径 (mm)", $spec.circleD)
            case .slot:
                numRow("槽总长 L（含圆弧）", $spec.slotL)
                numRow("槽宽 W", $spec.slotW)
            case .free:
                EmptyView()
            }
            numRow("零件厚度 (mm)", $spec.height)
        }

        if spec.template == .free {
            Section("节点（末点自动连回起点）") {
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
                HStack {
                    Button {
                        spec.nodes.append(ContourNode(x: spec.nodes.last?.x ?? 0, y: (spec.nodes.last?.y ?? 0) + 10))
                    } label: {
                        Label("加点", systemImage: "plus.circle")
                    }
                    Spacer()
                    Button("清空") { spec.nodes = [] }
                }
            }
        }

        Section("特征（孔 / 沉台）") {
            ForEach($spec.feats) { $f in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Picker("", selection: $f.kind) {
                            ForEach(PartFeatKind.allCases) { k in
                                Text(k.rawValue).tag(k)
                            }
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
                        if f.kind == .pocket {
                            miniNum("深", $f.depth)
                        }
                    }
                }
            }

            HStack {
                Button {
                    addFeat(.hole)
                } label: {
                    Label("加孔", systemImage: "circle.circle")
                }
                Spacer()
                Button {
                    addFeat(.pocket)
                } label: {
                    Label("加沉台", systemImage: "circle.dashed")
                }
            }
        }

        Section {
            let b = PartProg.bbox(spec)
            Text("\(spec.feats.count) 个特征 · 外形 \(ncf(Double(b.width))) × \(ncf(Double(b.height))) · 厚 \(ncf(spec.height))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 立体

    @ViewBuilder
    private var solidSection: some View {
        Section("立体预览") {
            Canvas { context, size in
                drawPart(context: context, size: size)
            }
            .frame(height: 320)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .simultaneousGesture(DragGesture(minimumDistance: 2)
                .onChanged { g in
                    let dx = Double(g.translation.width - lastDrag.width)
                    let dy = Double(g.translation.height - lastDrag.height)
                    lastDrag = g.translation
                    yaw += dx * 0.012
                    pitch = min(1.45, max(0.12, pitch - dy * 0.010))
                }
                .onEnded { _ in lastDrag = .zero }
            )
            .simultaneousGesture(MagnificationGesture()
                .onChanged { v in
                    zoom = min(3.0, max(0.4, zoomBase * Double(v)))
                }
                .onEnded { _ in zoomBase = zoom }
            )
            .onTapGesture(count: 2) {
                yaw = 0.78; pitch = 0.62; zoom = 1; zoomBase = 1
            }

            Text("拖动转视角 · 双指缩放 · 双击复位")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("图上看到的是什么") {
            Text("橙色是零件外形，深灰圆是孔（贯通到底），浅橙圆是沉台（只到设定深度）。立体是按「零件厚度」拉出来的，用来核对形状和位置，不是切削结果。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 加工

    @ViewBuilder
    private var camSection: some View {
        Section("工序（按模型自动排）") {
            ForEach(PartProg.opList(spec).indices, id: \.self) { i in
                HStack(spacing: 8) {
                    Text("\(i + 1)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color(red: 1.0, green: 0.42, blue: 0.10)))
                    Text(PartProg.opList(spec)[i]).font(.system(size: 14))
                }
            }
            Toggle("先铣顶面", isOn: $spec.doFace)
            Toggle("铣外形轮廓", isOn: $spec.doContour)
        }

        Section("刀具（T / D）") {
            toolRow("顶面", $spec.faceTool, $spec.faceDia)
            toolRow("外形", $spec.contourTool, $spec.contourDia)
            toolRow("孔", $spec.holeTool, $spec.holeDia)
            toolRow("沉台", $spec.pocketTool, $spec.pocketDia)
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
                        .font(.footnote)
                        .foregroundStyle(.orange)
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

    // MARK: - 小部件

    private func addFeat(_ kind: PartFeatKind) {
        let b = PartProg.bbox(spec)
        var f = PartFeat(kind: kind)
        f.x = Double(b.midX)
        f.y = Double(b.midY)
        f.dia = kind == .hole ? 10 : 30
        f.depth = min(5, max(1, spec.height / 2))
        spec.feats.append(f)
    }

    private func numRow(_ title: String, _ value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 96)
        }
    }

    private func intRow(_ title: String, _ value: Binding<Int>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 96)
        }
    }

    private func miniNum(_ title: String, _ value: Binding<Double>) -> some View {
        HStack(spacing: 3) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 13))
                .frame(width: 48)
        }
    }

    private func toolRow(_ title: String, _ t: Binding<Int>, _ d: Binding<Double>) -> some View {
        HStack(spacing: 6) {
            Text(title).frame(width: 44, alignment: .leading)
            Text("T").font(.system(size: 11)).foregroundStyle(.secondary)
            TextField("1", value: t, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .frame(width: 34)
            Text("D").font(.system(size: 11)).foregroundStyle(.secondary)
            TextField("6", value: d, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 54)
            Spacer()
        }
        .font(.system(size: 14))
    }

    // MARK: - 立体绘制

    private func drawPart(context: GraphicsContext, size: CGSize) {
        var ctx = context
        let p = spec
        let pts = PartProg.pts(p)
        guard pts.count > 2 else { return }

        let b = PartProg.bbox(p)
        let depth = max(p.height, 0.1)
        let stepD = max(p.stepDown, 0.1)
        let layers = max(1, Int(ceil(depth / stepD)))

        let cy = cos(yaw), sy = sin(yaw)
        let sp = sin(pitch), cp = cos(pitch)
        func raw(_ x: Double, _ y: Double, _ z: Double) -> (Double, Double) {
            let rx = x * cy - y * sy
            let ry = x * sy + y * cy
            return (rx, -(ry * sp + z * cp))
        }

        var mnx = Double.infinity, mxx = -Double.infinity
        var mny = Double.infinity, mxy = -Double.infinity
        for zz in [0.0, -depth] {
            for (xx, yy) in [(b.minX, b.minY), (b.maxX, b.minY), (b.maxX, b.maxY), (b.minX, b.maxY)] {
                let r = raw(Double(xx), Double(yy), zz)
                mnx = min(mnx, r.0); mxx = max(mxx, r.0)
                mny = min(mny, r.1); mxy = max(mxy, r.1)
            }
        }
        let pad = 26.0
        let w = max(mxx - mnx, 1), h = max(mxy - mny, 1)
        let k = min((size.width - pad * 2) / w, (size.height - pad * 2) / h) * zoom
        let ox = size.width / 2, oy = size.height / 2
        let mx = (mnx + mxx) / 2, my = (mny + mxy) / 2

        func P(_ x: Double, _ y: Double, _ z: Double) -> CGPoint {
            let r = raw(x, y, z)
            return CGPoint(x: ox + (r.0 - mx) * k, y: oy + (r.1 - my) * k)
        }

        func ringPath(_ pts: [CGPoint], _ z: Double) -> Path {
            var path = Path()
            guard let f = pts.first else { return path }
            path.move(to: P(f.x, f.y, z))
            for q in pts.dropFirst() {
                path.addLine(to: P(q.x, q.y, z))
            }
            return path
        }

        func circlePath(_ cx: Double, _ cyy: Double, _ z: Double, _ r: Double) -> Path {
            var path = Path()
            for i in 0...28 {
                let a = Double(i) / 28.0 * 2 * Double.pi
                let q = P(cx + r * cos(a), cyy + r * sin(a), z)
                if i == 0 { path.move(to: q) } else { path.addLine(to: q) }
            }
            return path
        }

        // 底面 + 分层 + 竖边
        let bottom = ringPath(pts, -depth)
        ctx.fill(bottom, with: .color(Color.orange.opacity(0.10)))
        ctx.stroke(bottom, with: .color(Color(red: 0.70, green: 0.72, blue: 0.76)), lineWidth: 1)

        if layers > 1 {
            for i in 1..<layers {
                let z = -min(depth, Double(i) * stepD)
                ctx.stroke(ringPath(pts, z), with: .color(Color.orange.opacity(0.22)), lineWidth: 0.7)
            }
        }

        let strideStep = max(1, pts.count / 30)
        for i in Swift.stride(from: 0, to: pts.count, by: strideStep) {
            let q = pts[i]
            ctx.stroke(Path { pp in
                pp.move(to: P(q.x, q.y, 0))
                pp.addLine(to: P(q.x, q.y, -depth))
            }, with: .color(Color(red: 0.78, green: 0.80, blue: 0.83)), lineWidth: 0.8)
        }

        // 顶面
        let top = ringPath(pts, 0)
        ctx.fill(top, with: .color(Color.orange.opacity(0.06)))
        ctx.stroke(top, with: .color(.orange), lineWidth: 2)

        // 特征：孔 / 沉台
        for f in p.feats {
            let r = f.dia / 2
            if f.kind == .hole {
                let topC = circlePath(f.x, f.y, 0, r)
                ctx.fill(topC, with: .color(Color(white: 0.28).opacity(0.55)))
                ctx.stroke(topC, with: .color(Color(white: 0.35)), lineWidth: 1.4)
                ctx.stroke(circlePath(f.x, f.y, -depth, r),
                           with: .color(Color(white: 0.45)), lineWidth: 0.9)
                for i in 0..<4 {
                    let a = Double(i) / 4.0 * 2 * Double.pi
                    let qx = f.x + r * cos(a), qy = f.y + r * sin(a)
                    ctx.stroke(Path { pp in
                        pp.move(to: P(qx, qy, 0))
                        pp.addLine(to: P(qx, qy, -depth))
                    }, with: .color(Color(white: 0.42)), lineWidth: 0.8)
                }
            } else {
                let d = min(f.depth, p.height)
                let topC = circlePath(f.x, f.y, 0, r)
                ctx.fill(topC, with: .color(Color(red: 1.0, green: 0.42, blue: 0.10).opacity(0.18)))
                ctx.stroke(topC, with: .color(Color(red: 0.95, green: 0.55, blue: 0.20)), lineWidth: 1.4)
                ctx.stroke(circlePath(f.x, f.y, -d, r),
                           with: .color(Color(red: 0.95, green: 0.55, blue: 0.20).opacity(0.75)), lineWidth: 1)
                for i in 0..<8 {
                    let a = Double(i) / 8.0 * 2 * Double.pi
                    let qx = f.x + r * cos(a), qy = f.y + r * sin(a)
                    ctx.stroke(Path { pp in
                        pp.move(to: P(qx, qy, 0))
                        pp.addLine(to: P(qx, qy, -d))
                    }, with: .color(Color(red: 0.90, green: 0.62, blue: 0.35)), lineWidth: 0.7)
                }
            }
        }
    }
}

// MARK: - 程序页

struct PartResultView: View {
    let code: String
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("\(code.components(separatedBy: "\n").count) 行")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = code
                        copied = true
                    } label: {
                        Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    NavigationLink {
                        SimScreen(code: code)
                    } label: {
                        Label("仿真", systemImage: "play.circle")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }

                Text(code)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(16)
        }
        .navigationTitle("多工序程序")
        .navigationBarTitleDisplayMode(.inline)
    }
}
