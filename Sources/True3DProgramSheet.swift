import SwiftUI
import SceneKit

/// 程序单：二维轮廓、三维模型、毛坯和刀具/切削参数汇总。
struct True3DProgramSheet: View {
    let projectName: String
    let profile: [True3DPoint]
    let width: Double
    let depth: Double
    let height: Double
    let scene: SCNScene
    let cam: True3DCAMParams
    let operations: [True3DOperation]
    let stats: True3DStats?

    @Environment(\.dismiss) private var dismiss

    private struct ToolRow: Identifiable {
        let id = UUID()
        let name: String
        let toolNo: Int
        let hNo: Int
        let dia: Double
        let spindle: Int
        let feed: Int
        let plunge: Int
        let stepDown: Double
        let stepOver: Double
    }

    private var toolRows: [ToolRow] {
        if operations.isEmpty {
            return [
                ToolRow(
                    name: "默认程序",
                    toolNo: cam.toolNo,
                    hNo: cam.hNo,
                    dia: cam.toolDia,
                    spindle: cam.spindle,
                    feed: cam.feed,
                    plunge: cam.plungeFeed,
                    stepDown: cam.stepDown,
                    stepOver: cam.stepOver
                )
            ]
        }
        return operations.filter(\.enabled).map { operation in
            ToolRow(
                name: operation.kind.rawValue,
                toolNo: operation.toolNo,
                hNo: operation.hNo,
                dia: operation.toolDia,
                spindle: operation.spindle,
                feed: operation.feed,
                plunge: operation.plungeFeed,
                stepDown: operation.stepDown,
                stepOver: operation.stepOver
            )
        }
    }

    private var drawingWidth: Double {
        guard profile.count >= 3,
              let minX = profile.map(\.x).min(),
              let maxX = profile.map(\.x).max(),
              maxX - minX > 0.1 else { return width }
        return maxX - minX
    }

    private var drawingDepth: Double {
        guard profile.count >= 3,
              let minY = profile.map(\.y).min(),
              let maxY = profile.map(\.y).max(),
              maxY - minY > 0.1 else { return depth }
        return maxY - minY
    }

    private var stockX: Double { max(width + cam.stockMarginXY * 2, 1) }
    private var stockY: Double { max(depth + cam.stockMarginXY * 2, 1) }
    private var stockZ: Double { max(height + cam.stockExtraBottom, 1) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    headerCard
                    drawingCard
                    modelCard
                    stockCard
                    toolCard
                    footer
                }
                .padding(14)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("程序单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(projectName)
                .font(.system(size: 22, weight: .bold))
            HStack(spacing: 14) {
                Label(dateText, systemImage: "calendar")
                Label("CNC 加工程序", systemImage: "gearshape.2")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                summaryPill("毛坯", "\(fmt(stockX))×\(fmt(stockY))×\(fmt(stockZ))")
                summaryPill("刀号", "T\(cam.toolNo) / H\(cam.hNo)")
                summaryPill("坐标", "G\(cam.coord)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func summaryPill(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 9)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 11, weight: .semibold)).lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private var drawingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardHeader("二维轮廓图", icon: "square.dashed", detail: "\(fmt(drawingWidth)) × \(fmt(drawingDepth)) mm")
            True3DProgramDrawing(profile: profile, width: drawingWidth, depth: drawingDepth)
                .frame(height: 230)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .bottomTrailing) {
                    Text("2D")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(8)
                }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var modelCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardHeader("三维模型", icon: "cube.transparent", detail: "Z 高 \(fmt(height)) mm")
            ZStack {
                if scene.rootNode.childNodes.isEmpty {
                    Text("尚未生成三维实体")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    True3DSceneView(scene: scene, showWire: false, allowsCameraControl: false)
                }
            }
            .frame(height: 230)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .bottomTrailing) {
                Text("3D")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(8)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var stockCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardHeader("毛坯与实体", icon: "shippingbox", detail: stats.map { "\($0.faces) 面 · \($0.edges) 边" } ?? "未生成实体")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                metric("毛坯 X", "\(fmt(stockX)) mm")
                metric("毛坯 Y", "\(fmt(stockY)) mm")
                metric("毛坯 Z", "\(fmt(stockZ)) mm")
                metric("零件 X", "\(fmt(width)) mm")
                metric("零件 Y", "\(fmt(depth)) mm")
                metric("零件 Z", "\(fmt(height)) mm")
            }
            if let stats {
                Text("体积 \(fmt(stats.volume)) mm³ · \(stats.triangles) 三角面 · \(stats.valid ? "实体有效" : "实体无效")")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 9)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 11, weight: .semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private var toolCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardHeader("刀具与切削参数", icon: "wrench.and.screwdriver", detail: "\(toolRows.count) 道工序")
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        tableCell("工序", width: 112, header: true)
                        tableCell("T/H", width: 44, header: true)
                        tableCell("刀具", width: 46, header: true)
                        tableCell("S", width: 48, header: true)
                        tableCell("F", width: 48, header: true)
                        tableCell("下刀", width: 48, header: true)
                        tableCell("步距", width: 44, header: true)
                        tableCell("下刀量", width: 50, header: true)
                    }
                    ForEach(toolRows) { row in
                        HStack(spacing: 0) {
                            tableCell(row.name, width: 112)
                            tableCell("T\(row.toolNo)/H\(row.hNo)", width: 44)
                            tableCell("Ø\(fmt(row.dia))", width: 46)
                            tableCell("\(row.spindle)", width: 48)
                            tableCell("\(row.feed)", width: 48)
                            tableCell("\(row.plunge)", width: 48)
                            tableCell("\(fmt(row.stepOver))", width: 44)
                            tableCell("\(fmt(row.stepDown))", width: 50)
                        }
                    }
                }
            }
            Text("S 转速 rpm · F 进给 mm/min · 下刀 mm/min · 步距/下刀量 mm")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func tableCell(_ text: String, width: CGFloat, header: Bool = false) -> some View {
        Text(text)
            .font(.system(size: header ? 9 : 10, weight: header ? .semibold : .regular))
            .foregroundStyle(header ? Color.secondary : Color.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: width, alignment: .leading)
            .padding(.vertical, 7)
            .padding(.horizontal, 5)
            .background(header ? Color(.tertiarySystemGroupedBackground) : Color.clear)
    }

    private func cardHeader(_ title: String, icon: String, detail: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(Color(red: 0.10, green: 0.42, blue: 0.90))
            Text(title).font(.system(size: 13, weight: .semibold))
            Spacer()
            Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            Text("MacroGen · 3D绘图建模")
            Spacer()
            Text("程序单")
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .padding(.bottom, 10)
    }

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func fmt(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.0001 { return String(format: "%.0f", value) }
        return String(format: "%.2f", value)
    }
}

private struct True3DProgramDrawing: View {
    let profile: [True3DPoint]
    let width: Double
    let depth: Double

    var body: some View {
        Canvas { context, size in
            let points = drawingPoints
            guard let minX = points.map(\.x).min(),
                  let maxX = points.map(\.x).max(),
                  let minY = points.map(\.y).min(),
                  let maxY = points.map(\.y).max() else { return }
            let padding: CGFloat = 34
            let w = max(CGFloat(maxX - minX), 1)
            let h = max(CGFloat(maxY - minY), 1)
            let scale = min((size.width - padding * 2) / w, (size.height - padding * 2) / h)
            let centerX = (minX + maxX) / 2
            let centerY = (minY + maxY) / 2
            func map(_ p: True3DPoint) -> CGPoint {
                CGPoint(
                    x: size.width / 2 + CGFloat(p.x - centerX) * scale,
                    y: size.height / 2 - CGFloat(p.y - centerY) * scale
                )
            }
            let mapped = points.map(map)
            var path = Path()
            path.move(to: mapped[0])
            for p in mapped.dropFirst() { path.addLine(to: p) }
            path.closeSubpath()
            context.fill(path, with: .color(Color(red: 0.95, green: 0.32, blue: 0.06).opacity(0.10)))
            context.stroke(path, with: .color(Color(red: 0.95, green: 0.32, blue: 0.06)), lineWidth: 1.8)

            let top = mapped.min(by: { $0.y < $1.y })?.y ?? padding
            let left = mapped.min(by: { $0.x < $1.x })?.x ?? padding
            let right = mapped.max(by: { $0.x < $1.x })?.x ?? size.width - padding
            let bottom = mapped.max(by: { $0.y < $1.y })?.y ?? size.height - padding

            var hLine = Path()
            hLine.move(to: CGPoint(x: left, y: top - 12))
            hLine.addLine(to: CGPoint(x: right, y: top - 12))
            context.stroke(hLine, with: .color(Color(red: 0.10, green: 0.42, blue: 0.90)), lineWidth: 1)
            context.draw(
                Text("\(fmt(width)) mm")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(red: 0.10, green: 0.42, blue: 0.90)),
                at: CGPoint(x: (left + right) / 2, y: top - 22)
            )

            var vLine = Path()
            vLine.move(to: CGPoint(x: left - 12, y: top))
            vLine.addLine(to: CGPoint(x: left - 12, y: bottom))
            context.stroke(vLine, with: .color(Color(red: 0.10, green: 0.42, blue: 0.90)), lineWidth: 1)
            context.draw(
                Text("\(fmt(depth)) mm")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(red: 0.10, green: 0.42, blue: 0.90)),
                at: CGPoint(x: left - 30, y: (top + bottom) / 2)
            )
        }
    }

    private var drawingPoints: [True3DPoint] {
        if profile.count >= 3 { return profile }
        let w = max(width, 1)
        let d = max(depth, 1)
        return [
            True3DPoint(x: -w / 2, y: -d / 2),
            True3DPoint(x: w / 2, y: -d / 2),
            True3DPoint(x: w / 2, y: d / 2),
            True3DPoint(x: -w / 2, y: d / 2)
        ]
    }

    private func fmt(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.0001 { return String(format: "%.0f", value) }
        return String(format: "%.2f", value)
    }
}
