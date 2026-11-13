import SwiftUI

/// 按 G 代码真执行出来的模拟界面：播放 / 单步 / 倍速 / DRO / 当前行高亮
struct SimScreen: View {
    let code: String
    var spec: PocketSpec? = nil

    @State private var path: SimPath = SimPath()
    @State private var progress: Double = 0
    @State private var playing = false
    @State private var speed: Double = 1
    @State private var iso = true
    @State private var timer: Timer? = nil

    private var curIndex: Int { indexAt(progress) }

    var body: some View {
        VStack(spacing: 8) {
            SimCanvas(path: path, progress: progress, iso: iso)

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

            CodeList(lines: lineArray, current: curIndex >= 0 ? (path.pts[safe: curIndex]?.line ?? -1) : -1)
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .navigationTitle("程序模拟")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            path = MacroInterp.run(code)
            progress = 0
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

    private var lineArray: [String] {
        code.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
    }

    private var lineText: String {
        let idx = curPoint.line
        guard idx >= 0, idx < lineArray.count else { return "点播放开始，或拖进度条逐段看" }
        return "行 \(idx + 1) › " + lineArray[idx].trimmingCharacters(in: .whitespaces)
    }

    private var speedText: String {
        speed == 0.5 ? "0.5×" : "\(Int(speed))×"
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
        timer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { t in
            let stepMm = path.maxLen / 15.0 * 0.04 * speed
            progress += (stepMm < 1 ? 1 : stepMm)
            if progress >= path.maxLen {
                progress = path.maxLen
                t.invalidate()
                playing = false
            }
        }
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

/// 代码列表：当前执行行高亮，自动滚到中间
private struct CodeList: View {
    let lines: [String]
    let current: Int

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                        Text(line)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(idx == current ? Color.white : Color(white: 0.82))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(idx == current ? Color.orange.opacity(0.75) : Color.clear)
                            .id(idx)
                    }
                }
                .padding(.vertical, 6)
            }
            .background(Color(red: 0.07, green: 0.10, blue: 0.14))
            .onChange(of: current) { newValue in
                withAnimation(.easeInOut(duration: 0.15)) {
                    proxy.scrollTo(max(0, newValue - 3), anchor: .top)
                }
            }
        }
    }
}

/// 刀路画布：俯视 / 等轴测；已走段按深度上色，未走段淡灰
struct SimCanvas: View {
    let path: SimPath
    let progress: Double
    let iso: Bool

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
        Canvas { ctx, size in
            ctx.translateBy(x: size.width / 2 + pan.x, y: size.height / 2 + pan.y)
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

            for k in 1..<path.pts.count {
                let a = path.pts[k - 1], b = path.pts[k]
                if path.dist[safe: k] ?? 0 > progress { continue }
                let p0 = project(a.x, a.y, a.z)
                let p1 = project(b.x, b.y, b.z)
                var line = Path()
                line.move(to: p0)
                line.addLine(to: p1)
                let col: Color
                if b.rapid {
                    col = Color(white: 0.62)
                } else {
                    let t = min(1, max(0, -b.z / depth))
                    col = Color(red: 1.0 - 0.12 * t, green: 0.64 - 0.38 * t, blue: 0.37 - 0.25 * t)
                }
                ctx.stroke(line, with: .color(col), lineWidth: b.rapid ? 0.8 : 1.4)
            }

            // 未走段淡灰轮廓
            for k in 1..<path.pts.count {
                if (path.dist[safe: k] ?? 0) <= progress { continue }
                let a = path.pts[k - 1], b = path.pts[k]
                var line = Path()
                line.move(to: project(a.x, a.y, a.z))
                line.addLine(to: project(b.x, b.y, b.z))
                ctx.stroke(line, with: .color(Color(white: 0.86)), lineWidth: 0.7)
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
