import SwiftUI
import UIKit
import SceneKit

/// 多工序刀路的分色信息：一段连续 segments 属于同一道工序。
struct True3DPathRunBand: Identifiable {
    let id: Int
    let range: Range<Int>
    let color: Color
    let name: String
    let toolNo: Int
    let toolDia: Double
}

func true3DOperationColor(_ index: Int) -> Color {
    let palette: [Color] = [
        Color(red: 1.00, green: 0.42, blue: 0.10),
        Color(red: 0.18, green: 0.50, blue: 0.93),
        Color(red: 0.13, green: 0.63, blue: 0.42),
        Color(red: 0.55, green: 0.36, blue: 0.96),
        Color(red: 0.88, green: 0.66, blue: 0.00),
        Color(red: 0.88, green: 0.32, blue: 0.32),
        Color(red: 0.00, green: 0.65, blue: 0.65),
        Color(red: 0.42, green: 0.23, blue: 0.80),
        Color(red: 0.30, green: 0.49, blue: 0.06),
        Color(red: 0.86, green: 0.15, blue: 0.47)
    ]
    return palette[index % palette.count]
}

func true3DPathBands(_ runs: [True3DCAMRun]) -> [True3DPathRunBand] {
    var bands: [True3DPathRunBand] = []
    var start = 0
    for (index, run) in runs.enumerated() {
        let end = start + run.segments.count
        if end > start {
            bands.append(True3DPathRunBand(
                id: index,
                range: start..<end,
                color: true3DOperationColor(index),
                name: run.operation.kind.rawValue,
                toolNo: run.operation.toolNo,
                toolDia: run.operation.toolDia
            ))
        }
        start = end
    }
    return bands
}

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
                    True3DPathSimulation(segments: camResult.segments, runs: camResult.runs)
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
                Toggle("G54 毛坯中心 X0Y0", isOn: $cam.stockCenterOrigin)
                    .font(.system(size: 12, weight: .semibold))
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

// MARK: - 3D 刀路预览 / 刀路模拟

struct True3DPathSimulation: View {
    let segments: [TPSeg]
    var runs: [True3DCAMRun] = []

    @State private var progress: Double = 0
    @State private var playing = false
    @State private var speed: Double = 1
    @State private var scopeAll = true
    @State private var selectedRun = 0

    private let timer = Timer.publish(every: 0.08, on: .main, in: .common).autoconnect()

    private var safeRunIndex: Int {
        guard !runs.isEmpty else { return 0 }
        return min(max(selectedRun, 0), runs.count - 1)
    }

    private var visibleSegments: [TPSeg] {
        guard !runs.isEmpty else { return segments }
        if scopeAll { return segments }
        return runs[safeRunIndex].segments
    }

    private var bands: [True3DPathRunBand] {
        if runs.isEmpty { return [] }
        if scopeAll { return true3DPathBands(runs) }
        let index = safeRunIndex
        let run = runs[index]
        guard !run.segments.isEmpty else { return [] }
        return [
            True3DPathRunBand(
                id: index,
                range: 0..<run.segments.count,
                color: true3DOperationColor(index),
                name: run.operation.kind.rawValue,
                toolNo: run.operation.toolNo,
                toolDia: run.operation.toolDia
            )
        ]
    }

    private var totalLength: Double {
        max(visibleSegments.reduce(0) { $0 + max($1.len, 0.001) }, 0.001)
    }

    /// 1× 速度下走完整条程序所需秒数；长程序自动压缩到 45 秒内。
    private var duration: Double {
        min(max(totalLength / 100.0, 8.0), 45.0)
    }

    private var currentState: (index: Int, z: Double, x: Double, y: Double)? {
        let source = visibleSegments
        guard !source.isEmpty else { return nil }
        let target = max(0, min(progress, 1)) * totalLength
        var traveled = 0.0
        for (index, seg) in source.enumerated() {
            let length = max(seg.len, 0.001)
            if target <= traveled + length, let first = seg.pts.first {
                let fraction = max(0, min((target - traveled) / length, 1))
                let pts = seg.pts
                let n = max(pts.count - 1, 1)
                let pos = fraction * Double(n)
                let i = min(Int(pos), n - 1)
                let t = pos - Double(i)
                let a = pts[i]
                let b = pts[min(i + 1, n)]
                return (
                    index,
                    seg.z,
                    Double(a.x) + (Double(b.x) - Double(a.x)) * t,
                    Double(a.y) + (Double(b.y) - Double(a.y)) * t
                )
            }
            traveled += length
        }
        if let last = source.last, let p = last.pts.last {
            return (source.count - 1, last.z, Double(p.x), Double(p.y))
        }
        return nil
    }

    private var currentBand: True3DPathRunBand? {
        guard let state = currentState else { return nil }
        return bands.first { $0.range.contains(state.index) }
    }

    private var currentOperation: True3DOperation? {
        guard let band = currentBand, runs.indices.contains(band.id) else { return nil }
        return runs[band.id].operation
    }

    var body: some View {
        VStack(spacing: 0) {
            if !runs.isEmpty {
                HStack(spacing: 8) {
                    Picker("范围", selection: $scopeAll) {
                        Text("全程序").tag(true)
                        Text("单序").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 138)

                    if !scopeAll {
                        Picker("工序", selection: $selectedRun) {
                            ForEach(runs.indices, id: \.self) { index in
                                Text("\(index + 1). \(runs[index].operation.kind.rawValue)")
                                    .tag(index)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    Spacer()
                    Text(scopeAll ? "\(runs.count) 道工序" : "只走当前一序")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 8)
            }

            True3DPathPreview(segments: visibleSegments, progress: progress, bands: bands)
                .frame(height: 300)
                .overlay(alignment: .topLeading) {
                    if let band = currentBand, let state = currentState {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 5) {
                                Circle().fill(band.color).frame(width: 7, height: 7)
                                Text("\(band.id + 1). \(band.name)")
                                    .font(.system(size: 10, weight: .bold))
                                    .lineLimit(1)
                            }
                            Text(String(format: "X %+.2f   Y %+.2f   Z %+.2f", state.x, state.y, state.z))
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)
                            if let op = currentOperation {
                                Text("T\(op.toolNo) H\(op.hNo) D\(op.dNo) · Ø\(String(format: "%.1f", op.toolDia)) · 层 \(runs[band.id].stats.layerCount) · S\(op.spindle) / F\(op.feed)")
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(Color.black.opacity(0.08), lineWidth: 1)
                        )
                        .padding(9)
                    }
                }

            HStack(spacing: 8) {
                Button {
                    if progress >= 1 { progress = 0 }
                    playing.toggle()
                } label: {
                    Label(playing ? "暂停" : "播放", systemImage: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 78)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 1.0, green: 0.42, blue: 0.10))

                Button {
                    progress = 0
                    playing = false
                } label: {
                    Image(systemName: "gobackward")
                        .font(.system(size: 13))
                }
                .buttonStyle(.bordered)

                Picker("速度", selection: $speed) {
                    Text("1×").tag(1.0)
                    Text("4×").tag(4.0)
                    Text("16×").tag(16.0)
                }
                .pickerStyle(.segmented)
                .frame(width: 142)

                Spacer()

                Text("\(Int(progress * 100))%")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 38, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            Slider(value: $progress, in: 0...1)
                .tint(Color(red: 1.0, green: 0.42, blue: 0.10))
                .padding(.horizontal, 12)

            if let band = currentBand {
                HStack(spacing: 6) {
                    Circle().fill(band.color).frame(width: 7, height: 7)
                    Text("第 \(band.id + 1) 序 · \(band.name) · T\(band.toolNo) Ø\(String(format: "%.1f", band.toolDia))")
                        .font(.system(size: 10, weight: .semibold))
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
            }

            HStack(spacing: 12) {
                if let state = currentState {
                    Label(String(format: "X %.2f  Y %.2f", state.x, state.y),
                          systemImage: "scope")
                    Label(String(format: "Z %.2f", state.z), systemImage: "arrow.up.and.down")
                    Text("第 \(state.index + 1)/\(visibleSegments.count) 段")
                } else {
                    Text("没有可模拟的刀路")
                }
                Spacer()
                Text(scopeAll ? "分色 · 已走刀路" : "单序 · 已走刀路")
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.bottom, 9)
        }
        .onReceive(timer) { _ in
            guard playing else { return }
            let step = 0.08 * speed / duration
            progress = min(1, progress + step)
            if progress >= 1 { playing = false }
        }
        .onChange(of: scopeAll) { _ in
            progress = 0
            playing = false
        }
        .onChange(of: selectedRun) { _ in
            progress = 0
            playing = false
        }
        .onChange(of: runs.count) { newCount in
            if newCount == 0 { scopeAll = true; selectedRun = 0 }
            else if selectedRun >= newCount { selectedRun = newCount - 1 }
        }
        .onAppear {
            if selectedRun >= runs.count { selectedRun = max(0, runs.count - 1) }
        }
    }
}

struct True3DPathPreview: View {
    let segments: [TPSeg]
    var progress: Double? = nil
    var bands: [True3DPathRunBand] = []

    @State private var yaw: Double = -0.66
    @State private var pitch: Double = 0.52
    @State private var zoom: CGFloat = 1.0
    @State private var zoomStart: CGFloat? = nil
    @State private var lastDrag: CGSize = .zero

    private let cutColor = Color(red: 1.0, green: 0.45, blue: 0.10)
    private let rapidColor = Color(red: 0.48, green: 0.56, blue: 0.66)

    private func bandColor(at index: Int) -> Color {
        bands.first(where: { $0.range.contains(index) })?.color ?? cutColor
    }

    private func currentBand(at index: Int) -> True3DPathRunBand? {
        bands.first(where: { $0.range.contains(index) })
    }

    private var totalLength: Double {
        max(segments.reduce(0) { $0 + max($1.len, 0.001) }, 0.001)
    }

    private var bounds: (minX: Double, maxX: Double, minY: Double, maxY: Double, minZ: Double, maxZ: Double)? {
        guard !segments.isEmpty else { return nil }
        var minX = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        var minZ = Double.greatestFiniteMagnitude
        var maxZ = -Double.greatestFiniteMagnitude
        for s in segments {
            minZ = min(minZ, s.z); maxZ = max(maxZ, s.z)
            for p in s.pts {
                minX = min(minX, Double(p.x)); maxX = max(maxX, Double(p.x))
                minY = min(minY, Double(p.y)); maxY = max(maxY, Double(p.y))
            }
        }
        guard minX < maxX, minY < maxY else { return nil }
        return (minX, maxX, minY, maxY, minZ, min(maxZ, minZ + 0.001))
    }

    var body: some View {
        Canvas { context, size in
            guard let b = bounds else { return }
            let pad: CGFloat = 30
            let dx = max(CGFloat(b.maxX - b.minX), 1)
            let dy = max(CGFloat(b.maxY - b.minY), 1)
            let dz = max(CGFloat(b.maxZ - b.minZ), 0.5)
            let zBoost: CGFloat = 1.8
            let span = max(dx, dy, dz * zBoost * 1.15, 1)
            let fit = min((size.width - pad * 2) / span,
                          (size.height - pad * 2) / (span * 0.78))
            let scale = max(1, fit) * zoom
            let cx = (b.minX + b.maxX) / 2
            let cy = (b.minY + b.maxY) / 2
            let cz = (b.minZ + b.maxZ) / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2 + 6)
            let cyaw = cos(yaw), syaw = sin(yaw)
            let cp = cos(pitch), sp = sin(pitch)

            func project(_ x: Double, _ y: Double, _ z: Double) -> CGPoint {
                let px = x - cx, py = y - cy, pz = (z - cz) * Double(zBoost)
                let x1 = px * cyaw - py * syaw
                let y1 = px * syaw + py * cyaw
                let y2 = y1 * cp - pz * sp
                return CGPoint(x: center.x + CGFloat(x1) * scale,
                               y: center.y - CGFloat(y2) * scale)
            }

            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .color(Color(red: 0.95, green: 0.97, blue: 0.99)))

            // 地面网格：让 Z 深度和工件平面可见
            let groundZ = b.minZ
            let grid = 6
            for i in 0...grid {
                let fx = b.minX + (b.maxX - b.minX) * Double(i) / Double(grid)
                let fy = b.minY + (b.maxY - b.minY) * Double(i) / Double(grid)
                var px = Path()
                px.move(to: project(fx, b.minY, groundZ))
                px.addLine(to: project(fx, b.maxY, groundZ))
                context.stroke(px, with: .color(Color.black.opacity(0.075)), lineWidth: 0.8)
                var py = Path()
                py.move(to: project(b.minX, fy, groundZ))
                py.addLine(to: project(b.maxX, fy, groundZ))
                context.stroke(py, with: .color(Color.black.opacity(0.075)), lineWidth: 0.8)
            }

            // 工件包络线：X/Y/Z 三个方向都有尺度感
            let corners: [(Double, Double)] = [(b.minX, b.minY), (b.maxX, b.minY), (b.maxX, b.maxY), (b.minX, b.maxY)]
            for (i, c) in corners.enumerated() {
                var v = Path()
                v.move(to: project(c.0, c.1, b.minZ))
                v.addLine(to: project(c.0, c.1, b.maxZ))
                context.stroke(v, with: .color(Color(red: 0.35, green: 0.45, blue: 0.58).opacity(0.16)), lineWidth: 0.8)
                let n = corners[(i + 1) % corners.count]
                var edge = Path()
                edge.move(to: project(c.0, c.1, b.minZ))
                edge.addLine(to: project(n.0, n.1, b.minZ))
                context.stroke(edge, with: .color(Color(red: 0.35, green: 0.45, blue: 0.58).opacity(0.11)), lineWidth: 0.8)
            }

            func stroke(_ seg: TPSeg, fraction: Double, color: Color, width: CGFloat, dashed: Bool) {
                guard let first = seg.pts.first else { return }
                let clamped = max(0, min(fraction, 1))
                var path = Path()
                path.move(to: project(Double(first.x), Double(first.y), seg.z))
                if clamped >= 1 {
                    for p in seg.pts.dropFirst() {
                        path.addLine(to: project(Double(p.x), Double(p.y), seg.z))
                    }
                } else {
                    let n = max(seg.pts.count - 1, 1)
                    let pos = clamped * Double(n)
                    let complete = Int(pos)
                    if complete > 0 {
                        for i in 1...complete {
                            let p = seg.pts[min(i, n)]
                            path.addLine(to: project(Double(p.x), Double(p.y), seg.z))
                        }
                    }
                    if complete < n {
                        let t = pos - Double(complete)
                        let a = seg.pts[complete]
                        let bb = seg.pts[min(complete + 1, n)]
                        path.addLine(to: project(Double(a.x) + (Double(bb.x) - Double(a.x)) * t,
                                                Double(a.y) + (Double(bb.y) - Double(a.y)) * t,
                                                seg.z))
                    }
                }
                context.stroke(path, with: .color(color),
                               style: StrokeStyle(lineWidth: width, dash: dashed ? [4, 3] : []))
            }

            // 全刀路：按工序分色，快移灰色虚线
            for (index, seg) in segments.enumerated() {
                stroke(seg, fraction: 1,
                       color: seg.cut ? bandColor(at: index).opacity(0.20) : rapidColor.opacity(0.20),
                       width: seg.cut ? 1.1 : 0.8,
                       dashed: !seg.cut)
            }

            // 已走部分
            let shown = progress ?? 1
            var consumed = max(0, min(shown, 1)) * totalLength
            for (index, seg) in segments.enumerated() {
                let len = max(seg.len, 0.001)
                let traveled = seg.cut ? bandColor(at: index) : rapidColor.opacity(0.75)
                if consumed <= 0 {
                    if progress == nil {
                        stroke(seg, fraction: 1,
                               color: traveled,
                               width: seg.cut ? 1.3 : 0.9,
                               dashed: !seg.cut)
                    }
                } else if consumed >= len {
                    stroke(seg, fraction: 1,
                           color: traveled,
                           width: seg.cut ? 1.3 : 0.9,
                           dashed: !seg.cut)
                    consumed -= len
                } else {
                    stroke(seg, fraction: consumed / len,
                           color: traveled,
                           width: seg.cut ? 1.3 : 0.9,
                           dashed: !seg.cut)
                    consumed = 0
                }
            }

            // 当前刀具位置：圆环 + 到地面的虚线，明确它在 3D 深度里
            if let progress, progress < 1, let pos = currentPosition(at: progress) {
                let markerColor = currentBand(at: pos.index)?.color ?? cutColor
                let ground = project(Double(pos.x), Double(pos.y), b.minZ)
                let knife = project(Double(pos.x), Double(pos.y), pos.z)
                var drop = Path()
                drop.move(to: knife)
                drop.addLine(to: ground)
                context.stroke(drop, with: .color(markerColor.opacity(0.45)),
                               style: StrokeStyle(lineWidth: 0.9, dash: [3, 3]))
                let rect = CGRect(x: knife.x - 5, y: knife.y - 5, width: 10, height: 10)
                context.fill(Path(ellipseIn: rect), with: .color(.white))
                context.stroke(Path(ellipseIn: rect), with: .color(markerColor), lineWidth: 2)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let dx = v.translation.width - lastDrag.width
                    let dy = v.translation.height - lastDrag.height
                    lastDrag = v.translation
                    yaw -= Double(dx) * 0.01
                    pitch = min(1.18, max(-0.35, pitch + Double(dy) * 0.008))
                }
                .onEnded { _ in lastDrag = .zero }
        )
        .simultaneousGesture(
            MagnificationGesture()
                .onChanged { v in
                    if zoomStart == nil { zoomStart = zoom }
                    zoom = min(1.7, max(0.7, (zoomStart ?? 1) * v))
                }
                .onEnded { _ in zoomStart = nil }
        )
        .overlay(alignment: .topLeading) {
            Label("3D · 拖动旋转", systemImage: "cube.transparent")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.white.opacity(0.82))
                .clipShape(Capsule())
                .padding(8)
        }
        .overlay(alignment: .bottomTrailing) {
            Text(bands.isEmpty ? "立体 · \(segments.count) 段 · X/Y/Z" : "分色 · \(bands.count) 序 · \(segments.count) 段")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.white.opacity(0.85))
                .clipShape(Capsule())
                .padding(8)
        }
    }

    private func currentPosition(at progress: Double) -> (x: CGFloat, y: CGFloat, z: Double, index: Int)? {
        let target = max(0, min(progress, 1)) * totalLength
        var traveled = 0.0
        for (index, seg) in segments.enumerated() {
            let len = max(seg.len, 0.001)
            if target <= traveled + len, let first = seg.pts.first {
                let fraction = max(0, min((target - traveled) / len, 1))
                let n = max(seg.pts.count - 1, 1)
                let pos = fraction * Double(n)
                let i = min(Int(pos), n - 1)
                let t = pos - Double(i)
                let a = seg.pts[i]
                let b = seg.pts[min(i + 1, n)]
                return (a.x + (b.x - a.x) * CGFloat(t), a.y + (b.y - a.y) * CGFloat(t), seg.z, index)
            }
            traveled += len
        }
        if let last = segments.last, let p = last.pts.last { return (p.x, p.y, last.z, max(segments.count - 1, 0)) }
        return nil
    }
}

// MARK: - 材料去除模拟

/// 基于高度图的毛坯去除预览：沿刀路把刀半径覆盖的网格单元降到刀底 Z。
/// 这不是 B-Rep 布尔仿真，而是用于快速检查过切、残料和刀路覆盖的 3D 近似。
struct True3DStockSimulation: View {
    let segments: [TPSeg]
    let model: True3DParams
    let toolRadius: Double

    @State private var progress: Double = 0
    @State private var playing = false
    @State private var speed: Double = 1

    private let timer = Timer.publish(every: 0.08, on: .main, in: .common).autoconnect()

    private var totalLength: Double {
        max(segments.reduce(0) { $0 + max($1.len, 0.001) }, 0.001)
    }

    private var duration: Double {
        min(max(totalLength / 80.0, 8.0), 40.0)
    }

    var body: some View {
        VStack(spacing: 0) {
            True3DStockSceneView(
                segments: segments,
                model: model,
                toolRadius: toolRadius,
                progress: progress
            )
            .frame(height: 300)

            HStack(spacing: 8) {
                Button {
                    if progress >= 1 { progress = 0 }
                    playing.toggle()
                } label: {
                    Label(playing ? "暂停" : "去除", systemImage: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 78)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 1.0, green: 0.42, blue: 0.10))

                Button {
                    progress = 0
                    playing = false
                } label: {
                    Image(systemName: "gobackward")
                        .font(.system(size: 13))
                }
                .buttonStyle(.bordered)

                Picker("速度", selection: $speed) {
                    Text("1×").tag(1.0)
                    Text("4×").tag(4.0)
                    Text("16×").tag(16.0)
                }
                .pickerStyle(.segmented)
                .frame(width: 142)

                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 38, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            Slider(value: $progress, in: 0...1)
                .tint(Color(red: 1.0, green: 0.42, blue: 0.10))
                .padding(.horizontal, 12)

            HStack {
                Text("高度图毛坯 · 刀半径 \(String(format: "%.1f", toolRadius * 2)) mm · 拖拽旋转查看残料")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 9)
        }
        .onReceive(timer) { _ in
            guard playing else { return }
            let step = 0.08 * speed / duration
            progress = min(1, progress + step)
            if progress >= 1 { playing = false }
        }
    }
}

private struct True3DStockSceneView: UIViewRepresentable {
    let segments: [TPSeg]
    let model: True3DParams
    let toolRadius: Double
    let progress: Double

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = UIColor(red: 0.95, green: 0.96, blue: 0.97, alpha: 1)
        view.autoenablesDefaultLighting = false
        view.allowsCameraControl = true
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.isPlaying = true

        let scene = SCNScene()
        view.scene = scene

        let maxDim = max(model.width, model.depth, model.height, 20)
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 45
        camera.position = SCNVector3(maxDim * 0.9, -maxDim * 1.15, maxDim * 1.25)
        let lookAt = SCNLookAtConstraint(target: scene.rootNode)
        lookAt.isGimbalLockEnabled = true
        camera.constraints = [lookAt]
        scene.rootNode.addChildNode(camera)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .omni
        key.light?.intensity = 900
        key.position = SCNVector3(maxDim * 0.6, -maxDim * 0.7, maxDim * 1.2)
        scene.rootNode.addChildNode(key)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .ambient
        fill.light?.intensity = 500
        scene.rootNode.addChildNode(fill)

        let stock = SCNNode()
        stock.name = "stock"
        scene.rootNode.addChildNode(stock)

        stock.geometry = buildGeometry(progress: progress)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        view.scene?.rootNode.childNode(withName: "stock", recursively: false)?
            .geometry = buildGeometry(progress: progress)
    }

    private func buildGeometry(progress: Double) -> SCNGeometry {
        let nx = 48
        let ny = 32
        let extra = 6.0
        let stockW = model.width + extra * 2
        let stockD = model.depth + extra * 2
        let minX = -stockW / 2
        let minY = -stockD / 2
        let cellW = stockW / Double(nx)
        let cellD = stockD / Double(ny)
        let pathTop = segments.map(\.z).max() ?? model.height
        let top = max(model.height, pathTop) + 1.5
        let bottom = min(0, segments.map(\.z).min() ?? 0) - 2
        let radius = max(toolRadius, 0.5)

        var heights = [Double](repeating: top, count: nx * ny)
        let total = max(segments.reduce(0) { $0 + max($1.len, 0.001) }, 0.001)
        let target = max(0, min(progress, 1)) * total
        var traveled = 0.0

        func stamp(x: Double, y: Double, z: Double) {
            let ix0 = max(0, Int(floor((x - radius - minX) / cellW)))
            let ix1 = min(nx - 1, Int(ceil((x + radius - minX) / cellW)))
            let iy0 = max(0, Int(floor((y - radius - minY) / cellD)))
            let iy1 = min(ny - 1, Int(ceil((y + radius - minY) / cellD)))
            guard ix0 <= ix1, iy0 <= iy1 else { return }
            for iy in iy0...iy1 {
                for ix in ix0...ix1 {
                    let cx = minX + (Double(ix) + 0.5) * cellW
                    let cy = minY + (Double(iy) + 0.5) * cellD
                    if hypot(cx - x, cy - y) <= radius {
                        heights[iy * nx + ix] = min(heights[iy * nx + ix], z)
                    }
                }
            }
        }

        for seg in segments {
            let len = max(seg.len, 0.001)
            if traveled >= target { break }
            let shown = min(1, (target - traveled) / len)
            let n = max(seg.pts.count - 1, 1)
            let endPos = shown * Double(n)
            for i in 0..<min(Int(endPos) + 1, n) {
                let a = seg.pts[i]
                let b = seg.pts[i + 1]
                let dist = hypot(Double(b.x - a.x), Double(b.y - a.y))
                let steps = max(1, Int(dist / 0.8))
                for s in 0...steps {
                    let t = Double(s) / Double(steps)
                    stamp(
                        x: Double(a.x) + Double(b.x - a.x) * t,
                        y: Double(a.y) + Double(b.y - a.y) * t,
                        z: seg.z
                    )
                }
            }
            traveled += len
        }

        var vertices: [SCNVector3] = []
        vertices.reserveCapacity(nx * ny + (nx + ny) * 4)
        for iy in 0..<ny {
            for ix in 0..<nx {
                let x = minX + (Double(ix) + 0.5) * cellW
                let y = minY + (Double(iy) + 0.5) * cellD
                vertices.append(SCNVector3(Float(x), Float(y), Float(heights[iy * nx + ix])))
            }
        }

        var indices: [UInt32] = []
        indices.reserveCapacity((nx - 1) * (ny - 1) * 6)
        for iy in 0..<(ny - 1) {
            for ix in 0..<(nx - 1) {
                let a = UInt32(iy * nx + ix)
                let b = UInt32(iy * nx + ix + 1)
                let c = UInt32((iy + 1) * nx + ix)
                let d = UInt32((iy + 1) * nx + ix + 1)
                indices.append(contentsOf: [a, b, c, b, d, c])
            }
        }

        // 四周侧壁：让毛坯看起来是实体块，而不是一张悬空高度图。
        func addWall(_ p0: CGPoint, _ p1: CGPoint, _ h0: Double, _ h1: Double) {
            let i0 = vertices.count
            let top0 = Float(h0)
            let top1 = Float(h1)
            vertices.append(SCNVector3(Float(p0.x), Float(p0.y), Float(bottom)))
            vertices.append(SCNVector3(Float(p1.x), Float(p1.y), Float(bottom)))
            vertices.append(SCNVector3(Float(p0.x), Float(p0.y), top0))
            vertices.append(SCNVector3(Float(p1.x), Float(p1.y), top1))
            indices.append(contentsOf: [
                UInt32(i0), UInt32(i0 + 1), UInt32(i0 + 2),
                UInt32(i0 + 1), UInt32(i0 + 3), UInt32(i0 + 2)
            ])
        }

        func point(ix: Int, iy: Int) -> CGPoint {
            CGPoint(
                x: minX + (Double(ix) + 0.5) * cellW,
                y: minY + (Double(iy) + 0.5) * cellD
            )
        }
        for ix in 0..<(nx - 1) {
            let i0 = ix, i1 = ix + 1
            addWall(point(ix: i0, iy: 0), point(ix: i1, iy: 0), heights[i0], heights[i1])
        }
        for ix in 0..<(nx - 1) {
            let i0 = (ny - 1) * nx + ix, i1 = i0 + 1
            addWall(point(ix: ix, iy: ny - 1), point(ix: ix + 1, iy: ny - 1), heights[i0], heights[i1])
        }
        for iy in 0..<(ny - 1) {
            let i0 = iy * nx, i1 = (iy + 1) * nx
            addWall(point(ix: 0, iy: iy), point(ix: 0, iy: iy + 1), heights[i0], heights[i1])
        }
        for iy in 0..<(ny - 1) {
            let i0 = iy * nx + nx - 1, i1 = (iy + 1) * nx + nx - 1
            addWall(point(ix: nx - 1, iy: iy), point(ix: nx - 1, iy: iy + 1), heights[i0], heights[i1])
        }

        let source = SCNGeometrySource(vertices: vertices)
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        let geometry = SCNGeometry(sources: [source], elements: [element])
        let material = SCNMaterial()
        material.diffuse.contents = UIColor(red: 0.72, green: 0.74, blue: 0.76, alpha: 1)
        material.metalness.contents = 0.15
        material.roughness.contents = 0.75
        material.isDoubleSided = true
        geometry.materials = [material]
        return geometry
    }
}

// MARK: - G 代码页

struct True3DGCodeScreen: View {
    let code: String
    let fileURL: URL
    @State private var copied = false

    var body: some View {
        True3DCodeTextView(text: code)
            .ignoresSafeArea(.container, edges: .bottom)
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

/// 用 UITextView 而不是 SwiftUI Text 承载完整 G 代码。
/// SwiftUI 的 Text 会对整段字符串做排版，几万行时主线程会卡死；UITextView 的
/// TextKit 滚动容器可以按需布局，几十万字符也能正常打开。
private struct True3DCodeTextView: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = true
        view.alwaysBounceVertical = true
        view.backgroundColor = .secondarySystemBackground
        view.textColor = .label
        view.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        view.textContainerInset = UIEdgeInsets(top: 14, left: 10, bottom: 24, right: 10)
        view.textContainer.lineFragmentPadding = 0
        view.contentInsetAdjustmentBehavior = .never
        view.text = text
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if view.text != text {
            view.text = text
        }
    }
}
