import SwiftUI

/// 按 G 代码真执行出来的模拟界面：播放 / 单步 / 倍速 / DRO / 当前行高亮
/// 2.5D 高度图：每个网格记录“被切到的最低 Z”和“第一次切到它的路径长度”。
/// 它不是实体布尔，但能把残料/已切区域按层显示出来。
struct SimHeightmap {
    var minX: Double
    var minY: Double
    var maxX: Double
    var maxY: Double
    var cols: Int
    var rows: Int
    var cellX: Double
    var cellY: Double
    var stockTop: Double
    var topZ: [Double]
    var cutLen: [Double]

    init(path: SimPath, toolDia: Double, stockTop: Double) {
        let pad = max(toolDia, 1) * 0.55
        let loX = path.pts.isEmpty ? 0 : path.minX - pad
        let hiX = path.pts.isEmpty ? 1 : path.maxX + pad
        let loY = path.pts.isEmpty ? 0 : path.minY - pad
        let hiY = path.pts.isEmpty ? 1 : path.maxY + pad
        minX = loX; maxX = max(hiX, loX + 1)
        minY = loY; maxY = max(hiY, loY + 1)
        cols = 64
        rows = max(12, Int(Double(cols) * (maxY - minY) / max(maxX - minX, 1)))
        cellX = (maxX - minX) / Double(cols)
        cellY = (maxY - minY) / Double(rows)
        self.stockTop = stockTop
        topZ = Array(repeating: stockTop, count: cols * rows)
        cutLen = Array(repeating: Double.infinity, count: cols * rows)
        guard !path.pts.isEmpty else { return }
        let r = max(toolDia, 0.1) / 2
        for k in 1..<path.pts.count {
            let b = path.pts[k]
            guard !b.rapid else { continue }
            let ix0 = max(0, Int(floor((b.x - r - minX) / cellX)))
            let ix1 = min(cols - 1, Int(ceil((b.x + r - minX) / cellX)))
            let iy0 = max(0, Int(floor((b.y - r - minY) / cellY)))
            let iy1 = min(rows - 1, Int(ceil((b.y + r - minY) / cellY)))
            guard ix0 <= ix1, iy0 <= iy1 else { continue }
            let d = k < path.dist.count ? path.dist[k] : 0
            for iy in iy0...iy1 {
                let cy = minY + (Double(iy) + 0.5) * cellY
                for ix in ix0...ix1 {
                    let cx = minX + (Double(ix) + 0.5) * cellX
                    guard hypot(cx - b.x, cy - b.y) <= r + max(cellX, cellY) * 0.5 else { continue }
                    let i = iy * cols + ix
                    topZ[i] = min(topZ[i], b.z)
                    cutLen[i] = min(cutLen[i], d)
                }
            }
        }
    }

    /// 到当前进度、当前层已经切掉的网格
    func removedCells(progress: Double, layerZ: Double) -> [CGRect] {
        var out: [CGRect] = []
        out.reserveCapacity(cols * rows / 4)
        for iy in 0..<rows {
            for ix in 0..<cols {
                let i = iy * cols + ix
                guard cutLen[i].isFinite, cutLen[i] <= progress,
                      topZ[i] <= layerZ + 0.01 else { continue }
                out.append(CGRect(x: CGFloat(minX + Double(ix) * cellX),
                                  y: CGFloat(minY + Double(iy) * cellY),
                                  width: CGFloat(cellX), height: CGFloat(cellY)))
            }
        }
        return out
    }
}

struct SimScreen: View {
    let code: String
    var spec: PocketSpec? = nil

    @State private var path: SimPath = SimPath()
    @State private var progress: Double = 0
    @State private var playing = false
    @State private var speed: Double = 1
    @State private var iso = true
    @State private var layerZ: Double = 0
    @State private var layered = false
    @State private var heightmap: SimHeightmap? = nil
    @State private var lines: [String] = []
    @State private var timer: Timer? = nil

    private var curIndex: Int { indexAt(progress) }

    var body: some View {
        VStack(spacing: 8) {
            SimCanvas(path: path, progress: progress, iso: iso,
                      toolDia: spec?.toolDia ?? 6,
                      layerZ: (!iso && layered) ? layerZ : nil,
                      heightmap: (!iso && layered) ? heightmap : nil)

            HStack(spacing: 0) {
                dro("X", value: curPoint.x)
                dro("Y", value: curPoint.y)
                dro("Z", value: curPoint.z)
            }
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(subTitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Slider(value: $progress, in: 0...max(1, path.maxLen), onEditingChanged: { _ in
                stop()
            })

            if !iso {
                HStack(spacing: 6) {
                    Toggle("分层", isOn: $layered)
                        .font(.system(size: 11))
                        .fixedSize()
                    Text("看层 Z \(ncf(layerZ))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                    Slider(value: $layerZ, in: layerRange)
                }
                .padding(.horizontal, 2)
            }

            HStack(spacing: 6) {
                btn(playing ? "暂停" : "播放", accent: true) { playing ? stop() : play() }
                btn("单步") { step() }
                btn(speedText) { cycleSpeed() }
                btn("复位") { stop(); progress = 0 }
                btn(iso ? "俯视" : "立体") { iso.toggle() }
            }

            Text(lineText)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            CodeList(lines: lines, current: curIndex >= 0 ? (path.pts[safe: curIndex]?.line ?? -1) : -1)
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .navigationTitle("程序模拟")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            path = MacroInterp.run(code)
            lines = code.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
            progress = 0
            layerZ = 0
            let stockTop = spec?.zTop ?? 0
            heightmap = SimHeightmap(path: path, toolDia: spec?.toolDia ?? 6, stockTop: stockTop)
        }
        .onDisappear { stop() }
    }

    // MARK: - 数据

    private var curPoint: SimPoint {
        guard !path.pts.isEmpty else { return SimPoint(x: 0, y: 0, z: 0, rapid: true, line: 0) }
        return path.pts[safe: min(curIndex, path.pts.count - 1)] ?? path.pts[0]
    }

    private var subTitle: String {
        if let err = path.error { return "⚠ " + err }
        return "\(path.pts.count) 个轨迹点 · 切削 \(Int(path.totalCut)) mm"
    }

    private var lineText: String {
        let idx = curPoint.line
        guard idx >= 0, idx < lines.count else { return "点播放开始，或拖进度条逐段看" }
        return "行 \(idx + 1) › " + lines[idx].trimmingCharacters(in: .whitespaces)
    }

    private var speedText: String {
        speed == 0.5 ? "0.5×" : "\(Int(speed))×"
    }

    private var layerRange: ClosedRange<Double> {
        let lo = min(path.minZ, 0)
        let hi = max(0, min(path.maxZ, 0))
        return lo...max(lo + 0.1, hi)
    }

    private func indexAt(_ d: Double) -> Int {
        guard !path.dist.isEmpty else { return 0 }
        var lo = 0, hi = path.dist.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if path.dist[mid] < d { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    // MARK: - 播放

    private func play() {
        guard path.maxLen > 0 else { return }
        if progress >= path.maxLen { progress = 0 }
        playing = true
        timer?.invalidate()
        let dt = 1.0 / 30.0
        let t = Timer(timeInterval: dt, repeats: true) { timer in
            let stepMm = path.maxLen / 15.0 * dt * speed
            progress += (stepMm < 0.5 ? 0.5 : stepMm)
            if progress >= path.maxLen {
                progress = path.maxLen
                timer.invalidate()
                playing = false
            }
        }
        t.tolerance = 0.01
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        playing = false
    }

    private func step() {
        stop()
        guard !path.pts.isEmpty else { return }
        let next = min(curIndex + 1, path.pts.count - 1)
        progress = path.dist[safe: next] ?? progress
    }

    private func cycleSpeed() {
        switch speed {
        case 1: speed = 2
        case 2: speed = 4
        case 4: speed = 0.5
        default: speed = 1
        }
        if playing { stop(); play() }
    }

    // MARK: - 小组件

    private func dro(_ name: String, value: Double) -> some View {
        VStack(spacing: 2) {
            Text(name).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(String(format: "%.3f", value))
                .font(.system(size: 14, design: .monospaced))
        }
        .frame(maxWidth: .infinity)
    }

    private func btn(_ t: String, accent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(accent ? Color.orange : Color(.tertiarySystemFill))
                .foregroundStyle(accent ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }
}

/// 代码列表：只渲染当前行附近的窗口，避免每帧把整段程序都重新排版
private struct CodeList: View {
    let lines: [String]
    let current: Int

    private var window: [Int] {
        guard !lines.isEmpty else { return [] }
        let center = current >= 0 ? current : 0
        let lo = max(0, center - 10)
        let hi = min(lines.count - 1, center + 10)
        return Array(lo...hi)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(window, id: \.self) { idx in
                    Text(lines[idx])
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(idx == current ? Color.white : Color(white: 0.82))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(idx == current ? Color.orange.opacity(0.75) : Color.clear)
                }
            }
            .padding(.vertical, 6)
        }
        .background(Color(red: 0.07, green: 0.10, blue: 0.14))
    }
}

/// 刀路画布：俯视 / 等轴测；已走段按深度上色，未走段淡灰
struct SimCanvas: View {
    let path: SimPath
    let progress: Double
    let iso: Bool
    var toolDia: Double = 6
    /// 非 nil 时只显示“切到该 Z 层及更深”的材料去除；nil = 全部刀路
    var layerZ: Double? = nil
    /// 高度图余料；给出后俯视图按网格显示已切区域
    var heightmap: SimHeightmap? = nil

    // 双指缩放 + 拖动平移
    @State private var zoom: CGFloat = 1
    @State private var baseZoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var basePan: CGSize = .zero

    private var zoomPan: some Gesture {
        SimultaneousGesture(
            MagnificationGesture()
                .onChanged { v in zoom = min(8, max(0.4, baseZoom * v)) }
                .onEnded { _ in baseZoom = zoom },
            DragGesture()
                .onChanged { v in
                    pan = CGSize(width: basePan.width + v.translation.width,
                                 height: basePan.height + v.translation.height)
                }
                .onEnded { _ in basePan = pan }
        )
    }

    var body: some View {
        Canvas { context, size in
            var ctx = context
            ctx.translateBy(x: size.width / 2 + pan.width, y: size.height / 2 + pan.height)
            ctx.scaleBy(x: zoom, y: zoom)
            ctx.translateBy(x: -size.width / 2, y: -size.height / 2)

            let spanX = max(path.maxX - path.minX, 1)
            let spanY = max(path.maxY - path.minY, 1)
            let zSpan = max(path.maxZ - path.minZ, 0.001)
            let zf = 0.8                    // 立体图里 Z 的视觉比例
            let needW = iso ? (spanX + spanY) * 0.95 : spanX
            let needH = iso ? (spanX + spanY) * 0.5 + zSpan * zf : spanY
            let s = min(size.width * 0.92 / needW, size.height * 0.90 / needH)
            let cx = (path.minX + path.maxX) / 2
            let cy = (path.minY + path.maxY) / 2
            let zMid = (path.minZ + path.maxZ) / 2
            let ox = size.width / 2
            let oy = size.height / 2 + (iso ? zMid * zf * s : 0)

            func project(_ x: Double, _ y: Double, _ z: Double) -> CGPoint {
                if iso {
                    let px = (x - cx) - (y - cy)
                    let py = ((x - cx) + (y - cy)) * 0.5 - z * zf
                    return CGPoint(x: ox + px * 0.866 * s, y: oy + py * s)
                }
                return CGPoint(x: ox + (x - cx) * s, y: oy - (y - cy) * s)
            }

            guard path.pts.count > 1 else { return }
            let depth = max(1, -path.minZ)

            // 2.5D 材料去除：俯视图把已走过的切削点按刀径擦掉毛坯，
            // 不是实体布尔仿真，但能直观看到哪些区域已经被掏空。
            if !iso, toolDia > 0.2 {
                let pad = CGFloat(toolDia) * 0.9
                let sx = Double(s)
                let stockRect = CGRect(x: CGFloat(path.minX * sx) + ox - pad,
                                       y: CGFloat(-path.maxY * sx) + oy - pad,
                                       width: CGFloat((path.maxX - path.minX) * sx) + pad * 2,
                                       height: CGFloat((path.maxY - path.minY) * sx) + pad * 2)
                let stockPath = Path { pth in pth.addRect(stockRect) }
                ctx.fill(stockPath, with: .color(Color(white: 0.86)))
                ctx.stroke(stockPath, with: .color(Color(white: 0.58)), lineWidth: 1)
                if let hm = heightmap, let lz = layerZ {
                    var cut = Path()
                    for cell in hm.removedCells(progress: progress, layerZ: lz) {
                        let a = project(cell.minX, cell.maxY, 0)
                        let b = project(cell.maxX, cell.minY, 0)
                        cut.addRect(CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                                           width: abs(b.x - a.x), height: abs(b.y - a.y)))
                    }
                    ctx.fill(cut, with: .color(Color(white: 0.965)))
                    ctx.stroke(cut, with: .color(Color(white: 0.86)), lineWidth: 0.35)
                    let layerNote = " · Z\(ncf(lz))"
                    ctx.draw(Text("高度图余料\(layerNote)")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.secondary),
                             at: CGPoint(x: min(stockRect.minX + 58, stockRect.maxX - 58), y: stockRect.minY + 10))
                } else {
                    let r = CGFloat(toolDia / 2) * s
                    for k in 1..<path.pts.count {
                        let b = path.pts[k]
                        let walkedYet = (path.dist[safe: k] ?? 0) <= progress
                        guard walkedYet, !b.rapid else { continue }
                        if let lz = layerZ, b.z > lz + 0.01 { continue }
                        let q = project(b.x, b.y, b.z)
                        if r <= 1 {
                            ctx.fill(Path(ellipseIn: CGRect(x: q.x - 1, y: q.y - 1, width: 2, height: 2)),
                                     with: .color(Color(white: 0.97)))
                        } else {
                            ctx.fill(Path(ellipseIn: CGRect(x: q.x - r, y: q.y - r, width: r * 2, height: r * 2)),
                                     with: .color(Color(white: 0.97)))
                        }
                    }
                    let layerNote = layerZ.map { " · Z\(ncf($0))" } ?? ""
                    ctx.draw(Text("材料去除（2.5D 分层近似\(layerNote)）")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.secondary),
                             at: CGPoint(x: min(stockRect.minX + 76, stockRect.maxX - 76), y: stockRect.minY + 10))
                }
            }

            // 性能：分段合批 + 按屏幕距离抽稀，几千个点也只发十几次 stroke
            let bands = 6
            var walked: [Path] = Array(repeating: Path(), count: bands)
            var lastW: [CGPoint?] = Array(repeating: nil, count: bands)
            var rapidPath = Path(); var lastRapid: CGPoint? = nil
            var pending = Path(); var lastPending: CGPoint? = nil

            for k in 1..<path.pts.count {
                let a = path.pts[k - 1], b = path.pts[k]
                let p0 = project(a.x, a.y, a.z)
                let p1 = project(b.x, b.y, b.z)
                let walkedYet = (path.dist[safe: k] ?? 0) <= progress
                if walkedYet {
                    if b.rapid {
                        if let lp = lastRapid {
                            if abs(p1.x - lp.x) + abs(p1.y - lp.y) >= 1.0 { rapidPath.addLine(to: p1); lastRapid = p1 }
                        } else { rapidPath.move(to: p0); rapidPath.addLine(to: p1); lastRapid = p1 }
                    } else {
                        let t = min(1, max(0, -b.z / depth))
                        let bi = min(bands - 1, max(0, Int(t * Double(bands))))
                        if let lp = lastW[bi] {
                            if abs(p1.x - lp.x) + abs(p1.y - lp.y) >= 1.0 { walked[bi].addLine(to: p1); lastW[bi] = p1 }
                        } else { walked[bi].move(to: p0); walked[bi].addLine(to: p1); lastW[bi] = p1 }
                    }
                } else {
                    if let lp = lastPending {
                        if abs(p1.x - lp.x) + abs(p1.y - lp.y) >= 1.2 { pending.addLine(to: p1); lastPending = p1 }
                    } else { pending.move(to: p0); pending.addLine(to: p1); lastPending = p1 }
                }
            }

            // 未走段淡灰轮廓
            if !pending.isEmpty {
                ctx.stroke(pending, with: .color(Color(white: 0.86)), lineWidth: 0.7)
            }
            if !rapidPath.isEmpty {
                ctx.stroke(rapidPath, with: .color(Color(white: 0.62)), lineWidth: 0.8)
            }
            for i in 0..<bands where !walked[i].isEmpty {
                let t = (Double(i) + 0.5) / Double(bands)
                let col = Color(red: 1.0 - 0.12 * t, green: 0.64 - 0.38 * t, blue: 0.37 - 0.25 * t)
                ctx.stroke(walked[i], with: .color(col), lineWidth: 1.4)
            }

            // 刀尖
            let idx = min(path.pts.count - 1, max(0, indexAt(progress)))
            let tip = path.pts[idx]
            let pt = project(tip.x, tip.y, tip.z)
            let dot = Path(ellipseIn: CGRect(x: pt.x - 3.5, y: pt.y - 3.5, width: 7, height: 7))
            ctx.fill(dot, with: .color(.orange))
            var vline = Path()
            vline.move(to: CGPoint(x: pt.x, y: pt.y - 26))
            vline.addLine(to: pt)
            ctx.stroke(vline, with: .color(.orange.opacity(0.65)), lineWidth: 1)
        }
        .background(Color(white: 0.97))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .gesture(zoomPan)
        .onTapGesture(count: 2) {
            zoom = 1; baseZoom = 1; pan = .zero; basePan = .zero
        }
        .overlay(alignment: .bottomTrailing) {
            Text("双指缩放 · 双击复位")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.white.opacity(0.8))
                .clipShape(Capsule())
                .padding(8)
        }
    }

    private func indexAt(_ d: Double) -> Int {
        guard !path.dist.isEmpty else { return 0 }
        var lo = 0, hi = path.dist.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if path.dist[mid] < d { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }
}

extension Array {
    subscript(safe i: Int) -> Element? {
        i >= 0 && i < count ? self[i] : nil
    }
}
