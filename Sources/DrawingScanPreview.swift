import SwiftUI
import UIKit

/// 拍照图纸识别结果预览：图上叠尺寸/孔位标注，下面列出可核对尺寸。
struct DrawingScanPreviewView: View {
    let result: DrawingScanResult
    var onUse: (DrawingScanResult) -> Void
    var onRetry: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var lengthText: String
    @State private var widthText: String
    @State private var heightText: String

    init(result: DrawingScanResult, onUse: @escaping (DrawingScanResult) -> Void, onRetry: @escaping () -> Void) {
        self.result = result
        self.onUse = onUse
        self.onRetry = onRetry
        _lengthText = State(initialValue: ncf(result.spec.rectL))
        _widthText = State(initialValue: ncf(result.spec.rectW))
        _heightText = State(initialValue: ncf(result.spec.height))
    }

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
                        Text("识别错了可直接改长/宽/厚；孔位、轮廓会按比例一起缩放。")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        HStack(spacing: 10) {
                            editMetric("长", $lengthText)
                            editMetric("宽", $widthText)
                            editMetric("厚", $heightText)
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
                        use()
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
                        use()
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

    private func editMetric(_ name: String, _ text: Binding<String>) -> some View {
        VStack(spacing: 3) {
            Text(name).font(.system(size: 11)).foregroundColor(.secondary)
            TextField("", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
                .textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    private func use() {
        var spec = result.spec
        let oldL = max(spec.rectL, 0.001)
        let oldW = max(spec.rectW, 0.001)
        let newL = max(Double(lengthText) ?? oldL, 0.1)
        let newW = max(Double(widthText) ?? oldW, 0.1)
        let newH = max(Double(heightText) ?? spec.height, 0.1)
        let sx = newL / oldL
        let sy = newW / oldW

        spec.rectL = newL
        spec.rectW = newW
        spec.height = newH

        if spec.template == .free {
            spec.nodes = spec.nodes.map { n in
                var n = n
                n.x *= sx
                n.y *= sy
                return n
            }
        }
        for i in spec.feats.indices {
            spec.feats[i].x *= sx
            spec.feats[i].y *= sy
            if spec.feats[i].kind == .hole {
                spec.feats[i].dia *= min(sx, sy)
                spec.feats[i].depth = newH + 1
            } else {
                spec.feats[i].w *= sx
                spec.feats[i].h *= sy
            }
        }
        for i in spec.innerLoops.indices {
            spec.innerLoops[i].cx *= sx
            spec.innerLoops[i].cy *= sy
            spec.innerLoops[i].rectL *= sx
            spec.innerLoops[i].rectW *= sy
            spec.innerLoops[i].circleD *= min(sx, sy)
            spec.innerLoops[i].slotL *= sx
            spec.innerLoops[i].slotW *= sy
            spec.innerLoops[i].depth = min(spec.innerLoops[i].depth, newH)
        }

        var updated = result
        updated.spec = spec
        updated.summary = "外形 \(ncf(newL)) × \(ncf(newW)) mm · 厚 \(ncf(newH)) mm · 孔 \(spec.feats.count) 个"
        updated.scaleNote = "已按你输入的尺寸修正；孔位和轮廓按比例缩放"
        onUse(updated)
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
