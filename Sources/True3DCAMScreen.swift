import SwiftUI
import UIKit

/// 真 3D 刀路：模型由 OCCT B-Rep 提供，刀路由真实截面偏置/行切生成。
struct True3DCAMScreen: View {
    let result: True3DResult
    let model: True3DParams

    @State private var cam = True3DCAMParams()
    @State private var camResult: True3DCAMResult?
    @State private var error: String?
    @State private var isGenerating = false
    @State private var gcodeURL: URL?
    @State private var copied = false
    @State private var showAdvanced = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let camResult {
                    True3DPathPreview(segments: camResult.segments)
                        .frame(height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.black.opacity(0.08), lineWidth: 1)
                        )

                    stats(camResult.stats)
                    warningList(camResult.warnings)
                    actionRow(camResult)
                } else {
                    emptyView
                }

                generateButton

                params
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .navigationTitle("3D 刀路")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    generate()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isGenerating)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("真 3D 刀路")
                    .font(.system(size: 22, weight: .bold))
                Text("B-Rep 截面")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color(red: 1.0, green: 0.42, blue: 0.10).opacity(0.12))
                    .foregroundStyle(Color(red: 0.75, green: 0.26, blue: 0.05))
                    .clipShape(Capsule())
            }
            Text("等高线外形 · 顶面行切 · 孔腔逐层清残 · FANUC G 代码")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    private var emptyView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("刀路还没生成", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 14, weight: .semibold))
            Text("按当前 3D 实体截面生成：外形偏置、顶面/凸台/腔底面行切、孔和方腔逐层清残。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func stats(_ s: True3DCAMStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                metric("切削长度", String(format: "%.0f mm", s.cutLength))
                Divider().frame(height: 30)
                metric("层数", "\(s.layerCount)")
                Divider().frame(height: 30)
                metric("路径", "\(s.pathCount)")
                Divider().frame(height: 30)
                metric("截面", "\(s.sectionCount)")
            }
            HStack {
                Label("Z \(String(format: "%.1f", s.zMin)) ~ \(String(format: "%.1f", s.zMax))",
                      systemImage: "arrow.up.and.down")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("快移约 \(String(format: "%.0f mm", s.rapidLength))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func warningList(_ warnings: [String]) -> some View {
        if !warnings.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder
    private func actionRow(_ result: True3DCAMResult) -> some View {
        HStack(spacing: 10) {
            if let gcodeURL {
                ShareLink(item: gcodeURL) {
                    Label("分享 G 代码", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            Button {
                UIPasteboard.general.string = result.gcode
                copied = true
            } label: {
                Label(copied ? "已复制" : "复制 G 代码", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .font(.system(size: 13, weight: .medium))

        if let gcodeURL {
            NavigationLink {
                True3DGCodeScreen(code: result.gcode, fileURL: gcodeURL)
            } label: {
                HStack {
                    Label("查看完整 G 代码", systemImage: "text.alignleft")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .font(.system(size: 13, weight: .semibold))
                .padding(.vertical, 11)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
    }

    private var generateButton: some View {
        Button {
            generate()
        } label: {
            Label(isGenerating ? "正在生成刀路…" : "生成 3D 刀路", systemImage: "point.3.connected.trianglepath.dotted")
                .frame(maxWidth: .infinity)
                .font(.system(size: 15, weight: .semibold))
        }
        .buttonStyle(.borderedProminent)
        .tint(Color(red: 1.0, green: 0.42, blue: 0.10))
        .disabled(isGenerating)
    }

    private var params: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("加工参数")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color(red: 0.14, green: 0.17, blue: 0.22))

            group("刀具 / 切削") {
                numRow("刀具直径 Ø", $cam.toolDia)
                numRow("每层切深 AP", $cam.stepDown)
                numRow("行距 AE", $cam.stepOver)
                intRow("转速 S", $cam.spindle)
                intRow("切削进给 F", $cam.feed)
                intRow("下刀进给", $cam.plungeFeed)
                numRow("安全高度 Z", $cam.safeZ)
            }

            group("毛坯 / 坐标") {
                numRow("XY 单边余量", $cam.stockMarginXY)
                numRow("底面余量", $cam.stockExtraBottom)
                Picker("工件坐标系", selection: $cam.coord) {
                    ForEach([54, 55, 56, 57, 58, 59], id: \.self) { c in
                        Text("G\(c)").tag(c)
                    }
                }
                numRow("零点偏移 X", $cam.originX)
                numRow("零点偏移 Y", $cam.originY)
                intRow("程序号 O", $cam.programNo)
            }

            group("工序") {
                Toggle("外形分层粗铣", isOn: $cam.doRoughing)
                Toggle("外形精铣", isOn: $cam.doFinishing)
                Toggle("孔 / 腔逐层清残", isOn: $cam.doClearInner)
                Toggle("基础顶面飞面", isOn: $cam.doFaceBaseTop)
                Toggle("凸台顶面飞面", isOn: $cam.doFaceBossTop)
                Toggle("方腔底面飞面", isOn: $cam.doFacePocketBottom)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
            Divider()
        }
    }

    private func numRow(_ title: String, _ value: Binding<Double>) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 13))
            Spacer()
            TextField("0", value: value, format: .number.precision(.fractionLength(2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 82)
                .textFieldStyle(.roundedBorder)
            Text("mm").font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 20, alignment: .leading)
        }
    }

    private func intRow(_ title: String, _ value: Binding<Int>) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 13))
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 82)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func generate() {
        guard !isGenerating else { return }
        error = nil
        copied = false
        isGenerating = true
        do {
            let generated = try True3DCAM.generate(result: result, model: model, cam: cam)
            camResult = generated
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let url = dir.appendingPathComponent("MacroGen-3D-\(cam.programNo).nc")
            try generated.gcode.write(to: url, atomically: true, encoding: .utf8)
            gcodeURL = url
        } catch {
            self.error = error.localizedDescription
            camResult = nil
            gcodeURL = nil
        }
        isGenerating = false
    }
}

// MARK: - 2D 俯视预览

struct True3DPathPreview: View {
    let segments: [TPSeg]

    var body: some View {
        Canvas { context, size in
            guard !segments.isEmpty else { return }
            var minX = Double.greatestFiniteMagnitude
            var maxX = -Double.greatestFiniteMagnitude
            var minY = Double.greatestFiniteMagnitude
            var maxY = -Double.greatestFiniteMagnitude
            for s in segments {
                for p in s.pts {
                    minX = min(minX, Double(p.x)); maxX = max(maxX, Double(p.x))
                    minY = min(minY, Double(p.y)); maxY = max(maxY, Double(p.y))
                }
            }
            guard minX < maxX, minY < maxY else { return }
            let pad: CGFloat = 16
            let scale = min(
                (size.width - pad * 2) / CGFloat(maxX - minX),
                (size.height - pad * 2) / CGFloat(maxY - minY)
            )
            let ox = (size.width - CGFloat(maxX - minX) * scale) / 2
            let oy = (size.height - CGFloat(maxY - minY) * scale) / 2

            func map(_ p: CGPoint) -> CGPoint {
                CGPoint(
                    x: ox + CGFloat(Double(p.x) - minX) * scale,
                    y: size.height - oy - CGFloat(Double(p.y) - minY) * scale
                )
            }

            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.96, green: 0.97, blue: 0.98)))

            for seg in segments {
                guard let first = seg.pts.first else { continue }
                var path = Path()
                path.move(to: map(first))
                for p in seg.pts.dropFirst() { path.addLine(to: map(p)) }
                context.stroke(path, with: .color(Color(red: 1.0, green: 0.45, blue: 0.10)), lineWidth: 1.1)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Text("俯视 · \(segments.count) 段")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.white.opacity(0.85))
                .clipShape(Capsule())
                .padding(8)
        }
    }
}

// MARK: - G 代码页

struct True3DGCodeScreen: View {
    let code: String
    let fileURL: URL
    @State private var copied = false

    var body: some View {
        ScrollView {
            Text(code)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .navigationTitle("3D G 代码")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    UIPasteboard.general.string = code
                    copied = true
                } label: {
                    Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: fileURL) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
    }
}
