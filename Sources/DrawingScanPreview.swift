import SwiftUI
import UIKit

/// 拍照图纸识别结果预览：图上叠尺寸/孔位标注，下面列出可核对尺寸。
struct DrawingScanPreviewView: View {
    let result: DrawingScanResult
    var onUse: () -> Void
    var onRetry: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    imagePanel
                    HStack(spacing: 8) {
                        chip("置信度 \(Int(result.confidence * 100))%")
                        chip(result.spec.template == .free ? "自由轮廓 \(result.spec.nodes.count) 段" : "矩形外形")
                        chip("孔 \(result.spec.feats.count)")
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("尺寸核对")
                            .font(.system(size: 15, weight: .semibold))
                        HStack(spacing: 10) {
                            metric("长", ncf(result.spec.rectL))
                            metric("宽", ncf(result.spec.rectW))
                            metric("厚", ncf(result.spec.height))
                        }
                        if !result.spec.feats.isEmpty {
                            ForEach(result.spec.feats) { f in
                                Text(f.kind == .hole
                                     ? "孔 Ø\(ncf(f.dia)) @ X\(ncf(f.x)) Y\(ncf(f.y))"
                                     : "型腔 \(ncf(f.w))×\(ncf(f.h)) 深\(ncf(f.depth)) @ X\(ncf(f.x)) Y\(ncf(f.y))")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }
                        }
                        if result.spec.template == .free, result.spec.nodes.count > 1 {
                            Text("轮廓分段：" + segmentLengths(result.spec.nodes))
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        Text(result.scaleNote)
                            .font(.system(size: 12))
                            .foregroundColor(.blue)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    if !result.warnings.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("核对提示")
                                .font(.system(size: 13, weight: .semibold))
                            ForEach(result.warnings, id: \.self) { w in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("•").foregroundColor(.orange)
                                    Text(w)
                                }
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            }
                        }
                    }

                    Text("采用后进入草图：尺寸标注、孔位、轮廓段长都可继续改；确认无误再拉伸/加工。")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("拍照图纸识别")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("采用") {
                        onUse()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 10) {
                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onRetry() }
                    } label: {
                        Label("重拍 / 换图", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        onUse()
                        dismiss()
                    } label: {
                        Label("采用并进草图", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
            }
        }
    }

    private var imagePanel: some View {
        GeometryReader { geo in
            let fit = fitRect(imageSize: result.image.size, in: geo.size)
            ZStack {
                Image(uiImage: result.image)
                    .resizable()
                    .frame(width: fit.width, height: fit.height)
                    .position(x: fit.midX, y: fit.midY)

                Canvas { ctx, size in
                    guard size.width > 1, size.height > 1 else { return }
                    if result.outline.count > 2 {
                        var p = Path()
                        let first = result.outline[0]
                        p.move(to: CGPoint(x: first.x * size.width, y: (1 - first.y) * size.height))
                        for pt in result.outline.dropFirst() {
                            p.addLine(to: CGPoint(x: pt.x * size.width, y: (1 - pt.y) * size.height))
                        }
                        p.closeSubpath()
                        ctx.stroke(p, with: .color(.orange), lineWidth: 1.6)
                    }

                    for a in result.annotations {
                        let r = CGRect(
                            x: a.rect.minX * size.width,
                            y: (1 - a.rect.maxY) * size.height,
                            width: max(a.rect.width * size.width, 1),
                            height: max(a.rect.height * size.height, 1))
                        let labelH: CGFloat = 13
                        let labelW = min(size.width - 4, max(28, CGFloat(a.text.count) * 6.3 + 8))
                        let box = CGRect(
                            x: min(max(r.midX - labelW / 2, 2), size.width - labelW - 2),
                            y: min(max(r.midY - labelH / 2, 2), size.height - labelH - 2),
                            width: labelW, height: labelH)
                        let color = color(for: a.kind)
                        ctx.fill(Path(roundedRect: box, cornerRadius: 3), with: .color(color.opacity(0.92)))
                        ctx.stroke(Path(roundedRect: box, cornerRadius: 3), with: .color(.white), lineWidth: 0.6)
                        ctx.draw(Text(a.text)
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(.white), at: CGPoint(x: box.midX, y: box.midY))
                    }
                }
                .frame(width: fit.width, height: fit.height)
                .position(x: fit.midX, y: fit.midY)
            }
        }
        .frame(height: 400)
        .background(Color.black.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.5), lineWidth: 1)
        )
    }

    private func fitRect(imageSize: CGSize, in size: CGSize) -> CGRect {
        guard imageSize.width > 1, imageSize.height > 1, size.width > 1, size.height > 1 else {
            return CGRect(origin: .zero, size: size)
        }
        let s = min(size.width / imageSize.width, size.height / imageSize.height)
        let w = imageSize.width * s, h = imageSize.height * s
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    private func color(for kind: ScanAnnotationKind) -> Color {
        switch kind {
        case .outer: return .orange
        case .hole: return .red
        case .ocr: return .blue
        case .note: return .green
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(Capsule())
    }

    private func metric(_ name: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(name).font(.system(size: 11)).foregroundColor(.secondary)
            Text(value + " mm").font(.system(size: 15, weight: .semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    private func segmentLengths(_ nodes: [ContourNode]) -> String {
        guard nodes.count > 1 else { return "—" }
        var out: [String] = []
        for i in 0..<nodes.count {
            let a = nodes[i], b = nodes[(i + 1) % nodes.count]
            out.append("\(i + 1):\(ncf(hypot(b.x - a.x, b.y - a.y)) )")
        }
        return out.joined(separator: "  ")
    }
}
