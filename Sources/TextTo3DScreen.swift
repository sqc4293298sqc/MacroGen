import SwiftUI

/// 本地文字生成 3D：规则解析 → True3DParams → 现有 SceneKit/OCCT 工作台。
/// 不调用后端、不联网；支持的是常用 CNC 特征，不是任意自然语言。
struct TextTo3DScreen: View {
    @SwiftUI.Environment(\.dismiss) private var dismiss
    @State private var prompt = "120×80×30，18宽三级阶梯槽，深6/12/18"
    @State private var parsed: TextTo3DParseResult?
    @State private var errorText: String?
    @State private var cloudResult: CloudCADJobStatus?
    @State private var cloudStepURL: URL?
    @State private var cloudParams: True3DParams?
    @State private var cloudBusy = false
    @State private var cloudProgress = ""
    @State private var cloudErrorText: String?
    @State private var show3D = false
    @FocusState private var editorFocused: Bool

    private let examples = [
        "120×80×30，18宽三级阶梯槽，深6/12/18",
        "80×80×10，中心Ø30，6个Ø6孔，分布圆Ø60，R1.5",
        "100×60×20，中间40×30方腔深10，R3",
        "Ø80×20 圆块，中心Ø30通孔",
        "120×80×30，Ø30凸台高8"
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                exampleRow
                editor
                parseButton

                if let errorText {
                    messageCard(
                        title: "没有生成",
                        text: errorText,
                        color: .red,
                        icon: "exclamationmark.triangle.fill"
                    )
                }

                if let cloudErrorText {
                    messageCard(
                        title: "云端没有生成",
                        text: cloudErrorText,
                        color: .red,
                        icon: "wifi.exclamationmark"
                    )
                }

                if let cloudResult {
                    cloudResultCard(cloudResult)
                    generateButton
                }

                if let parsed {
                    resultCard(parsed)
                    generateButton
                }

                help
            }
            .padding(16)
            .padding(.bottom, 30)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("文字生成 3D")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $show3D) {
            if let cloudStepURL {
                True3DModelScreen(initialParams: cloudParams, initialSTEPURL: cloudStepURL) {
                    show3D = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                        dismiss()
                    }
                }
            } else if let parsed {
                True3DModelScreen(initialParams: parsed.params) {
                    show3D = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                        dismiss()
                    }
                }
            } else {
                Text("没有解析结果")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("说尺寸和特征，直接生成实体")
                .font(.system(size: 22, weight: .bold))
            Text("云端模板解析，联网生成 STEP；也可以切本地规则离线解析。")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var exampleRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(examples, id: \.self) { example in
                    Button {
                        prompt = example
                        parsed = nil
                        errorText = nil
                    } label: {
                        Text(example)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color(red: 0.10, green: 0.42, blue: 0.42))
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                Color(red: 0.90, green: 0.97, blue: 0.96),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if prompt.isEmpty {
                Text("例如：120×80×30，18宽三级阶梯槽，深6/12/18")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 16)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $prompt)
                .focused($editorFocused)
                .font(.system(size: 16))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 150)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
        }
    }

    private var parseButton: some View {
        VStack(spacing: 8) {
            Button {
                editorFocused = false
                parseCloud()
            } label: {
                HStack(spacing: 8) {
                    if cloudBusy {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "cloud.fill")
                    }
                    Text(cloudBusy ? (cloudProgress.isEmpty ? "云端生成中…" : cloudProgress) : "云端生成")
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Spacer()
                    Text("联网")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 48)
                .background(
                    Color(red: 0.10, green: 0.48, blue: 0.46),
                    in: RoundedRectangle(cornerRadius: 14)
                )
            }
            .buttonStyle(.plain)
            .disabled(cloudBusy || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button {
                editorFocused = false
                parse()
            } label: {
                Text("本地快速解析（不联网）")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(cloudBusy)
        }
    }

    private func cloudResultCard(_ status: CloudCADJobStatus) -> some View {
        let stock = status.drawing?.stock
        let dims: String
        if let stock, let l = stock.length, let w = stock.width, let h = stock.height {
            dims = "\(fmt(l))×\(fmt(w))×\(fmt(h)) mm"
        } else {
            dims = "云端 STEP"
        }
        let featureCount = status.drawing?.features?.count ?? 0
        let faces = status.metrics?.faces
        let triangles = status.metrics?.triangles
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "cloud.fill")
                    .foregroundStyle(Color(red: 0.10, green: 0.55, blue: 0.44))
                Text("云端已生成")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Text("STEP")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Text("毛坯：\(dims)")
                .font(.system(size: 13))
            Text("特征：\(featureCount) 个" + (faces.map { " · 面 \($0)" } ?? "") + (triangles.map { " · 三角 \($0)" } ?? ""))
                .font(.system(size: 13))
                .foregroundStyle(.primary)
            if let notes = status.drawing?.notes, !notes.isEmpty {
                Divider()
                ForEach(notes, id: \.self) { note in
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                        Text(note)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Text("解析方式：云端模板，联网")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(red: 0.10, green: 0.48, blue: 0.46).opacity(0.18), lineWidth: 1)
        )
    }

    private func resultCard(_ result: TextTo3DParseResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Color(red: 0.10, green: 0.55, blue: 0.44))
                Text("已解析")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Text("\(result.params.features.count) 个特征")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            ForEach(result.summary, id: \.self) { line in
                HStack(alignment: .top, spacing: 7) {
                    Circle()
                        .fill(Color(red: 0.10, green: 0.48, blue: 0.46))
                        .frame(width: 5, height: 5)
                        .padding(.top, 6)
                    Text(line)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !result.warnings.isEmpty {
                Divider()
                ForEach(result.warnings, id: \.self) { warning in
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                        Text(warning)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(red: 0.10, green: 0.48, blue: 0.46).opacity(0.18), lineWidth: 1)
        )
    }

    private var generateButton: some View {
        Button {
            show3D = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "cube.transparent")
                Text("进入 3D 工作台")
                    .fontWeight(.semibold)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .opacity(0.8)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 50)
            .background(
                Color(red: 0.90, green: 0.42, blue: 0.16),
                in: RoundedRectangle(cornerRadius: 14)
            )
        }
        .buttonStyle(.plain)
    }

    private var help: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("当前支持")
                .font(.system(size: 13, weight: .semibold))
            Text("云端：矩形/圆形/圆管毛坯、三级阶梯槽、法兰、方腔、圆腔、通孔、沉头/锥沉、键槽、凸台、圆锥/球面、M3–M20 螺纹、孔距阵列、外轮廓圆角/倒角。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("写法：尺寸用 120×80×30；直径用 Ø30 或 D30；圆角用 R2.5；槽深用 6/12/18。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("云端解析仍是模板/关键词级，不承诺任意自然语言语义理解；断网时可用本地快速解析。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private func messageCard(title: String, text: String, color: Color, icon: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func parseCloud() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            cloudErrorText = "请输入零件描述"
            return
        }
        parsed = nil
        errorText = nil
        cloudResult = nil
        cloudStepURL = nil
        cloudParams = nil
        cloudErrorText = nil
        cloudProgress = "正在提交…"
        cloudBusy = true
        Task { @MainActor in
            do {
                let created = try await CloudCADClient.createTextJob(prompt: text)
                cloudProgress = "云端生成中…"
                let status = try await CloudCADClient.waitForJob(id: created.id)
                guard let stepPath = status.artifacts?["step"] else {
                    throw CloudCADClientError.missingSTEP
                }
                cloudProgress = "下载 STEP…"
                let url = try await CloudCADClient.downloadSTEP(path: stepPath)
                cloudStepURL = url
                cloudParams = status.drawing?.true3DParams()
                cloudResult = status
                cloudProgress = ""
            } catch {
                cloudErrorText = error.localizedDescription
                cloudProgress = ""
            }
            cloudBusy = false
        }
    }

    private func parse() {
        parsed = nil
        errorText = nil
        cloudResult = nil
        cloudStepURL = nil
        cloudParams = nil
        cloudErrorText = nil
        let result = LocalTextTo3DParser.parse(prompt)
        switch result {
        case .success(let value):
            parsed = value
        case .failure(let error):
            errorText = error.localizedDescription
        }
    }

    private func fmt(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.0001 { return String(format: "%.0f", value) }
        return String(format: "%.1f", value)
    }
}
