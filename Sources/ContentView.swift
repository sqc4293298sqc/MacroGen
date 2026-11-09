import SwiftUI
import Foundation

struct ContentView: View {
    @State private var spec = PocketSpec()
    @State private var result: String = ""
    @State private var manual: String = ""
    @State private var fileURL: URL? = nil
    @State private var showResult = false
    @State private var showRef = false
    @State private var showTol = false
    @State private var showThread = false
    @State private var showFeed = false
    @State private var showImport = false

    private var toolpathImage: String {
        switch spec.mode {
        case .pocket: return "ToolpathPocket"
        case .taper: return "ToolpathTaper"
        case .face: return "ToolpathFace"
        case .spiral: return "ToolpathSpiral"
        case .key: return "ToolpathKey"
        case .outer: return "ToolpathOuter"
        }
    }

    private var toolpathText: String {
        switch spec.mode {
        case .pocket: return "外圈一圈圈向内缩，逐层把腔掏空，最后 G41 精修侧壁"
        case .taper: return "一圈圈逐渐缩小的圆弧沿锥面盘旋下到底"
        case .face: return "Y 向往复走平行线，一层走满整张面再下一层"
        case .spiral: return "刀心圆上 G3 连续下降，每圈吃一层"
        case .key: return "沿槽长来回走，两端由刀径形成圆弧；槽宽大于刀径时自动分行"
        case .outer: return "贴工件轮廓外侧顺时针绕，一圈一圈往下，G41 把刀偏在外面"
        }
    }

    private enum SyncSource { case small, ratio, angle }
    @State private var syncSource: SyncSource = .small

    var body: some View {
        NavigationStack {
            Form {
                Section("加工类型") {
                    Picker("类型", selection: $spec.mode) {
                        ForEach(MachiningMode.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("刀路示意") {
                    Image(toolpathImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(height: 190)
                    Text(toolpathText)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                if spec.mode == .key {
                    Section("键槽参数 (mm)") {
                        numRow("槽长 L（含圆弧）", value: $spec.keyLength)
                        numRow("槽宽 W", value: $spec.keyWidth)
                        numRow("总深 H", value: $spec.depth)
                    }
                }

                if spec.mode == .spiral {
                    Section("螺旋参数 (mm)") {
                        numRow("圆直径 D", value: $spec.spiralDia)
                        numRow("去量 H", value: $spec.depth)
                    }
                }

                if spec.mode == .outer {
                    Section("工件外形尺寸 (mm)") {
                        numRow("长 L", value: $spec.length)
                        numRow("宽 W", value: $spec.width)
                        numRow("总深 H", value: $spec.depth)
                    }
                }

                if spec.mode == .pocket || spec.mode == .face {
                    Section(spec.mode == .face ? "平面尺寸 (mm)" : "型腔尺寸 (mm)") {
                        numRow("长 L", value: $spec.length)
                        numRow("宽 W", value: $spec.width)
                        numRow(spec.mode == .face ? "去量 H" : "深 D", value: $spec.depth)
                    }
                }

                if spec.mode == .pocket || spec.mode == .outer {
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
                }

                if spec.mode == .taper {
                    Section("锥孔参数 (mm)") {
                        numRow("大头 D", value: $spec.taperDia)
                        numRow("小头 d", value: Binding(
                            get: { spec.taperDiaSmall },
                            set: { self.spec.taperDiaSmall = $0; self.syncTaper(.small) }
                        ))
                        numRow("深度 H", value: Binding(
                            get: { spec.taperDepth },
                            set: { self.spec.taperDepth = $0; self.syncTaper(self.syncSource) }
                        ))
                        numRow("锥度 1:N", value: Binding(
                            get: { spec.taperRatio },
                            set: { self.spec.taperRatio = $0; self.syncTaper(.ratio) }
                        ))
                        numRow("角度 °", value: Binding(
                            get: { spec.taperAngle },
                            set: { self.spec.taperAngle = $0; self.syncTaper(.angle) }
                        ))
                        Text("大小头定锥度；锥度与角度也可直接改，其余自动换算")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("坐标系") {
                    Picker("工件坐标系", selection: $spec.coord) {
                        ForEach([54, 55, 56, 57, 58, 59], id: \.self) { c in
                            Text("G\(c)").tag(c)
                        }
                    }
                    numRow("中心 X", value: $spec.cx)
                    numRow("中心 Y", value: $spec.cy)
                    Text("中心为孔在该坐标系下的位置，程序用 G52 平移；Z0 = 工件顶面")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("刀具与切削") {
                    numRow("刀具直径", value: $spec.toolDia)
                    numRow("刀尖 R（平底刀填 0）", value: $spec.toolCornerR)
                    numRow("每层切深 AP", value: $spec.stepDown)
                    if spec.mode == .pocket {
                        numRow("行距 AE", value: $spec.stepOver)
                    }
                    if spec.mode == .face {
                        Text("飞面行距固定取刀具直径的 75%，不用填")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    intRow("转速 S", value: $spec.spindle)
                    intRow("进给 F", value: $spec.feed)
                    numRow("安全高度 Z", value: $spec.safeZ)
                    intRow("刀补号 H / D", value: $spec.hNo)
                }

                if spec.mode == .pocket {
                    Section("输出") {
                        Toggle("精简写法（,R / ,C 自动倒圆倒角）", isOn: $spec.compact)
                        Text("0i-MF 需参数 No.3405 第 4 位（CCR）= 1")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
                        showRef = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("编程代码大全", systemImage: "book")
                            Spacer()
                        }
                    }

                    Button {
                        showTol = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("尺寸公差查询", systemImage: "ruler")
                            Spacer()
                        }
                    }

                    Button {
                        showThread = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("丝锥底孔查询", systemImage: "circle.hexagongrid")
                            Spacer()
                        }
                    }

                    Button {
                        showFeed = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("刀具转速进给", systemImage: "gauge.with.dots.needle.bottom.50percent")
                            Spacer()
                        }
                    }

                    Button {
                        showImport = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("拍照识别程序 · 导入并模拟", systemImage: "camera.viewfinder")
                            Spacer()
                        }
                    }

                    Button {
                        self.build()
                    } label: {
                        HStack {
                            Spacer()
                            Label("生成宏程序 · 含刀路仿真", systemImage: "function")
                            Spacer()
                        }
                        .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(!spec.canGenerate)
                }
            }
            .navigationTitle("宏程序生成器")
            .sheet(isPresented: $showRef) {
                CodeRefView()
            }
            .sheet(isPresented: $showTol) {
                ToleranceView()
            }
            .sheet(isPresented: $showThread) {
                ThreadView()
            }
            .sheet(isPresented: $showFeed) {
                ToolFeedView()
            }
            .sheet(isPresented: $showImport) {
                ImportView()
            }
            .navigationDestination(isPresented: $showResult) {
                ResultView(code: result, manual: manual, fileURL: fileURL, spec: spec)
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

    private func syncTaper(_ src: SyncSource) {
        syncSource = src
        let big = spec.taperDia
        let depth = spec.taperDepth
        guard big > 0, depth > 0 else { return }
        var small = spec.taperDiaSmall
        switch src {
        case .small:
            small = spec.taperDiaSmall
        case .ratio:
            guard spec.taperRatio > 0 else { return }
            small = big - depth / spec.taperRatio
        case .angle:
            guard spec.taperAngle > 0, spec.taperAngle < 89 else { return }
            small = big - depth * tan(spec.taperAngle * .pi / 180)
        }
        guard small > 0, big > small else { return }
        if src != .small { spec.taperDiaSmall = small }
        if src != .ratio { spec.taperRatio = depth / (big - small) }
        if src != .angle {
            spec.taperAngle = atan((big - small) / depth) * 180 / .pi
        }
    }

    private func build() {
        let code = GCodeGenerator.generate(spec)
        let name: String
        if spec.mode == .taper {
            name = "taper_D\(Int(spec.taperDia))d\(Int(spec.taperDiaSmall))_H\(Int(spec.taperDepth)).nc"
        } else if spec.mode == .face {
            name = "face_L\(Int(spec.length))_W\(Int(spec.width))_H\(Int(spec.depth)).nc"
        } else if spec.mode == .spiral {
            name = "spiral_D\(Int(spec.spiralDia))_H\(Int(spec.depth)).nc"
        } else if spec.mode == .key {
            name = "key_L\(Int(spec.keyLength))_W\(Int(spec.keyWidth))_H\(Int(spec.depth)).nc"
        } else if spec.mode == .outer {
            name = "outer_L\(Int(spec.length))_W\(Int(spec.width))_H\(Int(spec.depth)).nc"
        } else {
            name = "pocket_L\(Int(spec.length))_W\(Int(spec.width))_D\(Int(spec.depth)).nc"
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? code.write(to: url, atomically: true, encoding: .utf8)
        result = code
        manual = GCodeGenerator.manual(spec)
        fileURL = url
        showResult = true
    }
}

struct ResultView: View {
    let code: String
    let manual: String
    let fileURL: URL?
    let spec: PocketSpec
    @State private var didCopy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(code)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)

                Text("刀路仿真（俯视 / 立体 / 倍速）")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)

                ToolpathSimView(spec: spec, embedded: true, canvasHeight: 220)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 8)

                NavigationLink {
                    SimScreen(code: code, spec: spec)
                } label: {
                    HStack {
                        Image(systemName: "play.circle.fill")
                        Text("程序模拟 › 按 G 代码逐段走刀")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity)
                    .background(Color.orange)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)

                DisclosureGroup("使用说明（每个变量怎么改）") {
                    Text(manual)
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                }
                .padding(12)
            }
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
