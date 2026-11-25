import SwiftUI

/// 本地文字生成 3D：规则解析 → True3DParams → 现有 SceneKit/OCCT 工作台。
/// 不调用后端、不联网；支持的是常用 CNC 特征，不是任意自然语言。
struct TextTo3DScreen: View {
    @SwiftUI.Environment(\.dismiss) private var dismiss
    @State private var prompt = "120×80×30，18宽三级阶梯槽，深6/12/18"
    @State private var parsed: TextTo3DParseResult?
    @State private var errorText: String?
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
            if let parsed {
                True3DModelScreen(initialParams: parsed.params) {
                    show3D = false
                    // 先让 3D 工作台退出，再把“文字生成”页一并退回首页。
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
            Text("本地规则解析，不联网；先生成参数化模型，再进 3D 工作台微调。")
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
        Button {
            editorFocused = false
            parse()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                Text("本地解析")
                    .fontWeight(.semibold)
                Spacer()
                Text("不联网")
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
            Text("矩形/圆形毛坯、三级阶梯槽、法兰、方腔、圆腔、通孔、凸台、外轮廓圆角。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("写法：尺寸用 120×80×30；直径用 Ø30 或 D30；圆角用 R2.5；槽深用 6/12/18。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("任意自然语言、曲面/螺纹/复杂装配尚未支持；这些可以进 3D 工作台继续做。")
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

    private func parse() {
        parsed = nil
        errorText = nil
        let result = LocalTextTo3DParser.parse(prompt)
        switch result {
        case .success(let value):
            parsed = value
        case .failure(let error):
            errorText = error.localizedDescription
        }
    }
}
