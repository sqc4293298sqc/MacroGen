import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 汉字刻字：和安卓同一套参数与 G 代码逻辑。
struct TextEngraveScreen: View {
    @State private var text = "汉字刻字"
    @State private var fontIndex = 0
    @State private var bold = false
    @State private var charW = "12"
    @State private var charH = "12"
    @State private var perCharW = ""
    @State private var perCharH = ""
    @State private var spacing = "2"
    @State private var totalW = "0"
    @State private var totalH = "0"
    @State private var depth = "1.5"
    @State private var stepDown = "0.5"
    @State private var toolDia = "3"
    @State private var feed = "300"
    @State private var rpm = "8000"
    @State private var safeZ = "10"
    @State private var hNo = "1"
    @State private var originX = "0"
    @State private var originY = "0"

    @State private var plan = TextEngravePlan()
    @State private var resultCode = ""
    @State private var resultPlan = TextEngravePlan()
    @State private var resultParams = TextEngraveParams()
    @State private var showResult = false
    @State private var errorText = ""

    private var params: TextEngraveParams {
        var p = TextEngraveParams()
        p.text = text
        p.fontIndex = fontIndex
        p.bold = bold
        p.fontName = TextEngraveEngine.fonts[max(0, min(fontIndex, TextEngraveEngine.fonts.count - 1))]
        p.charW = max(0.5, num(charW, 12))
        p.charH = max(0.5, num(charH, 12))
        p.charWidths = parseList(perCharW)
        p.charHeights = parseList(perCharH)
        p.spacing = max(0, num(spacing, 2))
        p.totalW = max(0, num(totalW, 0))
        p.totalH = max(0, num(totalH, 0))
        p.depth = max(0, num(depth, 1.5))
        p.stepDown = max(0.02, num(stepDown, 0.5))
        p.toolDia = max(0.1, num(toolDia, 3))
        p.feed = max(1, Int(num(feed, 300)))
        p.rpm = max(100, Int(num(rpm, 8000)))
        p.safeZ = num(safeZ, 10)
        p.hNo = max(0, Int(num(hNo, 1)))
        p.coord = 54
        p.originX = num(originX, 0)
        p.originY = num(originY, 0)
        return p
    }

    private var signature: String {
        [text, String(fontIndex), String(bold), charW, charH, perCharW, perCharH,
         spacing, totalW, totalH, depth, stepDown, toolDia, feed, rpm, safeZ,
         hNo, originX, originY].joined(separator: "|")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                card("刻字内容", "中文、英文、数字；建议一行不超过 12 个字") {
                    TextField("输入要刻的字", text: $text)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 17))

                    HStack {
                        Text("字体").font(.system(size: 14))
                        Spacer()
                        Picker("字体", selection: $fontIndex) {
                            ForEach(0..<TextEngraveEngine.fonts.count, id: \.self) { i in
                                Text(TextEngraveEngine.fonts[i]).tag(i)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }

                    Toggle("加粗", isOn: $bold)
                        .font(.system(size: 13))
                }

                card("字距与尺寸", "单字外框 + 字距；总尺寸填 0 自动计算") {
                    numRow("单字宽 W", $charW)
                    numRow("单字高 H", $charH)
                    numRow("字距", $spacing)
                    numRow("总宽（0=自动）", $totalW)
                    numRow("总高（0=自动）", $totalH)
                }

                card("逐字尺寸（可选）", "按可见字顺序用逗号分隔；留空则用上面的单字宽/高") {
                    listRow("逐字宽 W", $perCharW, hint: "如 12,10,14")
                    listRow("逐字高 H", $perCharH, hint: "如 12,12,16")
                }

                card("深度与刀具", "Z0 为工件顶面；轮廓刻线，不清腔") {
                    numRow("总深 D", $depth)
                    numRow("每层切深 AP", $stepDown)
                    numRow("刀径 Ø", $toolDia)
                    numRow("进给 F", $feed, keyboard: .numberPad)
                    numRow("转速 S", $rpm, keyboard: .numberPad)
                    numRow("安全高度 Z", $safeZ)
                    numRow("刀补号 H", $hNo, keyboard: .numberPad)
                    numRow("文字中心 X", $originX)
                    numRow("文字中心 Y", $originY)
                }

                card("轮廓预览", "和生成的 G 代码使用同一份轮廓") {
                    TextEngravePreviewView(plan: plan)
                        .frame(height: 230)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    Text(TextEngraveEngine.summary(plan: plan, params: params)
                         + " · 单字 \(TextEngraveEngine.fmt(params.charW, 2))×\(TextEngraveEngine.fmt(params.charH, 2))"
                         + (perCharItems > 0 ? " · 逐字 \(perCharItems) 项" : ""))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                if !errorText.isEmpty {
                    Text(errorText)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }

                Button {
                    generate()
                } label: {
                    Text("生成汉字刻字程序 · 含轮廓仿真")
                        .font(.system(size: 15, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 1.0, green: 0.42, blue: 0.10))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .padding(.bottom, 30)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("汉字刻字")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refresh() }
        .onChange(of: signature) { _ in refresh() }
        .sheet(isPresented: $showResult) {
            TextEngraveResultView(code: resultCode,
                                  plan: resultPlan,
                                  params: resultParams)
        }
    }

    private var perCharItems: Int {
        max(params.charWidths.count, params.charHeights.count)
    }

    private func refresh() {
        let p = params
        let built = TextEngraveEngine.build(params: p)
        plan = built
        if let error = built.error {
            errorText = error
        } else {
            errorText = ""
        }
    }

    private func generate() {
        refresh()
        guard plan.error == nil, !plan.contours.isEmpty else { return }
        resultParams = params
        resultPlan = plan
        resultCode = TextEngraveEngine.code(plan: plan, params: params)
        showResult = true
    }

    private func num(_ s: String, _ fallback: CGFloat) -> CGFloat {
        let cleaned = s.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        return CGFloat(Double(cleaned) ?? Double(fallback))
    }

    private func parseList(_ s: String) -> [CGFloat] {
        let parts = s.components(separatedBy: CharacterSet(charactersIn: ",，、 "))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.compactMap {
            Double($0.replacingOccurrences(of: ",", with: ".")).map(CGFloat.init)
        }
    }

    private func card<Content: View>(_ title: String, _ subtitle: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            content()
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func numRow(_ title: String, _ binding: Binding<String>,
                        keyboard: UIKeyboardType = .decimalPad) -> some View {
        HStack {
            Text(title).font(.system(size: 13.5))
            Spacer()
            TextField("", text: binding)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 14, design: .monospaced))
                .frame(width: 120)
                .textFieldStyle(.roundedBorder)
        }
        .frame(minHeight: 30)
    }

    private func listRow(_ title: String, _ binding: Binding<String>, hint: String) -> some View {
        HStack {
            Text(title).font(.system(size: 13.5))
            Spacer()
            TextField(hint, text: binding)
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 13, design: .monospaced))
                .frame(width: 180)
                .textFieldStyle(.roundedBorder)
        }
        .frame(minHeight: 30)
    }
}

/// 轮廓预览：Plan 用机床坐标 Y 向上，这里转成屏幕 Y 向下绘制。
struct TextEngravePreviewView: View {
    let plan: TextEngravePlan

    var body: some View {
        ZStack {
            Color(.secondarySystemBackground)
            if let error = plan.error {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(16)
            } else {
                Canvas { context, size in
                    let spanX = max(0.01, plan.maxX - plan.minX)
                    let spanY = max(0.01, plan.maxY - plan.minY)
                    let pad: CGFloat = 16
                    let scale = min((size.width - pad * 2) / spanX,
                                    (size.height - pad * 2 - 16) / spanY)
                    let ox = size.width / 2 - (plan.minX + plan.maxX) / 2 * scale
                    let oy = (size.height - 16) / 2 + (plan.minY + plan.maxY) / 2 * scale
                    for contour in plan.contours {
                        var path = Path()
                        for (i, p) in contour.pts.enumerated() {
                            let pt = CGPoint(x: ox + p.x * scale, y: oy - p.y * scale)
                            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                        }
                        context.stroke(path,
                                       with: .color(Color(red: 0.14, green: 0.20, blue: 0.27)),
                                       lineWidth: 1.2)
                    }
                }
                VStack {
                    Spacer()
                    HStack {
                        Text("总 \(TextEngraveEngine.fmt(plan.width, 2)) × \(TextEngraveEngine.fmt(plan.height, 2)) mm · \(plan.contours.count) 条轮廓")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(8)
                }
            }
        }
    }
}

/// 结果页：复制、分享、保存 .nc、进入现有模拟器。
struct TextEngraveResultView: View {
    let code: String
    let plan: TextEngravePlan
    let params: TextEngraveParams

    @Environment(\.dismiss) private var dismiss
    @State private var showExporter = false
    @State private var exportDoc: TextFileDocument? = nil
    @State private var saveMessage = ""

    private var simSpec: PocketSpec {
        var s = PocketSpec()
        s.length = Double(plan.width)
        s.width = Double(plan.height)
        s.depth = Double(params.depth)
        s.toolDia = Double(params.toolDia)
        s.stepDown = Double(params.stepDown)
        s.spindle = params.rpm
        s.feed = params.feed
        s.safeZ = Double(params.safeZ)
        s.hNo = params.hNo
        s.coord = params.coord
        return s
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(TextEngraveEngine.summary(plan: plan, params: params)
                         + "\n\(code.split(separator: "\n").count) 行 · \(code.count) 字符")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: true) {
                        Text(code)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 330)
                    .background(Color(red: 0.067, green: 0.102, blue: 0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(Color(red: 0.84, green: 0.87, blue: 0.91))

                    HStack(spacing: 8) {
                        Button {
                            UIPasteboard.general.string = code
                            saveMessage = "已复制到剪贴板"
                        } label: {
                            Label("复制", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)

                        ShareLink(item: code) {
                            Label("分享", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            exportDoc = TextFileDocument(text: code)
                            showExporter = true
                        } label: {
                            Label("保存", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.bordered)
                    }

                    NavigationLink {
                        SimScreen(code: code, spec: simSpec)
                    } label: {
                        Label("程序仿真", systemImage: "play.circle")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 1.0, green: 0.42, blue: 0.10))

                    if !saveMessage.isEmpty {
                        Text(saveMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    DisclosureGroup("用法说明") {
                        Text(TextEngraveEngine.manual(params: params))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                    }
                    .font(.system(size: 13, weight: .semibold))
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("汉字刻字程序")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .fileExporter(isPresented: $showExporter,
                          document: exportDoc,
                          contentType: .plainText,
                          defaultFilename: "hanzi_\(plan.charCount)_D\(TextEngraveEngine.fmt(params.depth, 2))") { result in
                switch result {
                case .success(let url): saveMessage = "已保存 \(url.lastPathComponent)"
                case .failure(let error): saveMessage = "保存失败：\(error.localizedDescription)"
                }
            }
        }
    }
}

/// 保存 .nc 用的小文本文件。
struct TextFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text = ""

    init(text: String = "") { self.text = text }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            text = String(decoding: data, as: UTF8.self)
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
