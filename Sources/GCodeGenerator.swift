import Foundation

enum CornerType: String, CaseIterable, Identifiable {
    case radius = "R 圆角"
    case chamfer = "C 倒角"
    case square = "直角"

    var id: String { rawValue }
}

enum MachiningMode: String, CaseIterable, Identifiable {
    case pocket = "方形型腔"
    case taper = "锥孔"
    case face = "铣飞面"
    case spiral = "螺旋铣"
    case key = "铣键槽"
    case outer = "只铣外方形"
    case innerChamfer = "内圆倒角"

    var id: String { rawValue }
}

struct PocketSpec {
    var mode: MachiningMode = .pocket

    // 型腔
    var length: Double = 120
    var width: Double = 80
    var depth: Double = 10
    var cornerType: CornerType = .radius
    var cornerValue: Double = 8
    var stepOver: Double = 6
    var compact: Bool = true

    // 锥孔
    var taperDia: Double = 50        // 大头
    var taperDiaSmall: Double = 34   // 小头
    var taperDepth: Double = 38      // 深度
    var spiralDia: Double = 50       // 螺旋铣圆直径
    var keyLength: Double = 40       // 键槽槽长（含圆弧）
    var keyWidth: Double = 12        // 键槽槽宽
    var taperRatio: Double = 2.38    // 锥度 1:N
    var taperAngle: Double = 22.83   // 全角（度）

    // 内圆倒角
    var chaDia: Double = 14          // 孔径
    var chaAngle: Double = 60        // 锥角（全角）
    var chaDepth: Double = 4         // 倒角深
    var chaStep: Double = 0.1        // 每层

    // 共用
    var toolDia: Double = 12
    var toolCornerR: Double = 5      // 刀尖 R（平底刀填 0）
    var stepDown: Double = 3
    var spindle: Int = 2000
    var feed: Int = 400
    var safeZ: Double = 100
    var hNo: Int = 13                // 刀补号 H / D
    var coord: Int = 54
    var cx: Double = 0
    var cy: Double = 0

    var toolRadius: Double { toolDia / 2 }
    var halfAngle: Double { atan((taperDia - taperDiaSmall) / (2 * taperDepth)) * 180 / .pi }

    var issues: [String] {
        switch mode {
        case .taper: return taperIssues
        case .face: return faceIssues
        case .spiral: return spiralIssues
        case .key: return keyIssues
        case .outer: return outerIssues
        case .innerChamfer: return chamferIssues
        default: return pocketIssues
        }
    }

    private var chamferIssues: [String] {
        var out: [String] = []
        let topDia = chaDia + 2 * chaDepth * tan(chaAngle / 2 * .pi / 180)
        if chaDia <= 0 { out.append("孔径必须大于 0") }
        if toolDia <= 0 { out.append("刀具直径必须大于 0") }
        if toolDia >= chaDia { out.append("刀具直径必须小于孔径，否则刀进不去") }
        if toolDia >= topDia { out.append("刀太大，放到顶口也套不进去，换小刀或减小锥角") }
        if chaDepth <= 0 { out.append("倒角深度必须大于 0") }
        if chaAngle <= 1 || chaAngle >= 179 { out.append("锥角应在 1~179 度之间（按图纸全角填）") }
        if chaStep <= 0 { out.append("每层切深必须大于 0") }
        if chaStep > chaDepth { out.append("每层切深大于总深度，改小一点") }
        return out
    }

    private var faceIssues: [String] {
        var out: [String] = []
        if length <= 0 || width <= 0 { out.append("长宽必须大于 0") }
        if toolDia <= 0 { out.append("刀具直径必须大于 0") }
        if depth <= 0 { out.append("要去掉的总深度必须大于 0") }
        if stepDown <= 0 { out.append("每层切深必须大于 0") }
        if stepDown > depth { out.append("每层切深大于总深度，改小一点") }
        return out
    }

    private var keyIssues: [String] {
        var out: [String] = []
        if keyLength <= 0 { out.append("槽长必须大于 0") }
        if keyWidth <= 0 { out.append("槽宽必须大于 0") }
        if toolDia <= 0 { out.append("刀具直径必须大于 0") }
        if toolDia > keyWidth { out.append("刀径不能大于槽宽，否则铣出来比槽宽") }
        if toolDia > keyLength { out.append("刀径不能大于槽长") }
        if depth <= 0 { out.append("总深必须大于 0") }
        if stepDown <= 0 { out.append("每层切深必须大于 0") }
        if stepDown > depth { out.append("每层切深大于总深，改小一点") }
        return out
    }

    private var spiralIssues: [String] {
        var out: [String] = []
        if spiralDia <= 0 { out.append("圆直径必须大于 0") }
        if toolDia <= 0 { out.append("刀具直径必须大于 0") }
        if toolDia >= spiralDia { out.append("刀具直径必须小于圆直径") }
        if depth <= 0 { out.append("要去掉的总深度必须大于 0") }
        if stepDown <= 0 { out.append("每圈下刀量必须大于 0") }
        if stepDown > depth { out.append("每圈下刀量大于总深度，改小一点") }
        return out
    }

    var canGenerate: Bool { issues.isEmpty }

    private var pocketIssues: [String] {
        var out: [String] = []
        if length <= 0 || width <= 0 || depth <= 0 { out.append("长宽深必须大于 0") }
        if toolDia <= 0 { out.append("刀具直径必须大于 0") }
        if toolDia >= min(length, width) { out.append("刀具直径必须小于型腔最小边") }
        if stepDown <= 0 { out.append("每层切深必须大于 0") }
        if cornerType != .square && cornerValue <= 0 { out.append("R/C 值必须大于 0，或选「直角」") }
        if cornerType == .radius && cornerValue < toolRadius {
            out.append("圆角 R 小于刀具半径，壁面无法一刀到位，需换小刀或先清角")
        }
        if cornerType == .chamfer && cornerValue > min(length, width) / 2 { out.append("倒角 C 过大") }
        if stepOver <= 0 || stepOver > toolDia { out.append("行距应在 0 到刀具直径之间") }
        return out
    }

    private var outerIssues: [String] {
        var out: [String] = []
        if length <= 0 || width <= 0 { out.append("工件长宽必须大于 0") }
        if toolDia <= 0 { out.append("刀具直径必须大于 0") }
        if depth <= 0 { out.append("总深必须大于 0") }
        if stepDown <= 0 { out.append("每层切深必须大于 0") }
        if stepDown > depth { out.append("每层切深大于总深，改小一点") }
        if stepDown > toolDia * 0.6 { out.append("每层切深超过刀径 60%，外形侧铣吃太多，改小一点") }
        if cornerType != .square && cornerValue <= 0 { out.append("R/C 值必须大于 0，或选「直角」") }
        if cornerType != .square && cornerValue >= min(length, width) / 2 { out.append("R/C 值不能大于工件最小边的一半") }
        return out
    }

    private var taperIssues: [String] {
        var out: [String] = []
        if taperDia <= 0 || taperDiaSmall <= 0 { out.append("大头/小头必须大于 0") }
        if taperDia <= taperDiaSmall { out.append("大头必须大于小头") }
        if taperDepth <= 0 { out.append("深度必须大于 0") }
        if toolDia <= 0 { out.append("刀具直径必须大于 0") }
        if toolCornerR < 0 || toolCornerR > toolRadius { out.append("刀尖 R 不能大于刀具半径（平底刀填 0）") }
        if toolRadius >= taperDiaSmall / 2 { out.append("刀具半径大于小头半径，下不到底，需换小刀") }
        if stepDown <= 0 { out.append("每层切深必须大于 0") }
        return out
    }
}

enum GCodeGenerator {

    static func fmt(_ v: Double, _ digits: Int = 3) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        f.minimumFractionDigits = digits
        f.maximumFractionDigits = digits
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }

    static func generate(_ s: PocketSpec) -> String {
        switch s.mode {
        case .taper: return generateTaper(s)
        case .face: return generateFace(s)
        case .spiral: return generateSpiral(s)
        case .key: return generateKey(s)
        case .outer: return generateOuter(s)
        case .innerChamfer: return generateInnerChamfer(s)
        default: return generatePocket(s)
        }
    }

    // MARK: - 内圆倒角
    private static func generateInnerChamfer(_ s: PocketSpec) -> String {
        let topDia = s.chaDia + 2 * s.chaDepth * tan(s.chaAngle / 2 * .pi / 180)
        let plunge = max(50, s.feed / 3)
        var L: [String] = []
        L.append("%")
        L.append("O1005 (内圆倒角宏程序)")
        L.append("( 孔Ø\(fmt(s.chaDia, 2))  锥角\(fmt(s.chaAngle, 1))°  深\(fmt(s.chaDepth, 2))  刀Ø\(fmt(s.toolDia, 2)) )")
        L.append("( 顶口Ø\(fmt(topDia, 2))  每层\(fmt(s.chaStep, 3))  中心X=\(fmt(s.cx, 2)) Y=\(fmt(s.cy, 2)) )")
        L.append("( Z0=工件上表面  孔要先打穿或至少深过倒角 )")
        L.append("( 由 MacroGen 生成 上机前请核对 )")
        L.append("G17 G21 G40 G49 G80 G90 G\(s.coord)")
        let shift = abs(s.cx) > 1e-9 || abs(s.cy) > 1e-9
        if shift {
            L.append("G52 X\(fmt(s.cx, 3)) Y\(fmt(s.cy, 3)) (平移到孔中心)")
        } else {
            L.append("( X0 Y0 就是 G\(s.coord) 零点, 不对刀就不用改 )")
        }
        L.append("G43 H\(s.hNo) Z\(fmt(s.safeZ, 1))")
        L.append("M3 S\(s.spindle)")
        L.append("M8")
        L.append("#1=\(fmt(s.chaDia, 2)) (孔径)")
        L.append("#2=\(fmt(s.toolDia, 2)) (刀径)")
        L.append("#3=\(fmt(s.chaDepth, 2)) (倒角深)")
        L.append("#4=\(fmt(s.chaStep, 3)) (每层)")
        L.append("#5=\(fmt(s.chaAngle, 1)) (锥角 全角)")
        L.append("#6=\(plunge) (下刀F)")
        L.append("#7=\(s.feed) (圆周F)")
        L.append("#25=TAN[#5/2.] (半角正切)")
        L.append("#26=FIX[#3/#4] (层数,取整防少切一层)")
        L.append("#21=[[#1/2.]+[#3*#25]]-[#2/2.] (顶层刀心半径)")
        L.append("G0 Z[#3+2.] (先到工件上方)")
        L.append("G0 X#21 Y0")
        L.append("G1 Z-#4 F#6 (第一刀把顶面那圈也切掉)")
        L.append("G2 X-#21 Y0 R#21 F#7 (前半圆, 圆心在X0Y0)")
        L.append("G2 X#21 Y0 R#21 F#7 (后半圆)")
        L.append("#20=2 (从第二层开始循环)")
        L.append("WHILE[#20LE#26]DO1")
        L.append("#21=[[#1/2.]+[[#3-[#20*#4]]*#25]]-[#2/2.] (本层刀心半径)")
        L.append("G0 Z2. (抬到工件上方再移刀)")
        L.append("G0 X#21 Y0")
        L.append("G1 Z-[#20*#4] F#6 (下本层)")
        L.append("G2 X-#21 Y0 R#21 F#7 (前半圆, 圆心在X0Y0)")
        L.append("G2 X#21 Y0 R#21 F#7 (后半圆)")
        L.append("#20=#20+1")
        L.append("END1")
        L.append("G0 Z\(fmt(s.safeZ, 1))")
        if shift { L.append("G52 X0 Y0") }
        L.append("M5")
        L.append("M9")
        L.append("G28 G91 Z0")
        L.append("G28 G91 Y0")
        L.append("G90")
        L.append("M30")
        L.append("%")
        return L.joined(separator: "\n")
    }

    // MARK: - 只铣外方形
    private static func generateOuter(_ s: PocketSpec) -> String {
        var L: [String] = []
        L.append("%")
        L.append("O1006 (铣外方形)")
        L.append("G17 G21 G40 G49 G80 G90 G\(s.coord)")
        L.append("G52 X\(fmt(s.cx)) Y\(fmt(s.cy)) (平移到工件中心)")
        L.append("G43 H\(s.hNo) Z\(fmt(s.safeZ, 1))")
        L.append("M3 S\(s.spindle)")
        L.append("M8")
        L.append("#1=\(fmt(s.length, 1)) (工件长)")
        L.append("#2=\(fmt(s.width, 1)) (工件宽)")
        L.append("#3=\(fmt(s.toolDia, 1)) (刀具直径)")
        let cv = s.cornerType == .square ? 0 : s.cornerValue
        L.append("#4=\(fmt(cv, 3)) (\(s.cornerType == .chamfer ? "倒角C，直角写0" : "圆角R，直角写0"))")
        L.append("#5=\(fmt(s.depth, 3)) (总深)")
        L.append("#6=\(fmt(s.stepDown, 2)) (每层)")
        L.append("#7=0 (工件表面Z)")
        L.append("#8=-#5 (终点Z)")
        L.append("#9=[#3/2.+2.] (起刀让量)")
        L.append("#10=[#1/2.] (半长)")
        L.append("#11=[#2/2.] (半宽)")
        L.append("#12=[#10-#4] (角起点X)")
        L.append("#13=#7 (当前Z)")
        L.append("WHILE[#13GT#8]DO1")
        L.append("#13=#13-#6")
        L.append("IF[#13LT#8]THEN#13=#8")
        L.append("G0 Z[#13+2.] (抬到本层上方2mm)")
        L.append("G0 X-[#10+#9] Y[#11+#9] (到左上角外侧)")
        L.append("G1 Z#13 F\(s.feed / 2) (落刀到本层)")
        L.append("G41 D\(s.hNo) G1 X-#12 Y#11 F\(s.feed) (左刀补切入，刀在轮廓外)")
        L.append("G1 X#12 F\(s.feed) (上边 → 右上角)")
        if s.cornerType == .radius {
            L.append("G2 X#10 Y[#11-#4] R#4 F\(s.feed) (右上圆角 R)")
            L.append("G1 Y-[#11-#4] F\(s.feed) (右边)")
            L.append("G2 X#12 Y-#11 R#4 F\(s.feed) (右下圆角 R)")
            L.append("G1 X-#12 F\(s.feed) (下边 → 左下角)")
            L.append("G2 X-#10 Y-[#11-#4] R#4 F\(s.feed) (左下圆角 R)")
            L.append("G1 Y[#11-#4] F\(s.feed) (左边)")
            L.append("G2 X-#12 Y#11 R#4 F\(s.feed) (左上圆角 R)")
        } else {
            L.append("G1 X#10 Y[#11-#4] F\(s.feed) (右上倒角 C)")
            L.append("G1 Y-[#11-#4] F\(s.feed) (右边)")
            L.append("G1 X#12 Y-#11 F\(s.feed) (右下倒角 C)")
            L.append("G1 X-#12 F\(s.feed) (下边 → 左下角)")
            L.append("G1 X-#10 Y-[#11-#4] F\(s.feed) (左下倒角 C)")
            L.append("G1 Y[#11-#4] F\(s.feed) (左边)")
            L.append("G1 X-#12 Y#11 F\(s.feed) (左上倒角 C)")
        }
        L.append("G40 G1 X-[#10+#9] Y[#11+#9] F\(s.feed) (取消刀补退刀)")
        L.append("END1")
        L.append("G0 Z\(fmt(s.safeZ, 1))")
        L.append("G52 X0 Y0")
        L.append("M5")
        L.append("M9")
        L.append("G28 G91 Z0")
        L.append("G28 G91 Y0")
        L.append("G90")
        L.append("M30")
        L.append("%")
        return join(L)
    }

    // MARK: - 铣飞面
    private static func generateFace(_ s: PocketSpec) -> String {
        var L: [String] = []
        L.append("%")
        L.append("O1003 (飞面宏程序)")
        L.append("G17 G21 G40 G49 G80 G90 G\(s.coord)")
        L.append("G52 X\(fmt(s.cx)) Y\(fmt(s.cy)) (平移到平面中心)")
        L.append("G43 H\(s.hNo) Z\(fmt(s.safeZ, 1))")
        L.append("M3 S\(s.spindle)")
        L.append("M8")
        L.append("#1=\(fmt(s.length, 1)) (长)")
        L.append("#2=\(fmt(s.width, 1)) (宽)")
        L.append("#3=\(fmt(s.toolDia, 1)) (刀具直径)")
        L.append("#4=0 (起始Z)")
        L.append("#5=\(fmt(-s.depth, 3)) (终点Z)")
        L.append("#6=\(fmt(s.stepDown, 2)) (每层)")
        L.append("#7=[#1/2.+#3/2.] (半长+刀半径，刀心走出工件边缘)")
        L.append("#8=[#2/2.+#3/2.] (半宽+刀半径，进出刀都在料外)")
        L.append("#9=[#3*0.75] (行距)")
        L.append("#10=1 (方向)")
        L.append("#11=#4 (当前Z)")
        L.append("WHILE[#11GT#5]DO1")
        L.append("#11=#11-#6")
        L.append("IF[#11LT#5]THEN#11=#5")
        L.append("#12=-#7 (X起点)")
        L.append("WHILE[#12LE#7]DO2")
        L.append("G0 Z[#4+2.] (抬到工件表面上方2mm再横移)")
        L.append("G0 X#12 Y[#8*#10]")
        L.append("G0 Z[#11+0.5]")
        L.append("G1 Z#11 F\(s.feed / 2)")
        L.append("G1 Y[-#8*#10] F\(s.feed)")
        L.append("#10=-#10")
        L.append("#12=#12+#9")
        L.append("END2")
        L.append("END1")
        L.append("G0 Z\(fmt(s.safeZ, 1))")
        L.append("G52 X0 Y0")
        L.append("M5")
        L.append("M9")
        L.append("G28 G91 Z0")
        L.append("G28 G91 Y0")
        L.append("G90")
        L.append("M30")
        L.append("%")
        return join(L)
    }

    // MARK: - 铣键槽
    private static func generateKey(_ s: PocketSpec) -> String {
        var L: [String] = []
        L.append("%")
        L.append("O1005 (键槽宏程序)")
        L.append("G17 G21 G40 G49 G80 G90 G\(s.coord)")
        L.append("G52 X\(fmt(s.cx)) Y\(fmt(s.cy)) (平移到键槽中心)")
        L.append("G43 H\(s.hNo) Z\(fmt(s.safeZ, 1))")
        L.append("M3 S\(s.spindle)")
        L.append("M8")
        L.append("#1=\(fmt(s.keyLength, 1)) (槽长含圆弧)")
        L.append("#2=\(fmt(s.keyWidth, 1)) (槽宽)")
        L.append("#3=\(fmt(s.toolDia, 1)) (刀具直径)")
        L.append("#4=\(fmt(s.depth, 3)) (总深)")
        L.append("#5=\(fmt(s.stepDown, 2)) (每层)")
        L.append("#6=0 (工件表面Z)")
        L.append("#7=-#4 (终点Z)")
        L.append("#8=[#1-#2]/2. (两端圆弧圆心X)")
        L.append("#9=[#2/2.-#3/2.] (端弧刀心半径)")
        L.append("IF[#9LT0.01]THEN#9=0.01")
        L.append("#13=#6 (当前Z)")
        L.append("WHILE[#13GT#7]DO1")
        L.append("#13=#13-#5")
        L.append("IF[#13LT#7]THEN#13=#7")
        L.append("G0 Z[#13+2.] (抬到本层上方2mm)")
        L.append("G0 X0 Y0 (在槽中心落刀，别贴壁下刀)")
        L.append("G1 Z#13 F\(s.feed / 2) (落刀到本层)")
        L.append("G1 X-#8 Y-#9 F\(s.feed / 2) (切到左端弧起点)")
        L.append("G1 X#8 F\(s.feed) (下壁走到右端)")
        L.append("G3 Y#9 I0. J#9 F\(s.feed) (右端圆弧 R)")
        L.append("G1 X-#8 F\(s.feed) (上壁走回左端)")
        L.append("G3 Y-#9 I0. J-#9 F\(s.feed) (左端圆弧 R)")
        L.append("END1")
        L.append("G0 Z\(fmt(s.safeZ, 1))")
        L.append("G52 X0 Y0")
        L.append("M5")
        L.append("M9")
        L.append("G28 G91 Z0")
        L.append("G28 G91 Y0")
        L.append("G90")
        L.append("M30")
        L.append("%")
        return join(L)
    }

    // MARK: - 螺旋铣
    private static func generateSpiral(_ s: PocketSpec) -> String {
        var L: [String] = []
        L.append("%")
        L.append("O1004 (螺旋铣宏程序)")
        L.append("G17 G21 G40 G49 G80 G90 G\(s.coord)")
        L.append("G52 X\(fmt(s.cx)) Y\(fmt(s.cy)) (平移到圆心)")
        L.append("G43 H\(s.hNo) Z\(fmt(s.safeZ, 1))")
        L.append("M3 S\(s.spindle)")
        L.append("M8")
        L.append("#1=\(fmt(s.spiralDia, 1)) (圆直径)")
        L.append("#2=\(fmt(s.toolDia, 1)) (刀具直径)")
        L.append("#3=0 (工件表面Z)")
        L.append("#4=\(fmt(-s.depth, 3)) (终点Z)")
        L.append("#5=\(fmt(s.stepDown, 2)) (每圈下刀)")
        L.append("#6=[#1/2.-#2/2.] (刀心圆半径)")
        L.append("IF[#6LT0.01]THEN#6=0.01 (防半径算成 0 或负数)")
        L.append("#7=#3 (当前Z)")
        L.append("G0 X-#6 Y0 (进到圆上)")
        L.append("G0 Z[#3+2.] (只到工件上方2mm，不再直插到Z0)")
        L.append("WHILE[#7GT#4]DO1")
        L.append("#7=#7-#5")
        L.append("IF[#7LT#4]THEN#7=#4")
        L.append("G3 I#6 Z#7 F\(s.feed)")
        L.append("END1")
        L.append("G0 Z\(fmt(s.safeZ, 1))")
        L.append("G52 X0 Y0")
        L.append("M5")
        L.append("M9")
        L.append("G28 G91 Z0")
        L.append("G28 G91 Y0")
        L.append("G90")
        L.append("M30")
        L.append("%")
        return join(L)
    }

    // MARK: - 方形型腔
    private static func generatePocket(_ s: PocketSpec) -> String {
        var L: [String] = []

        L.append("%")
        L.append("O1001 (型腔宏程序)")
        L.append("( 长=\(fmt(s.length)) 宽=\(fmt(s.width)) 深=\(fmt(s.depth)) )")
        L.append("( 四角=\(cornerDesc(s)) 刀具=\(fmt(s.toolDia)) )")
        L.append("( 切深=\(fmt(s.stepDown)) 行距=\(fmt(s.stepOver)) 转速=\(s.spindle) 进给=\(s.feed) )")
        L.append("( 坐标 G\(s.coord)  中心X=\(fmt(s.cx)) 中心Y=\(fmt(s.cy))  Z0=工件顶面 )")
        L.append("( 由 MacroGen 生成 上机前请核对 )")
        L.append("G17 G21 G40 G49 G80 G90 G\(s.coord)")
        L.append("#31=\(fmt(s.cx)) (中心X)")
        L.append("#32=\(fmt(s.cy)) (中心Y)")
        L.append("G52 X#31 Y#32 (平移到型腔中心)")
        L.append("G43 H\(s.hNo) Z\(fmt(s.safeZ))")
        L.append("M3 S\(s.spindle)")
        L.append("M8")
        L.append("#20=\(fmt(s.length / 2)) (半长)")
        L.append("#21=\(fmt(s.width / 2)) (半宽)")
        L.append("#22=\(fmt(s.toolDia / 2)) (刀具半径)")
        L.append("#3=\(fmt(s.depth)) (深)")
        L.append("#4=\(fmt(s.cornerValue)) (圆角或倒角)")
        L.append("#6=\(fmt(s.stepDown)) (每层切深)")
        L.append("#7=\(fmt(s.stepOver)) (行距)")
        L.append("#9=\(s.feed) (进给)")
        L.append("#10=\(fmt(s.safeZ)) (安全高度)")
        L.append("#23=0. (当前深度)")
        L.append("( === 分层粗铣 === )")
        L.append("WHILE[#23LT#3]DO1")
        L.append("#23=#23+#6")
        L.append("IF[#23GT#3]THEN#23=#3")
        L.append("#26=-#23")
        L.append("( 斜插下刀 )")
        L.append("G00 X0 Y0")
        L.append("G01 Z[#26+1.5] F[#9]")
        L.append("G01 X[#20/3.] Z#26 F[#9/2.]")
        L.append("#24=0 (环号)")
        L.append("WHILE[[#22+#24*#7]LE[#21-0.5]]DO2")
        L.append("#30=[#22+#24*#7] (内缩量)")
        L.append("#27=[#20-#30] (环半长)")
        L.append("#28=[#21-#30] (环半宽)")
        L.append("#29=[#4-#30] (环圆角)")
        L.append("IF[#29LT0.]THEN#29=0.")
        if s.cornerType == .radius {
            L.append("IF[#29LT0.001]THEN#29=0.001")
        }
        L.append("#24=#24+1")
        if s.compact {
            L.append(contentsOf: ringBlocksCompact(s, skipFirst: false))
        } else {
            L.append(contentsOf: ringBlocks(type: s.cornerType, approach: "G01 X#27 Y0 F[#9]"))
        }
        L.append("END2")
        L.append("END1")
        L.append("( === 精修壁面 G41 === )")
        L.append("#27=#20")
        L.append("#28=#21")
        L.append("#29=#4")
        L.append("G00 Z[#26+2.]")
        L.append("G00 X0 Y0 (回腔中心，别往壁里冲)")
        L.append("G01 Z#26 F[#9]")
        L.append("G41 D\(s.hNo) G01 X#27 Y0 F[#9]")
        if s.compact {
            L.append(contentsOf: ringBlocksCompact(s, skipFirst: true))
        } else {
            L.append(contentsOf: ringBlocks(type: s.cornerType))
        }
        L.append("G40 G01 X0 Y0 F[#9] (退回腔中心再抬刀)")
        L.append("G00 Z#10")
        L.append("G52 X0 Y0 (取消局部坐标)")
        L.append("M5")
        L.append("M9")
        L.append("G28 G91 Z0")
        L.append("G28 G91 Y0")
        L.append("G90")
        L.append("M30")
        L.append("%")
        return join(L)
    }

    // MARK: - 锥孔
    private static func generateTaper(_ s: PocketSpec) -> String {
        var L: [String] = []
        let taperN = s.taperDepth / (s.taperDia - s.taperDiaSmall)

        L.append("%")
        L.append("O1002(锥孔)")
        L.append("( 小头\(fmt(s.taperDiaSmall)) 大头\(fmt(s.taperDia)) 深\(fmt(s.taperDepth)) )")
        L.append("( 半角\(fmt(s.halfAngle)) 锥度1:\(fmt(taperN, 2)) 全角\(fmt(s.halfAngle * 2, 2)) )")
        L.append("( 刀\(fmt(s.toolDia)) 刀尖R\(fmt(s.toolCornerR)) 层\(fmt(s.stepDown)) )")
        L.append("( G\(s.coord) 中心X\(fmt(s.cx)) Y\(fmt(s.cy)) Z0=顶面 )")
        L.append("G17 G\(s.coord) G80 G90 G40 G49")
        L.append("#31=\(fmt(s.cx))(中心X)")
        L.append("#32=\(fmt(s.cy))(中心Y)")
        L.append("G52 X#31 Y#32")
        L.append("G0 X0 Y0")
        L.append("G43 H\(s.hNo) Z\(fmt(s.safeZ))")
        L.append("M3 S\(s.spindle)")
        L.append("Z10.")
        L.append("M8")
        L.append("#1=\(fmt(s.taperDiaSmall))(小头)")
        L.append("#2=\(fmt(s.taperDia))(大头)")
        L.append("#3=\(fmt(s.halfAngle, 4))(半角)")
        L.append("#4=\(fmt(s.toolDia))(刀直径)")
        L.append("#5=\(fmt(s.toolCornerR))(刀尖R)")
        L.append("#16=\(fmt(s.stepDown))(层深)")
        L.append("#21=\(fmt(s.taperDepth))(总深)")
        L.append("#9=\(s.feed)(进给)")
        L.append("#6=0(当前深度)")
        L.append("#11=[#2/2.](大头半径)")
        L.append("#7=#5*[1-COS[#3]](刀尖R径向补偿)")
        L.append("#8=#5*SIN[#3]")
        L.append("WHILE[#6LE#21]DO2")
        L.append("#12=#11+#7-#4/2-#6*TAN[#3](刀心半径)")
        L.append("#13=#8-#5-#6(Z)")
        L.append("IF[#12LT.001]THEN#12=.001")
        L.append("G0 X0 Y0")
        L.append("G1 Z[#13+#5]F[#9/2.]")
        L.append("G1 X#12 F[#9]")
        L.append("G3 I-#12 F[#9]")
        L.append("G1 X0 Y0")
        L.append("#6=#6+#16")
        L.append("END2")
        L.append("G0 Z\(fmt(s.safeZ))")
        L.append("G52 X0 Y0")
        L.append("M5")
        L.append("M9")
        L.append("G28 G91 Z0")
        L.append("G28 G91 Y0")
        L.append("G90")
        L.append("M30")
        L.append("%")
        return join(L)
    }

    // MARK: - 新手使用说明
    static func manual(_ s: PocketSpec) -> String {
        switch s.mode {
        case .innerChamfer:
            return """
            【干什么用】
            给孔口铣一圈锥面倒角（图纸上标 60°、90° 的那种）。用一把平底铣刀，刀心在孔里一圈一圈往下缩，
            每层只下 0.1，下几十层就把锥面一刀一刀叠出来。螺纹孔、销孔的口部倒角都用这个。

            【刀要多大】
            必须比孔小：Ø14 的孔最多用 Ø12 的刀，Ø10 最稳。刀比孔大，连孔都进不去，程序会直接报警不给算。

            【程序里几个数怎么改】
            #1 孔径：图纸上孔的名义尺寸，Ø14 就填 14
            #2 刀径：实际装上去的铣刀直径
            #3 倒角深：从工件上表面往下倒多深，图纸标 4 就填 4
            #4 每层：每圈往下吃多少。0.1 很稳，赶时间可 0.2，想更光可 0.05
            #5 锥角：填图纸上标的角度，注意是【全角】。标 60° 填 60，标 90° 填 90
            #6 下刀进给、#7 圆周进给：材料硬就把 #7 调小

            【倒角尺寸怎么核对】
            顶口直径 = 孔径 + 2 × 倒角深 × tan(锥角/2)
            例：Ø14 孔、深 4、60° → 顶口约 Ø18.62，正好比 M16 螺纹大一圈。
            如果图纸那个倒角只倒到 M16 大径（Ø16），深其实只有 1.7 左右，把 #3 改成 1.7。

            【为什么第一刀比后面多切一点】
            第一刀的半径是按“工件上表面”算的，所以正好把顶面那一圈切干净，倒角边齐平、不留薄边。

            【上机注意】
            1. Z0 要打在工件上表面，X0Y0 是孔中心（程序用 G52 平移过去了，不用改坐标）
            2. 孔必须先打穿或至少深过倒角，否则刀会在孔底顶到余料
            3. 倒角面是一层层叠出来的，刀纹是细台阶，想很光就把 #4 改 0.05 再走一遍
            """
        case .taper:
            return """
            【干什么用】
            铣 1:N 锥度的圆孔。刀具从大头中心下刀，一圈一圈往下扩，逐层把锥面铣出来。

            【上机前必须做】
            1. Z0 对在工件顶面（不是台面、不是毛坯底面）
            2. G54 的 X0 Y0 对在锥孔中心，程序会自动 G52 平移
            3. 刀具实际直径、刀补号 H 要和程序一致

            【可以改的变量】
            #1 = 小头直径
            #2 = 大头直径
            #3 = 半角（度）
            #4 = 刀具直径
            #5 = 刀尖 R（平底刀填 0，球刀填 R 值）
            #16 = 每层深度
            #21 = 总深
            #9 = 进给

            【不用管的变量】
            #6 当前深度、#11 大头半径、#7 刀尖R补偿、#8 Z向补偿、#12 刀心半径、#13 下刀Z 都是程序自己算的。

            【改法举例】
            想把小头改到 30：只改 #1=30。
            想每层切 1.5：改 #16=1.5。
            改了大头或小头后，半角 #3 要重新算：
            #3 = ATAN[(大头-小头)/2/总深]

            【注意】
            - 刀半径不能大于小头半径，否则下不到底，程序会让你换小刀
            - #12 那行有 IF 保护，刀心半径算出来小于 0 时会自动取 0.001，防止 I 值为负报警
            - 走刀方向是 G3（逆时针），想改顺铣要改成 G2，I 值同时变正号
            """
        case .outer:
            return """
            【干什么用】
            只铣外形。刀偏在工件轮廓外面，一圈一圈贴着外形往下走，把 长×宽 的方料修成外形（落料、修边都能用）。每层走一圈，走到总深为止。四角可以是 R 圆角，也可以是 C 倒角，直角就写 0。

            【上机前必须做】
            1. Z0 对在工件顶面
            2. G54 的 X0 Y0 对在工件中心（程序自动 G52 平移）
            3. 刀补号 D 和 H 填真实号，别写死
            4. 先在机床上空跑一次，确认 G41 让刀偏在工件外面；偏里面就是方向反了

            【可以改的变量】
            #1 = 工件长
            #2 = 工件宽
            #3 = 刀具直径
            #4 = 四角值（R 圆角 / C 倒角，直角写 0）
            #5 = 总深
            #6 = 每层切深
            #7 = 工件表面 Z（一般 0）
            #8 = 终点 Z（自动=-#5）

            【自动算的】
            #9 = 刀半径 + 2，起刀点离开工件的距离
            #10 = 半长，#11 = 半宽
            #12 = 半长 - #4，圆角/倒角的起点 X
            #13 = 当前 Z

            【改法举例】
            外形 120×80、R8、深 10、每层 3、Ø12 刀：
            #1=120  #2=80  #4=8  #5=10  #6=3  #3=12
            要 C5 倒角：把 #4 改成 5，并在界面上选「C 倒角」
            直角外形：#4 写 0，界面选「直角」

            【注意】
            - G41 是左刀补，程序顺时针绕一圈，刀才落在工件外侧；改成逆时针就必须换 G42
            - 有圆角时代码用 G2 R#4；有倒角时用两段 G1，#4 就是倒角边长
            - 退刀前必须有 G40，不然下一段还带着刀补
            - 每层别超过刀径的 60%，外形侧刃吃太多会震刀
            """
        case .key:
            return """
            【干什么用】
            键槽。每一层从上方直接落刀，沿槽下壁走到右端 → G3 铣右端 R → 沿上壁走回左端 → G3 铣左端 R，一个闭合的往复就铣完一层，再落下一层。两端 R 是 G3 单独铣出来的，不靠刀带。

            【上机前必须做】
            1. Z0 对在工件顶面
            2. G54 的 X0 Y0 对在键槽中心（槽长的中点），程序自动 G52 平移
            3. 刀径按实际填，槽宽/行程都是靠它算的

            【可以改的变量】
            #1 = 槽长（含两端圆弧的总长）
            #2 = 槽宽
            #3 = 刀具直径
            #4 = 总深
            #5 = 每层切深
            #6 = 起始 Z
            #7 = 终点 Z（自动=-#4）

            【自动算的】
            #8 = (槽长-槽宽)/2，两端圆弧的圆心 X
            #9 = 槽宽/2 - 刀径/2，端弧的刀心半径
            #13 当前 Z

            【改法举例】
            槽 40×12 深 5、用 Ø10 刀：
            #1=40  #2=12  #3=10 → #8=14，两端圆心在 ±14；#9=1，端弧刀心半径 1，一刀往复就铣满 12 宽
            槽 40×20 深 5、用 Ø12 刀：
            #2=20  #3=12 → #9=4，两刀（±4）正好盖满 20 宽

            【注意】
            - 刀径必须小于槽宽，两个 G3 的 R 才铣得出来；刀径等于槽宽时 R 只剩刀半径，等于没 R
            - 刀径要 ≥ 槽宽的一半，一个往复才盖满整宽；比一半还小中间会留料
            - 两个 G3 绝对不能删：G3 Y#9 I0. J#9 是右端，G3 Y-#9 I0. J-#9 是左端
            - 每层 #5 建议 ≤1mm（键槽刀可直扎）；用普通立铣刀请减到 0.3
            - 槽长 #1 是含圆弧的总长，不是直线段长度
            """
        case .face:
            return """
            【干什么用】
            铣平面。X 向一刀一刀往复，每一层走完整幅面再下一层，适合毛坯飞面、去黑皮。

            【上机前必须做】
            1. Z0 对在工件顶面
            2. G54 的 X0 Y0 对在矩形中心，程序会自动 G52 平移
            3. 刀具直径要填真实值，行距是按它自动算的

            【可以改的变量】
            #1 = 长（X 方向）
            #2 = 宽（Y 方向）
            #3 = 刀具直径
            #4 = 起始 Z（默认 0，从顶面开始）
            #5 = 终点 Z（负值，铣到多深就写多少）
            #6 = 每层切深

            【自动算的】
            #7 半长、#8 半宽、#9 行距（=75% 刀径）、#10 方向、#11 当前Z、#12 X位置

            【改法举例】
            毛坯要飞掉 2mm，每刀 0.5：
            #5=-2.  #6=0.5
            行距想更密，把 #9 那行改成 #9=[#3*0.6]

            【注意】
            - #5 必须比 #4 小（更负），否则循环一次都不进，程序空跑
            - 每一趟都先抬到 [#11+2] 再定位，不在材料里横着快走
            - 最后一层如果除不尽，会自动落到 #5，不会多切
            """
        case .spiral:
            return """
            【干什么用】
            螺旋铣圆形面或圆孔。刀具在刀心圆上一边走 G3 一边下降，从工件上方直接螺旋下刀，不用先扎到 Z0 再开始。每圈吃一层，Z 连续到底。

            【上机前必须做】
            1. Z0 对在工件顶面
            2. G54 的 X0 Y0 对在圆心，程序会自动 G52 平移
            3. 刀具直径填真实值——刀心圆半径就是靠它算的

            【可以改的变量】
            #1 = 圆直径（要铣的圆）
            #2 = 刀具直径
            #3 = 工件表面 Z（一般写 0）
            #4 = 终点 Z（负值）
            #5 = 每圈下刀量

            【自动算的】
            #6 = 刀心圆半径 =（圆直径-刀径）/2
            #7 = 当前 Z

            【改法举例】
            Ø50 的圆用 Ø30 刀：
            #1=50  #2=30 → 刀心半径自动 10
            和手工写的 G1 X-10.78 / G3 I10.78 是同一个意思，这个程序会自动算出来。

            【注意】
            - 刀具直径必须小于圆直径，等于或大于程序会拦下来
            - 每圈下刀量别超过刀尖强度，#5 建议 0.3~0.6
            - 下刀靠 G0 Z[#3+2.] + 后面整段 G3，全程螺旋，没有直插；照抄时别把它改回 G1 Z0
            - 想顺铣把 G3 改成 G2，同时 #6 前面加负号（G2 I-#6）
            """
        default:
            return """
            【干什么用】
            铣方形型腔，可做 R 圆角或 C 倒角。先分层粗铣把中间掏空，最后 G41 刀补精修一圈侧壁。

            【上机前必须做】
            1. Z0 对在工件顶面
            2. G54 的 X0 Y0 对在型腔中心，程序自动 G52 平移
            3. 刀补号 H（G43）和 D（G41）要用真实刀补号，别写死 D1

            【可以改的变量】
            #20 = 半长（长的一半，直接写数值）
            #21 = 半宽
            #22 = 刀具半径
            #3 = 总深
            #4 = 圆角 R 或倒角 C（直角就写 0）
            #6 = 每层切深
            #7 = 行距
            #9 = 进给
            #10 = 安全高度

            【自动算的】
            #23 当前深度、#24 环号、#27 环半长、#28 环半宽、#29 环圆角、#30 内缩量

            【改法举例】
            120×80 的腔、R8、Ø12 刀：
            #20=60  #21=40  #22=6  #4=8
            行距想细一点：#7 改成 5（别超过 #22 的两倍）

            【注意】
            - 刀具半径大于圆角 R 时，角上铣不出来，要换小刀清角
            - 行距 #7 大于刀径会留台阶
            - 精修段有 G41，上机前先在机床上空跑校验刀补方向
            - 程序里 #29 有 IF 保护，圆角算成负数会取 0.001，不会报警停机
            """
        }
    }

    private static func join(_ lines: [String]) -> String {
        var out: [String] = []
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { out.append(t) }
        }
        return out.joined(separator: "\n")
    }

    private static func cornerDesc(_ s: PocketSpec) -> String {
        switch s.cornerType {
        case .radius: return "R\(fmt(s.cornerValue, 2))"
        case .chamfer: return "C\(fmt(s.cornerValue, 2))"
        case .square: return "NONE"
        }
    }

    /// 精简写法：FANUC 自动倒圆/倒角 ,R / ,C
    private static func ringBlocksCompact(_ s: PocketSpec, skipFirst: Bool) -> [String] {
        var sfx = ""
        if s.cornerType == .radius { sfx = ",R[#29]" }
        else if s.cornerType == .chamfer { sfx = ",C[#29]" }
        var out: [String] = []
        if !skipFirst { out.append("G01X#27Y0F[#9]") }
        out.append("G01X#27Y#28" + sfx)
        out.append("G01X[-#27]Y#28" + sfx)
        out.append("G01X[-#27]Y[-#28]" + sfx)
        out.append("G01X#27Y[-#28]" + sfx)
        out.append("G01X#27Y0" + sfx)
        return out
    }

    /// 逆时针轮廓，从 (半长,0) 出发；与 G41 左补偿配合=内腔顺铣
    private static func ringBlocks(type: CornerType, approach: String? = nil) -> [String] {
        var out: [String] = []
        if let a = approach { out.append(a) }
        switch type {
        case .radius:
            out.append("G01 Y[#28-#29]")
            out.append("G03 X[#27-#29] Y#28 R#29")
            out.append("G01 X[#29-#27]")
            out.append("G03 X[-#27] Y[#28-#29] R#29")
            out.append("G01 Y[#29-#28]")
            out.append("G03 X[#29-#27] Y[-#28] R#29")
            out.append("G01 X[#27-#29]")
            out.append("G03 X#27 Y[#29-#28] R#29")
            out.append("G01 Y0")
        case .chamfer:
            out.append("G01 Y[#28-#29]")
            out.append("G01 X[#27-#29] Y#28")
            out.append("G01 X[#29-#27]")
            out.append("G01 X[-#27] Y[#28-#29]")
            out.append("G01 Y[#29-#28]")
            out.append("G01 X[#29-#27] Y[-#28]")
            out.append("G01 X[#27-#29]")
            out.append("G01 X#27 Y[#29-#28]")
            out.append("G01 Y0")
        case .square:
            out.append("G01 Y#28")
            out.append("G01 X[-#27]")
            out.append("G01 Y[-#28]")
            out.append("G01 X#27")
            out.append("G01 Y0")
        }
        return out
    }
}
