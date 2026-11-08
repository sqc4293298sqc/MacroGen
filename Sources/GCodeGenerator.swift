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
    var taperRatio: Double = 2.38    // 锥度 1:N
    var taperAngle: Double = 22.83   // 全角（度）

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
        mode == .taper ? taperIssues : pocketIssues
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
        s.mode == .taper ? generateTaper(s) : generatePocket(s)
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
        L.append("G21 G40 G49 G80 G90 G\(s.coord)")
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
        L.append("G00 X[#27+6.] Y0")
        L.append("G01 Z#26 F[#9]")
        L.append("G41 D\(s.hNo) G01 X#27 Y0 F[#9]")
        if s.compact {
            L.append(contentsOf: ringBlocksCompact(s, skipFirst: true))
        } else {
            L.append(contentsOf: ringBlocks(type: s.cornerType))
        }
        L.append("G40 G01 X[#27+6.] Y0")
        L.append("G00 Z#10")
        L.append("G52 X0 Y0 (取消局部坐标)")
        L.append("M5")
        L.append("M9")
        L.append("G28 G91 Z0")
        L.append("G28 G91 Y0")
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
        L.append("G\(s.coord) G80 G90 G40 G49 G17")
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
        L.append("M1")
        L.append("%")
        return join(L)
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
