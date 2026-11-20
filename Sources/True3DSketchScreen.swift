import Foundation
import SwiftUI

// MARK: - 草图结果

enum True3DSketchOutput {
    case base([True3DPoint])
    case feature(True3DFeatureSpec)
}

enum True3DSketchTool: String, CaseIterable, Identifiable {
    case polyline = "折线"
    case rectangle = "矩形"
    case circle = "圆"
    case arc = "圆弧"
    case spline = "样条"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .polyline: return "scribble.variable"
        case .rectangle: return "rectangle"
        case .circle: return "circle"
        case .arc: return "circle.dashed"
        case .spline: return "scribble"
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
struct True3DSketchScreen: View {
    let width: Double
    let depth: Double
    var embedded: Bool = false
    let onCommit: (True3DSketchOutput) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var tool: True3DSketchTool = .polyline
    @State private var points: [True3DPoint] = []
    @State private var previewPoints: [True3DPoint] = []
    @State private var arcPoints: [True3DPoint] = []
    @State private var closed = false
    @State private var gridStep: Double = 5
    @State private var snap = true
    @State private var showGrid = true
    @State private var operation: True3DSketchOperation = .boss
    @State private var extrudeDepth: Double = 5
    @State private var error: String?
    @State private var canvasSize: CGSize = .zero
    @State private var dragStart: CGPoint?

    private var baseWidth: CGFloat { CGFloat(max(width, 1)) }
    private var baseDepth: CGFloat { CGFloat(max(depth, 1)) }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            sketchCanvas
            summaryBar
            bottomBar
        }
        .navigationTitle("草图")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !embedded {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("撤销上一点") { undo() }
                    Button("清空草图") { clear() }
                    Divider()
                    Button("闭合轮廓") { closeProfile() }
                    Divider()
                    Button("旋转 90°") { rotateSketch() }
                    Button("水平镜像") { mirrorSketch(horizontal: true) }
                    Button("垂直镜像") { mirrorSketch(horizontal: false) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    // MARK: 顶部工具条

    private var topBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(True3DSketchTool.allCases) { item in
                    Button {
                        tool = item
                        previewPoints = []
                        arcPoints = []
                    } label: {
                        Label(item.rawValue, systemImage: item.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                tool == item
                                    ? Color(red: 1.0, green: 0.42, blue: 0.10)
                                    : Color(.secondarySystemBackground),
                                in: Capsule()
                            )
                            .foregroundStyle(tool == item ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }

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
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    // MARK: 画布

    private var sketchCanvas: some View {
        GeometryReader { geo in
            Canvas { context, size in
                drawGrid(context: &context, size: size)
                drawProfile(context: &context, size: size)
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
                     : "按住拖动画\(tool.rawValue)，松开生成闭合轮廓")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.88), in: Capsule())
                    .padding(10)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard tool != .polyline, !closed else { return }
                        if dragStart == nil { dragStart = value.startLocation }
                        let a = worldPoint(value.startLocation, in: geo.size)
                        let b = worldPoint(value.location, in: geo.size)
                        previewPoints = shapePoints(from: a, to: b)
                    }
                    .onEnded { value in
                        defer {
                            dragStart = nil
                            previewPoints = []
                        }
                        guard !closed else { return }
                        let a = worldPoint(value.startLocation, in: geo.size)
                        let b = worldPoint(value.location, in: geo.size)
                        switch tool {
                        case .polyline:
                            addPolylinePoint(snapped(b))
                        case .arc:
                            handleArcTap(snapped(b))
                        case .spline:
                            addPolylinePoint(snapped(b), maximumPoints: 32)
                        case .rectangle, .circle:
                            let shape = shapePoints(from: a, to: b)
                            guard shape.count >= 3 else {
                                error = "轮廓太小，至少画 \(String(format: "%.0f", gridStep)) mm"
                                return
                            }
                            points = shape
                            closed = true
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
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.96, green: 0.97, blue: 0.98)))

        let s = scale(for: size)
        let halfW = baseWidth / 2
        let halfD = baseDepth / 2
        let rect = CGRect(
            x: size.width / 2 - halfW * s,
            y: size.height / 2 - halfD * s,
            width: baseWidth * s,
            height: baseDepth * s
        )
        context.fill(Path(rect), with: .color(Color.white))
        context.stroke(Path(rect), with: .color(Color.black.opacity(0.16)), lineWidth: 1.5)

        guard showGrid else { return }
        let step = max(gridStep, 0.5) * Double(s)
        guard step > 3 else { return }

        var x = rect.minX
        while x <= rect.maxX + 0.5 {
            var p = Path()
            p.move(to: CGPoint(x: x, y: rect.minY))
            p.addLine(to: CGPoint(x: x, y: rect.maxY))
            context.stroke(p, with: .color(Color.black.opacity(0.055)), lineWidth: 0.7)
            x += step
        }
        var y = rect.minY
        while y <= rect.maxY + 0.5 {
            var p = Path()
            p.move(to: CGPoint(x: rect.minX, y: y))
            p.addLine(to: CGPoint(x: rect.maxX, y: y))
            context.stroke(p, with: .color(Color.black.opacity(0.055)), lineWidth: 0.7)
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

    private func drawProfile(context: inout GraphicsContext, size: CGSize) {
        guard points.count > 1 else { return }
        let mapped = points.map { viewPoint($0, in: size) }
        var path = Path()
        path.move(to: mapped[0])
        for p in mapped.dropFirst() { path.addLine(to: p) }
        if closed {
            path.closeSubpath()
            context.fill(path, with: .color(Color(red: 1.0, green: 0.42, blue: 0.10).opacity(0.16)))
        }
        context.stroke(path, with: .color(Color(red: 0.9, green: 0.33, blue: 0.05)), lineWidth: 1.8)

        for (index, p) in mapped.enumerated() {
            let r: CGFloat = index == 0 ? 5 : 3.2
            let dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            context.fill(dot, with: .color(index == 0 ? Color.orange : Color.black.opacity(0.55)))
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
            Text("\(points.count) 点")
            Text(closed ? "已闭合" : "未闭合")
                .foregroundStyle(closed ? .green : .orange)
            if let box {
                Text("X \(fmt(box.maxX - box.minX)) × Y \(fmt(box.maxY - box.minY)) mm")
            }
            Spacer()
            Button(closed ? "重新画" : "闭合轮廓") {
                if closed {
                    points = []
                    closed = false
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
                .disabled(points.count < 3 || !closed)
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

    private func snapped(_ p: True3DPoint) -> True3DPoint {
        guard snap else { return p }
        let g = max(gridStep, 0.1)
        return True3DPoint(
            x: (p.x / g).rounded() * g,
            y: (p.y / g).rounded() * g
        )
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
        case .arc, .spline:
            return []
        }
    }

    /// 三点圆弧：圆心 → 起点 → 终点。生成逆时针圆弧后用弦直接闭合，
    /// 让圆弧轮廓可以直接作为基础轮廓或拉伸特征。
    private func handleArcTap(_ p: True3DPoint) {
        guard !closed else { return }
        guard p.x >= -width / 2, p.x <= width / 2, p.y >= -depth / 2, p.y <= depth / 2 else {
            error = "点超出基础块范围"
            return
        }
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
        guard arc.allSatisfy({ $0.x >= -width / 2 - 0.1 && $0.x <= width / 2 + 0.1 && $0.y >= -depth / 2 - 0.1 && $0.y <= depth / 2 + 0.1 }) else {
            error = "圆弧超出基础块范围，缩小半径或移动圆心"
            arcPoints = []
            previewPoints = []
            return
        }
        points = arc
        closed = true
        arcPoints = []
        previewPoints = []
        error = nil
    }

    private func addPolylinePoint(_ p: True3DPoint, maximumPoints: Int = 200) {
        if points.count >= 3, let first = points.first, hypot(p.x - first.x, p.y - first.y) < max(gridStep, 0.5) {
            closed = true
            error = nil
            return
        }
        guard p.x >= -width / 2, p.x <= width / 2, p.y >= -depth / 2, p.y <= depth / 2 else {
            error = "点超出基础块范围"
            return
        }
        guard points.count < maximumPoints else {
            error = "点数已达上限，按“闭合轮廓”生成曲线"
            return
        }
        points.append(p)
        closed = false
        error = nil
    }

    private func rotateSketch() {
        guard !points.isEmpty else { return }
        let rotated = points.map { True3DPoint(x: -$0.y, y: $0.x) }
        guard rotated.allSatisfy({ $0.x >= -width / 2 - 0.1 && $0.x <= width / 2 + 0.1 && $0.y >= -depth / 2 - 0.1 && $0.y <= depth / 2 + 0.1 }) else {
            error = "旋转后超出基础块范围"
            return
        }
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

    private func closeProfile() {
        guard points.count >= 3 else {
            error = "至少需要 3 个点才能闭合"
            return
        }
        if tool == .spline, !closed {
            let smoothed = smoothClosed(points, samples: 8)
            guard smoothed.allSatisfy({ $0.x >= -width / 2 - 0.1 && $0.x <= width / 2 + 0.1 && $0.y >= -depth / 2 - 0.1 && $0.y <= depth / 2 + 0.1 }) else {
                error = "样条圆滑后超出基础块，缩小控制点范围"
                return
            }
            points = smoothed
        }
        closed = true
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
            closed = false
        } else if !points.isEmpty {
            points.removeLast()
        }
        error = nil
    }

    private func clear() {
        points = []
        previewPoints = []
        arcPoints = []
        closed = false
        error = nil
    }

    private var bounds: (minX: Double, maxX: Double, minY: Double, maxY: Double)? {
        guard let minX = points.map(\.x).min(),
              let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(),
              let maxY = points.map(\.y).max() else { return nil }
        return (minX, maxX, minY, maxY)
    }

    private func commit() {
        guard points.count >= 3 else {
            error = "草图至少需要 3 个点"
            return
        }
        guard closed else {
            error = "请先闭合轮廓"
            return
        }
        guard let box = bounds, box.maxX - box.minX > 0.1, box.maxY - box.minY > 0.1 else {
            error = "草图尺寸太小"
            return
        }

        switch operation {
        case .base:
            onCommit(.base(points))
        case .boss, .cut:
            var feature = True3DFeatureSpec(kind: operation == .boss ? .profileBoss : .profileCut)
            feature.name = operation == .boss ? "草图凸台" : "草图切除"
            feature.profile = points
            feature.depth = max(extrudeDepth, 0.1)
            feature.bossHeight = max(extrudeDepth, 0.1)
            onCommit(.feature(feature))
        }
        if !embedded { dismiss() }
    }

    private func fmt(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.0001 { return String(format: "%.0f", value) }
        return String(format: "%.1f", value)
    }
}
