import SwiftUI

struct ContentView: View {
    @State private var spec = PocketSpec()
    @State private var result: String = ""
    @State private var fileURL: URL? = nil
    @State private var showResult = false
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Form {
                Section("型腔尺寸 (mm)") {
                    numRow("长 L", value: $spec.length)
                    numRow("宽 W", value: $spec.width)
                    numRow("深 D", value: $spec.depth)
                }

                Section("四角形状") {
                    Picker("类型", selection: $spec.cornerType) {
                        ForEach(CornerType.allCases) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)

                    if spec.cornerType != .square {
                        numRow(spec.cornerType == .radius ? "圆角 R" : "倒角 C", value: $spec.cornerValue)
                    }
                }

                Section("刀具与切削") {
                    numRow("刀具直径", value: $spec.toolDia)
                    numRow("每层切深 AP", value: $spec.stepDown)
                    numRow("行距 AE", value: $spec.stepOver)
                    intRow("转速 S", value: $spec.spindle)
                    intRow("进给 F", value: $spec.feed)
                    numRow("安全高度 Z", value: $spec.safeZ)
                    intRow("刀补号 D", value: $spec.compNo)
                }

                if !spec.issues.isEmpty {
                    Section("检查") {
                        ForEach(spec.issues, id: \.self) { t in
                            Label(t, systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Section {
                    Button {
                        build()
                    } label: {
                        HStack {
                            Spacer()
                            Label("生成宏程序", systemImage: "function")
                            Spacer()
                        }
                    }
                    .disabled(!spec.canGenerate)
                }
            }
            .navigationTitle("宏程序生成器")
            .navigationDestination(isPresented: $showResult) {
                ResultView(code: result, fileURL: fileURL)
            }
        }
    }

    private func numRow(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 110)
        }
    }

    private func intRow(_ title: String, value: Binding<Int>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 110)
        }
    }

    private func build() {
        let code = GCodeGenerator.generate(spec)
        let name = "pocket_L\(Int(spec.length))_W\(Int(spec.width))_D\(Int(spec.depth)).nc"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? code.write(to: url, atomically: true, encoding: .utf8)
        result = code
        fileURL = url
        showResult = true
    }
}

struct ResultView: View {
    let code: String
    let fileURL: URL?
    @State private var didCopy = false

    var body: some View {
        ScrollView {
            Text(code)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .navigationTitle("宏程序")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    UIPasteboard.general.string = code
                    didCopy = true
                } label: {
                    Label(didCopy ? "已复制" : "复制", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if let url = fileURL {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }
}
