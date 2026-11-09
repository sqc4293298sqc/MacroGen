import SwiftUI

/// 刀路仿真：俯视 / 等轴测立体，可倍速播放
struct ToolpathSimView: View {
    let spec: PocketSpec

    @Environment(\.dismiss) private var dismiss
    @State private var progress: Double = 0
    @State private var playing = true
    @State private var iso = false
    @State private var speedIndex = 0

    private let speeds: [Double] = [1, 2, 4, 0.5]
    private let speedNames = ["1×", "2×", "4×", "0.5×"]

    private var segs: [TPSeg] { ToolpathEngine.build(spec) }
    private var outlinePts: [CGPoint] { ToolpathEngine.outline(spec) }
    private var total: Double { max(1, ToolpathEngine.totalLen(segs)) }
    private var maxDepth: Double { max(0.001, segs.map { -$0.z }.max() ?? 1) }

    private var currentZ: Double {
        var acc = 0.0
        for s in segs {
            if acc + s.len >= progress * total { return s.z }
            acc += s.len
        }
        return segs.last?.z ?? 0
    }

    /// 是否嵌在别的页面里（嵌进去就不带自己的导航栏和关闭按钮）
    var embedded = false
    /// 画布高度，嵌进宏程序页时可以矮一点
    var canvasHeight: CGFloat = 360

    var body: some View {
        if embedded {
            panel
        } else {
            NavigationStack {
                panel
                    .navigationTitle("刀路仿真")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭") { dismiss() }
                        }
                    }
            }
        }
    }

    private var panel: some View {
        VStack(spacing: 10) {
                Canvas { ctx, size in draw(ctx, size) }
                    .frame(height: canvasHeight)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(red: 0.91, green: 0.93, blue: 0.95)))

                HStack(spacing: 10) {
                    Button {
                        iso.toggle()
                    } label: {
                        Label(iso ? "看俯视" : "看立体", systemImage: iso ? "square" : "cube")
                            .frame(maxWidth: .infinity)
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        speedIndex = (speedIndex + 1) % speeds.count
                    } label: {
                        Label("速度 \(speedNames[speedIndex])", systemImage: "speedometer")
                            .frame(maxWidth: .infinity)
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                }

                Text(String(format: "进度 %d%%    当前 Z = %.2f", Int(progress * 100), currentZ))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Slider(value: $progress, in: 0...1) { editing in
                    if editing { playing = false }
                }

                HStack(spacing: 12) {
                    Button {
                        if progress >= 1 { progress = 0 }
                        playing.toggle()
                    } label: {
                        Label(playing ? "暂停" : "播放", systemImage: playing ? "pause.fill" : "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 1, green: 0.42, blue: 0.10))

                    Button {
                        progress = 0
                        playing = true
                    } label: {
                        Label("重播", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
        }
        .padding(14)
        .onReceive(Timer.publish(every: 0.04, on: .main, in: .common).autoconnect()) { _ in
            guard playing else { return }
            progress = min(1, progress + 0.006 * speeds[speedIndex])
            if progress >= 1 { playing = false }
        }
    }

    // MARK: - 绘制

    private func project(_ x: Double, _ y: Double, _ z: Double) -> CGPoint {
        if iso {
            return CGPoint(x: (x - y) * 0.866, y: (x + y) * 0.5 + z * 2.0)
        }
        return CGPoint(x: x, y: y)
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        let toolR = spec.toolDia / 2
        var pts: [CGPoint] = []
        for s in segs {
            for p in s.pts { pts.append(project(Double(p.x), Double(p.y), s.z)) }
        }
        if !outlinePts.isEmpty {
            for z in [0.0, -maxDepth] {
                for p in outlinePts { pts.append(project(Double(p.x), Double(p.y), z)) }
            }
        }
        guard !pts.isEmpty else { return }

        let minX = pts.map { $0.x }.min()! - toolR
        let maxX = pts.map { $0.x }.max()! + toolR
        let minY = pts.map { $0.y }.min()! - toolR
        let maxY = pts.map { $0.y }.max()! + toolR

        let spanX = max(0.001, maxX - minX), spanY = max(0.001, maxY - minY)
        let pad = 16.0
        let scale = min((size.width - pad * 2) / spanX, (size.height - pad * 2) / spanY)
        let ox = (size.width - spanX * scale) / 2 - minX * scale
        let oy = (size.height - spanY * scale) / 2 + maxY * scale

        func screen(_ p: CGPoint) -> CGPoint {
            CGPoint(x: ox + p.x * scale, y: oy - p.y * scale)
        }

        // 网格
        let step = niceStep(spanX / 6)
        var gx = floor(minX / step) * step
        while gx <= maxX {
            let x = ox + gx * scale
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: x, y: 0))
                p.addLine(to: CGPoint(x: x, y: size.height))
            }, with: .color(Color(red: 0.93, green: 0.94, blue: 0.96)), lineWidth: 1)
            gx += step
        }
        var gy = floor(minY / step) * step
        while gy <= maxY {
            let y = oy - gy * scale
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: size.width, y: y))
            }, with: .color(Color(red: 0.93, green: 0.94, blue: 0.96)), lineWidth: 1)
            gy += step
        }

        // 工件轮廓（顶面 + 底面）
        func strokeOutline(_ z: Double, _ color: Color) {
            guard outlinePts.count > 1 else { return }
            ctx.stroke(Path { p in
                p.move(to: screen(project(Double(outlinePts[0].x), Double(outlinePts[0].y), z)))
                for q in outlinePts.dropFirst() {
                    p.addLine(to: screen(project(Double(q.x), Double(q.y), z)))
                }
            }, with: .color(color), lineWidth: 1)
        }
        strokeOutline(0, Color(red: 0.69, green: 0.73, blue: 0.78))
        if iso {
            if spec.mode == .taper {
                // 锥孔：底面画小头圆
                let small = spec.taperDiaSmall / 2
                ctx.stroke(Path { p in
                    var first = true
                    for i in 0...48 {
                        let a = 2 * Double.pi * Double(i) / 48
                        let q = screen(project(small * cos(a), small * sin(a), -maxDepth))
                        if first { p.move(to: q); first = false } else { p.addLine(to: q) }
                    }
                }, with: .color(Color(red: 0.78, green: 0.81, blue: 0.85)), lineWidth: 1)
            } else {
                strokeOutline(-maxDepth, Color(red: 0.78, green: 0.81, blue: 0.85))
            }
            // 底面轮廓已表现厚度，不再画竖线
        }

        // 预测路径
        for s in segs where s.pts.count > 1 {
            ctx.stroke(Path { p in
                p.move(to: screen(project(Double(s.pts[0].x), Double(s.pts[0].y), s.z)))
                for q in s.pts.dropFirst() {
                    p.addLine(to: screen(project(Double(q.x), Double(q.y), s.z)))
                }
            }, with: .color(Color(red: 0.81, green: 0.84, blue: 0.88)), lineWidth: 1)
        }

        // 已走轨迹
        let need = total * progress
        var acc = 0.0
        var last: (CGPoint, Double)? = nil
        for s in segs {
            if acc > need { break }
            let frac = s.len > 0 ? min(1, (need - acc) / s.len) : 0
            let rem = s.len * frac
            var part: [CGPoint] = []
            if let first = s.pts.first { part.append(first) }
            var run = 0.0
            if s.pts.count > 1 {
                for i in 1..<s.pts.count {
                    let a = s.pts[i - 1], b = s.pts[i]
                    let d = hypot(Double(b.x - a.x), Double(b.y - a.y))
                    if run + d <= rem {
                        part.append(b)
                        run += d
                    } else {
                        let t = d > 0 ? (rem - run) / d : 0
                        part.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
                        break
                    }
                }
            }
            if part.count > 1 {
                let t = min(1, -s.z / maxDepth)
                let col = Color(red: 1 - 0.2 * t, green: 0.64 - 0.45 * t, blue: 0.37 - 0.30 * t)
                ctx.stroke(Path { p in
                    p.move(to: screen(project(Double(part[0].x), Double(part[0].y), s.z)))
                    for q in part.dropFirst() {
                        p.addLine(to: screen(project(Double(q.x), Double(q.y), s.z)))
                    }
                }, with: .color(col), lineWidth: 1.8)
            }
            last = (part.last ?? CGPoint.zero, s.z)
            acc += s.len
        }

        // 刀具
        if let last {
            let c = screen(project(Double(last.0.x), Double(last.0.y), last.1))
            let r = toolR * scale
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r * (iso ? 0.6 : 1),
                                              width: r * 2, height: r * 2 * (iso ? 0.6 : 1))),
                       with: .color(Color(red: 0.35, green: 0.4, blue: 0.48).opacity(0.85)), lineWidth: 1.2)
            if iso {
                ctx.stroke(Path { p in
                    p.move(to: c)
                    p.addLine(to: CGPoint(x: c.x, y: c.y + (-last.1) * 2 * scale))
                }, with: .color(Color(red: 0.67, green: 0.7, blue: 0.75)), lineWidth: 1)
            }
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: c.x - r, y: c.y))
                p.addLine(to: CGPoint(x: c.x + r, y: c.y))
                p.move(to: CGPoint(x: c.x, y: c.y - r))
                p.addLine(to: CGPoint(x: c.x, y: c.y + r))
            }, with: .color(Color(red: 0.35, green: 0.4, blue: 0.48).opacity(0.6)), lineWidth: 1)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 3.5, y: c.y - 3.5, width: 7, height: 7)),
                     with: .color(Color(red: 1, green: 0.42, blue: 0.10)))
        }
    }

    private func niceStep(_ v: Double) -> Double {
        let p = pow(10.0, floor(log10(max(1.0, v))))
        let n = v / p
        if n < 2 { return 2 * p }
        if n < 5 { return 5 * p }
        return 10 * p
    }
}
