import SwiftUI
import Foundation

struct ContentView: View {
    init(mode: MachiningMode = .pocket) {
        var s = PocketSpec()
        s.mode = mode
        if mode == .oblique {
            s.spiralDia = 100
            s.toolDia = 50
            s.depth = 80
            s.stepDown = 0.5
            s.obliqueAngle = 70
        }
        if mode == .thread {
            s.toolDia = 26
            s.threadDia = 30
            s.threadPitch = 3.5
            s.threadLength = 59.5
            s.threadTop = 2
            s.threadRadialStep = 0.5
            s.holeCount = 8
            s.holePatternRadius = 100
            s.holeStartAngle = 22.5
            s.holeAngleStep = 45
        }
        if mode == .taperHelix {
            s.taperDia = 100
            s.taperDiaSmall = 60
            s.taperDepth = 30
            s.toolDia = 50
            s.stepDown = 0.2
            s.taperRatio = 30 / 40
            s.taperAngle = atan(40 / 30) * 180 / .pi
        }
        if mode == .arcSurface {
            s.arcKind = .inner
            s.arcTravel = 122
            s.arcRadius = 25
            s.arcStraightDepth = 25
            s.arcSweep = 90
            s.arcAngleStep = 3
            s.arcCenterY = -70
            s.length = 200
            s.width = 100
            s.depth = 50
            s.toolDia = 40
            s.toolCornerR = 0
        }
        _spec = State(initialValue: s)
    }

    @State private var spec = PocketSpec()
    @State private var format: ProgramFormat = .macro
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
        case .taperHelix: return "ToolpathTaper"
        case .face: return "ToolpathFace"
        case .spiral: return "ToolpathSpiral"
        case .oblique: return "ToolpathSpiral"
        case .thread: return "ToolpathSpiral"
        case .key: return "ToolpathKey"
        case .outer: return "ToolpathOuter"
        case .innerChamfer: return "ToolpathChamfer"
        case .odCham: return "ToolpathODCham"
        case .rCorner:
            switch spec.rKind {
            case .outerCylinder: return "ToolpathODCham"
            case .hole: return "ToolpathChamfer"
            case .outerRect: return "ToolpathOuter"
            case .slot: return "ToolpathKey"
            }
        case .arcSurface: return "ToolpathFace"
        }
    }

    private var toolpathText: String {
        switch spec.mode {
        case .pocket: return "外圈一圈圈向内缩，逐层把腔掏空，最后 G41 精修侧壁"
        case .taper: return "沿锥面连续螺旋下到底，一圈降一层，中途不抬刀"
        case .taperHelix: return "刀心半径从大头到小头连续缩小，Z 逐度下降，到底再走一整圈平底"
        case .face: return "Y 向往复走平行线，一层走满整张面再下一层；斜面按角度逐层偏移"
        case .spiral: return spec.holeCount > 1 ? "按圆周分布逐孔螺旋下刀，每个孔一圈降一层，孔间抬刀转移" : "刀心圆上 G3 连续下降，一圈降一层，中途不抬刀"
        case .oblique: return "G68 把孔轴在 XY 平面内旋转，X 逐度进给，YZ 走圆；到底再走一圈平底"
        case .thread: return "按圆周分布逐孔下刀，先径向进刀，再 G03 螺旋上升一个螺距一圈"
        case .key: return "沿槽长来回走，两端由刀径形成圆弧；槽宽大于刀径时自动分行"
        case .outer: return "贴轮廓外侧顺时针绕，上边中点半圆弧切入/切出，G41 把刀偏在外面"
        case .innerChamfer: return "刀心在孔里连续螺旋下，一圈缩一层，中途不抬刀"
        case .odCham: return "刀在外圆外侧连续螺旋下，一圈向外挪一层，中途不抬刀"
        case .rCorner:
            return spec.rKind == .slot
                ? "槽底内 R 沿 1/4 圆逐层收角，每层走一圈圆角槽"
                : "沿 1/4 圆按角度分层，每层一整圈/一圈圆角矩形，逐层叠出 R 面"
        case .arcSurface:
            return spec.arcKind == .inner
                ? "X 向往返直线，Y=COS[角度]×R，Z=-(直边深度+SIN[角度]×R)，逐刀叠出内圆弧面"
                : "X 向往返直线，Y=-SIN[角度]×(刀尖R+R)，Z=-R×(1-COS[角度])，逐刀叠出外圆弧面"
        }
    }

    private enum SyncSource { case small, ratio, angle }
    @State private var syncSource: SyncSource = .small

    var body: some View {
            Form {
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
                        intRow("孔数", value: $spec.holeCount)
                        if spec.holeCount > 1 {
                            numRow("圆周分布半径", value: $spec.holePatternRadius)
                            numRow("起始角 °", value: $spec.holeStartAngle)
                            numRow("角步距 °（0=均分）", value: $spec.holeAngleStep)
                            Text("孔数 > 1 时按 G52 逐孔平移；单孔时分布半径自动按 0 处理")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if spec.mode == .oblique {
                    Section("非正交螺旋参数 (mm)") {
                        numRow("孔径 Ø", value: $spec.spiralDia)
                        numRow("加工深度 H", value: $spec.depth)
                        numRow("每圈切深", value: $spec.stepDown)
                        numRow("孔轴旋转角 °", value: $spec.obliqueAngle)
                        Text("G68 让孔轴在 XY 平面内旋转；X 每度进给，YZ 走圆，到底再走一圈平底")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("旋转 0° 时孔轴沿 X；70° 就是图例里的斜向孔。上机前用空跑确认 G68 方向")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if spec.mode == .thread {
                    Section("圆周螺纹参数 (mm)") {
                        numRow("螺纹直径 M", value: $spec.threadDia)
                        numRow("螺距 P", value: $spec.threadPitch)
                        numRow("螺纹长度", value: $spec.threadLength)
                        numRow("螺纹顶 Z", value: $spec.threadTop)
                        numRow("径向步距", value: $spec.threadRadialStep)
                        intRow("孔数", value: $spec.holeCount)
                        if spec.holeCount > 1 {
                            numRow("圆周分布半径", value: $spec.holePatternRadius)
                            numRow("起始角 °", value: $spec.holeStartAngle)
                            numRow("角步距 °（0=均分）", value: $spec.holeAngleStep)
                            Text("按 G52 逐孔平移；每个孔先径向进刀，再 G03 螺旋上升一个螺距一圈")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("径向范围自动按螺纹直径与螺纹刀直径算；默认 8 孔、分布 R100、起始 22.5°")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if spec.mode == .arcSurface {
                    Section("圆弧面参数 (mm)") {
                        Picker("圆弧类型", selection: $spec.arcKind) {
                            ForEach(ArcKind.allCases) { k in
                                Text(k.rawValue).tag(k)
                            }
                        }
                        .pickerStyle(.segmented)
                        numRow("单侧行程", value: $spec.arcTravel)
                        numRow("圆弧半径 R", value: $spec.arcRadius)
                        if spec.arcKind == .inner {
                            numRow("直边深度", value: $spec.arcStraightDepth)
                        }
                        numRow("扫掠角度 °", value: $spec.arcSweep)
                        numRow("角度步距 °", value: $spec.arcAngleStep)
                        numRow("圆弧轴心 Y 偏移", value: $spec.arcCenterY)
                        Text("X 从 -行程 走到 +行程，再反向；每刀角度增加一个步距。轴心 Y 偏移会加到工件中心 Y 上")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("图例默认：内圆弧 行程122 / 轴心Y -70 / 刀Ø40 / 直边25；外圆弧 行程127 / 轴心Y -45 / 刀Ø50 / 刀尖R5")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if spec.arcKind == .outer {
                            Text("外圆弧实际计算半径 = 刀尖 R + 圆弧半径；刀尖 R 在下方「刀具与切削」里填")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("内圆弧暂按刀尖中心走，未补刀尖 R；要精确请用球刀或把 R 补进程序")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
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
                        if spec.mode == .face {
                            numRow("斜面角 °（0=平面）", value: $spec.slopeAngle)
                            Text("正角向 +Y 下斜，负角向 -Y 下斜；每层 Y 偏移 = 深度 × tan(角度)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
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

                if spec.mode == .taper || spec.mode == .taperHelix {
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
                        if spec.mode == .taperHelix {
                            numRow("每圈下刀量", value: $spec.stepDown)
                        }
                        Text("大小头定锥度；锥度与角度也可直接改，其余自动换算；锥孔螺旋按每圈下刀量分层")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if spec.mode == .innerChamfer {
                    Section("内圆倒角参数 (mm)") {
                        numRow("孔径 Ø", value: $spec.chaDia)
                        numRow("锥角 °（全角）", value: $spec.chaAngle)
                        numRow("倒角深 H", value: $spec.chaDepth)
                        numRow("每层 mm", value: $spec.chaStep)
                        Text("顶口直径 = 孔径 + 2×深×tan(锥角/2)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if spec.mode == .odCham {
                    Section("外圆倒角参数 (mm)") {
                        numRow("外圆直径 Ø", value: $spec.odDia)
                        numRow("锥角 °（全角）", value: $spec.odAngle)
                        numRow("倒角深 H", value: $spec.odDepth)
                        numRow("每层 mm", value: $spec.odStep)
                        Text("倒角宽 = 深×tan(锥角/2)；顶口直径 = 外圆 − 2×倒角宽")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("圆柱外缘顶边倒角；整圆一刀，外圆上有缺口时会被切一刀")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if spec.mode == .rCorner {
                    Section("R 角类型") {
                        Picker("类型", selection: $spec.rKind) {
                            ForEach(RCornerKind.allCases) { k in
                                Text(k.rawValue).tag(k)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    Section("R 角参数 (mm)") {
                        if spec.rKind == .outerCylinder {
                            numRow("圆柱直径 Ø", value: $spec.rCylinderDia)
                        } else if spec.rKind == .hole {
                            numRow("孔径 Ø", value: $spec.rHoleDia)
                        } else {
                            numRow("长 L", value: $spec.length)
                            numRow("宽 W", value: $spec.width)
                            if spec.rKind == .slot {
                                numRow("槽深 H", value: $spec.depth)
                            }
                        }
                        numRow("R 角半径", value: $spec.rValue)
                        numRow("角度步距 °", value: $spec.rAngleStep)
                        Text("沿 90° 分成若干层，每层走一圈；3° 约 30 层，2° 更光但程序更长")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("刀尖 R 在下方「刀具与切削」里填：平底刀 0，圆鼻刀填刀片 R")
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
                    Text("中心为工件/孔中心，程序用 G52 平移；Z0 = 工件顶面")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("刀具与切削") {
                    numRow("刀具直径", value: $spec.toolDia)
                    numRow("刀尖 R（平底刀填 0）", value: $spec.toolCornerR)
                    if spec.mode != .innerChamfer && spec.mode != .odCham && spec.mode != .rCorner && spec.mode != .arcSurface {
                        numRow("每层切深 AP", value: $spec.stepDown)
                    }
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

                Section("程序格式") {
                    Picker("程序格式", selection: $format) {
                        ForEach(ProgramFormat.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(format.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

                    NavigationLink {
                        DrawScreen()
                    } label: {
                        HStack {
                            Spacer()
                            Label("绘图编程 · 任意轮廓", systemImage: "scribble.variable")
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
                            Label(format == .macro ? "生成宏程序 · 含刀路仿真" : "生成 G 代码 · 含刀路仿真",
                                  systemImage: format == .macro ? "function" : "list.number")
                            Spacer()
                        }
                        .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(!spec.canGenerate)
                }
            }
            .navigationTitle(spec.mode.rawValue)
            .navigationBarTitleDisplayMode(.inline)
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
                ResultView(code: result, manual: manual, fileURL: fileURL, spec: spec, format: format)
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
        var source = spec
        // 普通 G 代码不接受 FANUC 的 ,R/,C 精简写法，改用完整圆角/倒角块。
        if format == .gcode { source.compact = false }
        let macro = GCodeGenerator.generate(source)
        let code = PostProcessor.output(macro, format: format)
        let name: String
        if spec.mode == .taper {
            name = "taper_D\(Int(spec.taperDia))d\(Int(spec.taperDiaSmall))_H\(Int(spec.taperDepth)).nc"
        } else if spec.mode == .taperHelix {
            name = "taperHelix_D\(Int(spec.taperDia))d\(Int(spec.taperDiaSmall))_H\(Int(spec.taperDepth))_a\(String(format: "%.2f", spec.stepDown)).nc"
        } else if spec.mode == .face {
            name = "face_L\(Int(spec.length))_W\(Int(spec.width))_H\(Int(spec.depth))_A\(Int(spec.slopeAngle)).nc"
        } else if spec.mode == .spiral {
            name = "spiral_D\(Int(spec.spiralDia))_H\(Int(spec.depth))_N\(spec.holeCount).nc"
        } else if spec.mode == .oblique {
            name = "oblique_D\(Int(spec.spiralDia))_H\(Int(spec.depth))_A\(Int(spec.obliqueAngle)).nc"
        } else if spec.mode == .thread {
            name = "thread_M\(Int(spec.threadDia))_P\(fmt(spec.threadPitch, 2))_N\(spec.holeCount).nc"
        } else if spec.mode == .key {
            name = "key_L\(Int(spec.keyLength))_W\(Int(spec.keyWidth))_H\(Int(spec.depth)).nc"
        } else if spec.mode == .outer {
            name = "outer_L\(Int(spec.length))_W\(Int(spec.width))_H\(Int(spec.depth)).nc"
        } else if spec.mode == .innerChamfer {
            name = "chamfer_D\(Int(spec.chaDia))_A\(Int(spec.chaAngle))_H\(Int(spec.chaDepth)).nc"
        } else if spec.mode == .odCham {
            name = "odcham_D\(Int(spec.odDia))_A\(Int(spec.odAngle))_H\(Int(spec.odDepth)).nc"
        } else if spec.mode == .rCorner {
            name = "r\(spec.rKind.rawValue)_R\(Int(spec.rValue))_A\(Int(spec.rAngleStep)).nc"
        } else if spec.mode == .arcSurface {
            let kind = spec.arcKind == .inner ? "inner" : "outer"
            name = "arc_\(kind)_R\(Int(spec.arcRadius))_T\(Int(spec.arcTravel))_A\(Int(spec.arcAngleStep)).nc"
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
    let format: ProgramFormat
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

                if format == .macro {
                    DisclosureGroup("使用说明（每个变量怎么改）") {
                        Text(manual)
                            .font(.system(size: 13))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)
                    }
                    .padding(12)
                } else {
                    Text("已展开为普通 G 代码：程序里不再有 #变量、WHILE 和 IF，坐标全部是固定值。上机前核对 G43/G28/G52 与 D 刀补。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(12)
                }
            }
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .navigationTitle(format == .macro ? "宏程序" : "普通 G 代码")
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
