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

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .polyline: return "scribble.variable"
        case .rectangle: return "rectangle"
        case .circle: return "circle"
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
                Text(tool == .polyline
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
        }
    }

    private func addPolylinePoint(_ p: True3DPoint) {
        if points.count >= 3, let first = points.first, hypot(p.x - first.x, p.y - first.y) < max(gridStep, 0.5) {
            closed = true
            error = nil
            return
        }
        guard p.x >= -width / 2, p.x <= width / 2, p.y >= -depth / 2, p.y <= depth / 2 else {
            error = "点超出基础块范围"
            return
        }
        points.append(p)
        closed = false
        error = nil
    }

    private func closeProfile() {
        guard points.count >= 3 else {
            error = "至少需要 3 个点才能闭合"
            return
        }
        closed = true
        error = nil
    }

    private func undo() {
        if closed {
            closed = false
        } else if !points.isEmpty {
            points.removeLast()
        }
        error = nil
    }

    private func clear() {
        points = []
        previewPoints = []
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
