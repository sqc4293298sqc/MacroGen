import SwiftUI
import UIKit

/// 绘图编程：画一个任意闭合轮廓，直接出带刀补的宏程序
struct DrawScreen: View {
    @State private var spec = DrawSpec()
    @State private var format: ProgramFormat = .macro
    @State private var code = ""
    @State private var showResult = false
    @State private var showHelp = false
    @State private var solid = false          // 立体草图
    @State private var yaw = 0.78             // 水平旋转角
    @State private var pitch = 0.62           // 俯视角
    @State private var zoom = 1.0
    @State private var zoomBase = 1.0
    @State private var lastDrag: CGSize = .zero

    private var segs: [ContourSeg] {
        ContourGeo.segments(ContourGeo.buildNodes(spec))
    }

    private var issues: [String] { ContourProg.issues(spec) }

    var body: some View {
        Form {
            Section("轮廓") {
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
                    numRow("圆的直径 (mm)", $spec.circleD)
                case .slot:
                    numRow("槽总长 L（含两端圆弧）", $spec.slotL)
                    numRow("槽宽 W（= 两倍圆弧半径）", $spec.slotW)
                case .free:
                    EmptyView()
                }

                Text(ContourProg.summary(spec))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if spec.template == .free {
                Section("节点（最后一个点之后自动用直线连回起点）") {
                    ForEach(spec.nodes.indices, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("点 \(i + 1)")
                                    .font(.system(size: 13, weight: .semibold))
                                Spacer()
                                if spec.nodes.count > 1 {
                                    Button {
                                        spec.nodes.remove(at: i)
                                    } label: {
                                        Image(systemName: "minus.circle")
                                            .foregroundStyle(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            HStack(spacing: 10) {
                                Text("X").font(.system(size: 12)).foregroundStyle(.secondary)
                                TextField("0", value: Binding(
                                    get: { spec.nodes[i].x },
                                    set: { spec.nodes[i].x = $0 }
                                ), format: .number)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                                Text("Y").font(.system(size: 12)).foregroundStyle(.secondary)
                                TextField("0", value: Binding(
                                    get: { spec.nodes[i].y },
                                    set: { spec.nodes[i].y = $0 }
                                ), format: .number)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                            }
                            if i > 0 {
                                HStack(spacing: 10) {
                                    Picker("", selection: Binding(
                                        get: { spec.nodes[i].kind },
                                        set: { spec.nodes[i].kind = $0 }
                                    )) {
                                        ForEach(ContourKind.allCases) { k in
                                            Text(k.rawValue).tag(k)
                                        }
                                    }
                                    .labelsHidden()
                                    .pickerStyle(.menu)
                                    if spec.nodes[i].kind != .line {
                                        TextField("R", value: Binding(
                                            get: { spec.nodes[i].r },
                                            set: { spec.nodes[i].r = $0 }
                                        ), format: .number)
                                        .keyboardType(.decimalPad)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 70)
                                    }
                                }
                                .font(.system(size: 13))
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    HStack {
                        Button {
                            addPoint()
                        } label: {
                            Label("加一个点", systemImage: "plus.circle")
                        }
                        Spacer()
                        Button {
                            spec.template = .free
                            fillRectNodes()
                        } label: {
                            Text("按矩形填入")
                                .font(.system(size: 13))
                        }
                    }
                    .font(.system(size: 14))
                }
            }

            Section("画布 · 草图 / 立体") {
                HStack(spacing: 10) {
                    Spacer()
                    viewChip("草图 2D", on: !solid) { solid = false }
                    viewChip("立体 3D", on: solid) { solid = true }
                }
                .padding(.bottom, 2)

                Canvas { context, size in
                    if solid { drawSolid(context: context, size: size) }
                    else { drawPreview(context: context, size: size) }
                }
                .frame(height: solid ? 300 : 240)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .simultaneousGesture(DragGesture(minimumDistance: 2)
                    .onChanged { g in
                        guard solid else { return }
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
                        guard solid else { return }
                        zoom = min(3.0, max(0.4, zoomBase * Double(v)))
                    }
                    .onEnded { _ in zoomBase = zoom }
                )
                .onTapGesture(count: 2) {
                    if solid { yaw = 0.78; pitch = 0.62; zoom = 1; zoomBase = 1 }
                }

                Text(solid
                     ? "拖动转视角 · 双指缩放 · 双击复位（立体是草图按深度拉出来的，不是切削结果）"
                     : "橙线是轮廓，橙点是起刀点，虚线和淡橙圆是半圆进刀")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("刀具与切削") {
                numRow("刀具直径 (mm)", $spec.toolDia)
                numRow("加工深度 (mm)", $spec.depth)
                numRow("每层切深 (mm)", $spec.stepDown)
                numRow("切削进给 F", $spec.feed)
                numRow("转速 S", $spec.rpm)
                intRow("刀补号 H / D", Binding(
                    get: { spec.hNo },
                    set: { spec.hNo = $0 }
                ))
                numRow("安全高度 Z", $spec.safeZ)
                numRow("半圆进刀半径（0=自动）", $spec.leadR)
                Toggle("外形（刀在轮廓外）", isOn: $spec.outward)
                Text(spec.outward
                     ? "外形：程序用 G41 顺时针（或 G42 逆时针）绕外轮廓，刀偏在件外面"
                     : "内腔：程序把刀偏在腔里，沿腔壁绕一圈")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("程序格式") {
                Picker("程序格式", selection: $format) {
                    ForEach(ProgramFormat.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                Text(format.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !issues.isEmpty {
                Section("检查") {
                    ForEach(issues, id: \.self) { t in
                        Label(t, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section {
                Button {
                    build()
                } label: {
                    HStack {
                        Spacer()
                        Label(format == .macro ? "生成宏程序 · 含仿真" : "生成 G 代码 · 含仿真",
                              systemImage: format == .macro ? "scribble.variable" : "list.number")
                        Spacer()
                    }
                    .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)

                Button {
                    showHelp = true
                } label: {
                    HStack {
                        Spacer()
                        Label("画轮廓怎么用", systemImage: "questionmark.circle")
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("绘图编程")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showResult) {
            ContourResultView(code: code, format: format)
        }
        .sheet(isPresented: $showHelp) {
            ContourHelpView()
        }
        .onAppear {
            if spec.nodes.isEmpty { fillRectNodes() }
        }
    }

    // MARK: - 行

    private func numRow(_ title: String, _ value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 110)
        }
    }

    private func intRow(_ title: String, _ value: Binding<Int>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 110)
        }
    }

    // MARK: - 动作

    private func addPoint() {
        if let last = spec.nodes.last {
            spec.nodes.append(ContourNode(x: last.x + 20, y: last.y))
        } else {
            spec.nodes.append(ContourNode(x: 0, y: 0))
        }
    }

    private func fillRectNodes() {
        let l = max(spec.rectL, 1), w = max(spec.rectW, 1)
        spec.nodes = [
            ContourNode(x: 0, y: 0),
            ContourNode(x: l, y: 0),
            ContourNode(x: l, y: w),
            ContourNode(x: 0, y: w)
        ]
    }

    private func build() {
        let macro = ContourProg.generate(spec)
        code = PostProcessor.output(macro, format: format)
        showResult = true
    }

    // MARK: - 画布

    private func drawPreview(context: GraphicsContext, size: CGSize) {
        var ctx = context
        let pts = ContourGeo.flatten(segs, arcStep: 24)
        guard !pts.isEmpty else { return }

        var minX = pts[0].x, maxX = pts[0].x, minY = pts[0].y, maxY = pts[0].y
        for p in pts {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        let pad = 22.0
        let w = max(maxX - minX, 1), h = max(maxY - minY, 1)
        let k = min((size.width - pad * 2) / w, (size.height - pad * 2) / h)
        let ox = size.width / 2 - (minX + maxX) / 2 * k
        let oy = size.height / 2 + (minY + maxY) / 2 * k
        func sx(_ x: Double) -> Double { ox + x * k }
        func sy(_ y: Double) -> Double { oy - y * k }

        // 栅格
        ctx.stroke(Path { p in
            p.move(to: CGPoint(x: 0, y: sy(0)))
            p.addLine(to: CGPoint(x: size.width, y: sy(0)))
            p.move(to: CGPoint(x: sx(0), y: 0))
            p.addLine(to: CGPoint(x: sx(0), y: size.height))
        }, with: .color(Color(.systemGray5)), lineWidth: 1)

        // 轮廓
        ctx.stroke(Path { p in
            p.move(to: CGPoint(x: sx(pts[0].x), y: sy(pts[0].y)))
            for q in pts.dropFirst() {
                p.addLine(to: CGPoint(x: sx(q.x), y: sy(q.y)))
            }
            p.addLine(to: CGPoint(x: sx(pts[0].x), y: sy(pts[0].y)))
        }, with: .color(.orange), lineWidth: 2)

        // 起点 + 半圆进刀示意
        if let first = segs.first {
            let p0 = first.p0
            let t0 = ContourGeo.tangent(first)
            let ccw = ContourGeo.signedArea(pts) > 0
            let useLeft = spec.outward ? !ccw : ccw
            let n = useLeft ? CGPoint(x: -t0.y, y: t0.x) : CGPoint(x: t0.y, y: -t0.x)
            let lead = ContourProg.leadRadius(spec)
            let ap = CGPoint(x: p0.x + n.x * lead * 2, y: p0.y + n.y * lead * 2)
            let cp = CGPoint(x: p0.x + n.x * lead, y: p0.y + n.y * lead)

            ctx.stroke(Path { p in
                p.addEllipse(in: CGRect(x: sx(cp.x) - lead * k, y: sy(cp.y) - lead * k,
                                        width: lead * 2 * k, height: lead * 2 * k))
            }, with: .color(Color.orange.opacity(0.35)), lineWidth: 1)

            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: sx(p0.x), y: sy(p0.y)))
                p.addLine(to: CGPoint(x: sx(ap.x), y: sy(ap.y)))
            }, with: .color(Color(.systemGray3)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

            ctx.fill(Path(ellipseIn: CGRect(x: sx(ap.x) - 4, y: sy(ap.y) - 4, width: 8, height: 8)),
                     with: .color(Color(.systemGray2)))
            ctx.fill(Path(ellipseIn: CGRect(x: sx(p0.x) - 4, y: sy(p0.y) - 4, width: 8, height: 8)),
                     with: .color(.orange))
        }
    }

    private func viewChip(_ text: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(on ? Color.white : Color(red: 0.45, green: 0.49, blue: 0.55))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(on ? Color(red: 1.0, green: 0.42, blue: 0.10) : Color(.systemGray6))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 立体草图

    /// 把草图轮廓按「加工深度」拉成一块立体，画出顶面、每层轮廓、竖边和进刀圆
    private func drawSolid(context: GraphicsContext, size: CGSize) {
        var ctx = context
        let pts = ContourGeo.flatten(segs, arcStep: 26)
        guard pts.count > 2 else { return }

        let depth = max(spec.depth, 0.1)
        let step = max(spec.stepDown, 0.1)
        let layers = max(1, Int(ceil(depth / step)))

        var minX = pts[0].x, maxX = pts[0].x, minY = pts[0].y, maxY = pts[0].y
        for p in pts {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }

        let cy = cos(yaw), sy = sin(yaw)
        let sp = sin(pitch), cp = cos(pitch)

        func raw(_ x: Double, _ y: Double, _ z: Double) -> (Double, Double) {
            let rx = x * cy - y * sy
            let ry = x * sy + y * cy
            return (rx, -(ry * sp + z * cp))
        }

        var pminX = Double.infinity, pmaxX = -Double.infinity
        var pminY = Double.infinity, pmaxY = -Double.infinity
        for zz in [0.0, -depth] {
            for (xx, yy) in [(minX, minY), (maxX, minY), (maxX, maxY), (minX, maxY)] {
                let r = raw(xx, yy, zz)
                pminX = min(pminX, r.0); pmaxX = max(pmaxX, r.0)
                pminY = min(pminY, r.1); pmaxY = max(pmaxY, r.1)
            }
        }
        let pad = 26.0
        let w = max(pmaxX - pminX, 1), h = max(pmaxY - pminY, 1)
        let k = min((size.width - pad * 2) / w, (size.height - pad * 2) / h) * zoom
        let ox = size.width / 2, oy = size.height / 2
        let mx = (pminX + pmaxX) / 2, my = (pminY + pmaxY) / 2

        func P(_ x: Double, _ y: Double, _ z: Double) -> CGPoint {
            let r = raw(x, y, z)
            return CGPoint(x: ox + (r.0 - mx) * k, y: oy + (r.1 - my) * k)
        }

        func ringPath(_ z: Double) -> Path {
            var path = Path()
            guard let f = pts.first else { return path }
            path.move(to: P(f.x, f.y, z))
            for q in pts.dropFirst() {
                path.addLine(to: P(q.x, q.y, z))
            }
            return path
        }

        // 底面（最深处）
        let bottom = ringPath(-depth)
        ctx.fill(bottom, with: .color(Color.orange.opacity(0.10)))
        ctx.stroke(bottom, with: .color(Color(red: 0.70, green: 0.72, blue: 0.76)), lineWidth: 1)

        // 每层轮廓（浅橙，表示分层切深）
        if layers > 1 {
            for i in 1..<layers {
                let z = -min(depth, Double(i) * step)
                ctx.stroke(ringPath(z), with: .color(Color.orange.opacity(0.25)), lineWidth: 0.7)
            }
        }

        // 竖边（每 2 个点取一个，最多 30 条，避免太乱）
        let strideStep = max(1, pts.count / 30)
        for i in Swift.stride(from: 0, to: pts.count, by: strideStep) {
            let q = pts[i]
            ctx.stroke(Path { p in
                p.move(to: P(q.x, q.y, 0))
                p.addLine(to: P(q.x, q.y, -depth))
            }, with: .color(Color(red: 0.78, green: 0.80, blue: 0.83)), lineWidth: 0.8)
        }

        // 顶面（草图轮廓）
        let top = ringPath(0)
        ctx.fill(top, with: .color(Color.orange.opacity(0.06)))
        ctx.stroke(top, with: .color(.orange), lineWidth: 2)

        // 进刀点与半圆进刀（同样投影到 3D 顶面上）
        if let first = segs.first {
            let p0 = first.p0
            let t0 = ContourGeo.tangent(first)
            let ccw = ContourGeo.signedArea(pts) > 0
            let useLeft = spec.outward ? !ccw : ccw
            let n = useLeft ? CGPoint(x: -t0.y, y: t0.x) : CGPoint(x: t0.y, y: -t0.x)
            let lead = ContourProg.leadRadius(spec)
            let ap = CGPoint(x: p0.x + n.x * lead * 2, y: p0.y + n.y * lead * 2)
            let cp = CGPoint(x: p0.x + n.x * lead, y: p0.y + n.y * lead)

            var circle = Path()
            for i in 0...24 {
                let a = Double(i) / 24.0 * 2 * Double.pi
                let q = CGPoint(x: cp.x + lead * cos(a), y: cp.y + lead * sin(a))
                let sp2 = P(q.x, q.y, 0)
                if i == 0 { circle.move(to: sp2) } else { circle.addLine(to: sp2) }
            }
            ctx.stroke(circle, with: .color(Color.orange.opacity(0.35)), lineWidth: 1)

            ctx.stroke(Path { p in
                p.move(to: P(p0.x, p0.y, 0))
                p.addLine(to: P(ap.x, ap.y, 0))
            }, with: .color(Color(red: 0.62, green: 0.65, blue: 0.70)),
               style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

            let apP = P(ap.x, ap.y, 0)
            ctx.fill(Path(ellipseIn: CGRect(x: apP.x - 4, y: apP.y - 4, width: 8, height: 8)),
                     with: .color(Color(red: 0.72, green: 0.74, blue: 0.78)))
            let p0P = P(p0.x, p0.y, 0)
            ctx.fill(Path(ellipseIn: CGRect(x: p0P.x - 4.5, y: p0P.y - 4.5, width: 9, height: 9)),
                     with: .color(.orange))
        }
    }
}

// MARK: - 结果页

struct ContourResultView: View {
    let code: String
    var format: ProgramFormat = .macro
    @State private var copied = false

    var body: some View {
        VStack(spacing: 10) {
            ScrollView {
                Text(code)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 8) {
                Button {
                    UIPasteboard.general.string = code
                    copied = true
                } label: {
                    Label(copied ? "已复制" : "复制程序", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                NavigationLink {
                    SimScreen(code: code)
                } label: {
                    Label("程序模拟", systemImage: "play.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            .font(.system(size: 15, weight: .semibold))
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .navigationTitle(format == .macro ? "绘图编程 · 宏程序" : "绘图编程 · G 代码")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 帮助

struct ContourHelpView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    helpBlock("能干什么",
                              "画一个闭合轮廓（矩形、圆、腰形槽，或者自己点坐标排一条线），直接生成带 G41/G42 刀补、分层、半圆弧进出的 FANUC 宏程序，并且能在这里仿真。")
                    helpBlock("三种模板",
                              "矩形：填长、宽，四角要圆角就填 R（0 就是直角）。\n圆：填直径，整圆一刀绕下来。\n腰形槽：填总长和宽，两端自动是半圆。")
                    helpBlock("自定义",
                              "按顺序填节点坐标，每一段可以是直线，也可以是顺时针/逆时针圆弧（要填 R）。最后一个节点之后，程序会自动用直线连回第一个点，所以轮廓一定是闭合的。\n起点就是第一个节点，半圆进刀从那里生成，尽量把起点放在直线段上，别放在角上。")
                    helpBlock("外形 / 内腔",
                              "外形：刀偏在轮廓外面（件比轮廓大）。\n内腔：刀偏在轮廓里面（轮廓就是腔壁）。\n刀补方向由程序自己按走向判断，你只需选对内外。")
                    helpBlock("分层",
                              "总深除以每层得到层数并自动补齐最后一刀；每层在起刀点原位下 Z，再半圆切入绕一圈，切完半圆切出，全程不抬 Z。")
                    helpBlock("注意",
                              "程序里用的是 G41/G42，机床必须对好刀补号（H/D）和刀补值，否则偏出来的量不对。\n仿真画的是轮廓线（未叠加刀补半径），上机前先空运行、单段、抬高 Z 试第一件。")
                }
                .padding(16)
            }
            .navigationTitle("绘图编程 · 使用说明")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func helpBlock(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
