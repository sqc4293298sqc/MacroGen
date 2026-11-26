import Foundation
import SwiftUI
import UIKit

/// 基础二维工程图：主视图 / 俯视图 / 左视图，带总体尺寸、孔位圆和标题栏。
/// 只读取已经生成的参数和特征，不重新求 B-Rep，导出 A4 横向 PDF。
struct True3DEngineeringDrawing: View {
    let projectName: String
    let params: True3DParams
    let stats: True3DStats?
    let features: [True3DFeatureSpec]

    @SwiftUI.Environment(\.dismiss) private var dismiss
    @State private var pdfURL: URL?
    @State private var errorText: String?

    private let pageSize = CGSize(width: 842, height: 595)

    private var width: Double { max(stats?.sizeX ?? params.width, 1) }
    private var depth: Double { max(stats?.sizeY ?? params.depth, 1) }
    private var height: Double { max(stats?.sizeZ ?? params.height, 1) }
    private var activeFeatures: [True3DFeatureSpec] { features.filter { !$0.suppressed } }

    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                drawing
                    .frame(width: pageSize.width, height: pageSize.height)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Color.black.opacity(0.25), lineWidth: 0.5))
                    .padding(12)
            }
            .background(Color(.systemGray6))
            .navigationTitle("工程图")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if let pdfURL {
                        ShareLink(item: pdfURL) {
                            Label("导出 PDF", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        ProgressView()
                    }
                }
            }
            .task { makePDF() }
            .alert("工程图导出失败", isPresented: Binding(
                get: { errorText != nil },
                set: { if !$0 { errorText = nil } }
            )) {
                Button("好", role: .cancel) { errorText = nil }
            } message: {
                Text(errorText ?? "")
            }
        }
    }

    private var drawing: some View {
        Canvas { context, size in
            let margin: CGFloat = 34
            let scale = min(
                2.25,
                min(
                    (size.width - margin * 2 - 210) / max(width + depth, 1),
                    (size.height - margin * 2 - 110) / max(height + depth, 1)
                )
            )
            let w = CGFloat(width) * scale
            let h = CGFloat(height) * scale
            let d = CGFloat(depth) * scale
            let front = CGPoint(x: 62, y: 92)
            let top = CGPoint(x: 62, y: 330)
            let right = CGPoint(x: 475, y: 92)

            drawText(&context, "\(projectName) — 工程图", at: CGPoint(x: 34, y: 30), size: 15, bold: true, anchor: .leading)
            drawText(&context, "单位 mm · 三视图 · 参考尺寸", at: CGPoint(x: 34, y: 52), size: 9, color: Color.gray, anchor: .leading)

            drawView(&context, origin: front, width: w, height: h, title: "主视图", titleOffset: -22)
            drawDimension(&context, from: CGPoint(x: front.x, y: front.y + h + 16),
                          to: CGPoint(x: front.x + w, y: front.y + h + 16),
                          label: "X \(fmtDim(width))", vertical: false)
            drawDimension(&context, from: CGPoint(x: front.x - 18, y: front.y),
                          to: CGPoint(x: front.x - 18, y: front.y + h),
                          label: "Z \(fmtDim(height))", vertical: true)

            drawView(&context, origin: top, width: w, height: d, title: "俯视图", titleOffset: -22)
            drawDimension(&context, from: CGPoint(x: top.x, y: top.y + d + 16),
                          to: CGPoint(x: top.x + w, y: top.y + d + 16),
                          label: "X \(fmtDim(width))", vertical: false)
            drawDimension(&context, from: CGPoint(x: top.x - 18, y: top.y),
                          to: CGPoint(x: top.x - 18, y: top.y + d),
                          label: "Y \(fmtDim(depth))", vertical: true)
            drawHoles(&context, origin: top, width: w, depth: d)

            drawView(&context, origin: right, width: d, height: h, title: "左视图", titleOffset: -22)
            drawDimension(&context, from: CGPoint(x: right.x, y: right.y + h + 16),
                          to: CGPoint(x: right.x + d, y: right.y + h + 16),
                          label: "Y \(fmtDim(depth))", vertical: false)
            drawDimension(&context, from: CGPoint(x: right.x - 18, y: right.y),
                          to: CGPoint(x: right.x - 18, y: right.y + h),
                          label: "Z \(fmtDim(height))", vertical: true)

            drawTitleBlock(&context, at: CGPoint(x: 536, y: 438), size: CGSize(width: 278, height: 120))
            drawText(&context, "模型：\(stats.map { "\($0.faces) 面 / \($0.edges) 边 / \($0.valid ? "有效" : "无效")" } ?? "参数模型")",
                     at: CGPoint(x: 34, y: 560), size: 9, color: Color.gray, anchor: .leading)
        }
        .background(Color.white)
    }

    private func drawView(
        _ context: inout GraphicsContext,
        origin: CGPoint,
        width: CGFloat,
        height: CGFloat,
        title: String,
        titleOffset: CGFloat
    ) {
        let rect = CGRect(x: origin.x, y: origin.y, width: width, height: height)
        context.stroke(Path { p in p.addRect(rect) }, with: .color(.black), lineWidth: 1.1)
        context.stroke(Path { p in p.addRect(rect) }, with: .color(.black.opacity(0.7)), lineWidth: 0.6)
        drawText(&context, title, at: CGPoint(x: origin.x, y: origin.y + titleOffset), size: 10, bold: true, anchor: .leading)
    }

    private func drawHoles(_ context: inout GraphicsContext, origin: CGPoint, width: CGFloat, depth: CGFloat) {
        for feature in activeFeatures where feature.kind == .hole {
            let x = origin.x + CGFloat(feature.x + width / 2)
            let y = origin.y + CGFloat(feature.y + depth / 2)
            let r = max(CGFloat(feature.dia) / 2, 1.5)
            let marker = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
            context.stroke(Path(ellipseIn: marker), with: .color(.black), lineWidth: 1.0)
            if feature.dia >= 6 {
                drawText(&context, "Ø\(fmtDim(feature.dia))", at: CGPoint(x: x, y: y + r + 8), size: 7, color: .black)
            }
        }
    }

    private func drawDimension(
        _ context: inout GraphicsContext,
        from: CGPoint,
        to: CGPoint,
        label: String,
        vertical: Bool
    ) {
        context.stroke(Path { p in p.move(to: from); p.addLine(to: to) }, with: .color(.black), lineWidth: 0.6)
        let tick: CGFloat = 4
        if vertical {
            context.stroke(Path { p in
                p.move(to: CGPoint(x: from.x - tick, y: from.y)); p.addLine(to: CGPoint(x: from.x + tick, y: from.y))
            }, with: .color(.black), lineWidth: 0.6)
            context.stroke(Path { p in
                p.move(to: CGPoint(x: to.x - tick, y: to.y)); p.addLine(to: CGPoint(x: to.x + tick, y: to.y))
            }, with: .color(.black), lineWidth: 0.6)
            drawText(&context, label, at: CGPoint(x: from.x - 10, y: (from.y + to.y) / 2), size: 8, color: .black, anchor: .trailing)
        } else {
            context.stroke(Path { p in
                p.move(to: CGPoint(x: from.x, y: from.y - tick)); p.addLine(to: CGPoint(x: from.x, y: from.y + tick))
            }, with: .color(.black), lineWidth: 0.6)
            context.stroke(Path { p in
                p.move(to: CGPoint(x: to.x, y: to.y - tick)); p.addLine(to: CGPoint(x: to.x, y: to.y + tick))
            }, with: .color(.black), lineWidth: 0.6)
            drawText(&context, label, at: CGPoint(x: (from.x + to.x) / 2, y: from.y + 6), size: 8, color: .black)
        }
    }

    private func drawTitleBlock(_ context: inout GraphicsContext, at origin: CGPoint, size: CGSize) {
        let rect = CGRect(origin: origin, size: size)
        context.stroke(Path { p in p.addRect(rect) }, with: .color(.black), lineWidth: 1.0)
        context.stroke(Path { p in
            p.move(to: CGPoint(x: origin.x, y: origin.y + 34))
            p.addLine(to: CGPoint(x: origin.x + size.width, y: origin.y + 34))
            p.move(to: CGPoint(x: origin.x, y: origin.y + 76))
            p.addLine(to: CGPoint(x: origin.x + size.width, y: origin.y + 76))
            p.move(to: CGPoint(x: origin.x + size.width * 0.66, y: origin.y + 34))
            p.addLine(to: CGPoint(x: origin.x + size.width * 0.66, y: origin.y + size.height))
        }, with: .color(.black), lineWidth: 0.7)
        drawText(&context, projectName, at: CGPoint(x: origin.x + 8, y: origin.y + 10), size: 10, bold: true, anchor: .leading)
        drawText(&context, "比例 参考 · 单位 mm", at: CGPoint(x: origin.x + 8, y: origin.y + 42), size: 8, color: Color.gray, anchor: .leading)
        drawText(&context, "三视图 / 基础尺寸", at: CGPoint(x: origin.x + 8, y: origin.y + 84), size: 9, color: .black, anchor: .leading)
        drawText(&context, "MacroGen 3D", at: CGPoint(x: origin.x + size.width * 0.69, y: origin.y + 42), size: 9, color: Color.gray, anchor: .leading)
        drawText(&context, "未签名工程图", at: CGPoint(x: origin.x + size.width * 0.69, y: origin.y + 84), size: 8, color: Color.gray, anchor: .leading)
    }

    private func drawText(
        _ context: inout GraphicsContext,
        _ text: String,
        at point: CGPoint,
        size: CGFloat,
        color: Color = .black,
        bold: Bool = false,
        anchor: UnitPoint = .center
    ) {
        let value = Text(text).font(.system(size: size, weight: bold ? .semibold : .regular)).foregroundColor(color)
        context.draw(value, at: point, anchor: anchor)
    }

    private func fmtDim(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.05 { return String(format: "%.0f", value) }
        return String(format: "%.1f", value)
    }

    private func makePDF() {
        guard pdfURL == nil else { return }
        let renderer = ImageRenderer(content: drawing.frame(width: pageSize.width, height: pageSize.height).background(Color.white))
        renderer.scale = 2
        guard let image = renderer.uiImage else {
            errorText = "无法渲染工程图"
            return
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("MacroGen-Drawings", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let name = (projectName.isEmpty ? "工程图" : projectName)
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
            let url = dir.appendingPathComponent("\(name)-三视图.pdf")
            let bounds = CGRect(origin: .zero, size: pageSize)
            let pdf = UIGraphicsPDFRenderer(bounds: bounds)
            try pdf.pdfData { ctx in
                ctx.beginPage()
                image.draw(in: bounds)
            }.write(to: url, options: .atomic)
            pdfURL = url
        } catch {
            errorText = error.localizedDescription
        }
    }
}
