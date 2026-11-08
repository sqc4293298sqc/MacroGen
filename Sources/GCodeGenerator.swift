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
    var taperDepth: Double = 38
    var spiralDia: Double = 50      // 螺旋铣圆直径
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
        switch mode {
        case .taper: return taperIssues
        case .face: return faceIssues
        case .spiral: return spiralIssues
        default: return pocketIssues
        }
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

    private var faceIssues: [String] {
        var out: [String] = []
        if length <= 0 || width <= 0 { out.append("长宽必须大于 0") }
        if toolDia <= 0 { out.append("刀具直径必须大于 0") }
        if depth <= 0 { out.append("要去掉的总深度必须大于 0") }
        if stepDown <= 0 { out.append("每层切深必须大于 0") }
        if stepDown > depth { out.append("每层切深大于总深度，改小一点") }
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
        default: return generatePocket(s)
        }
    }

    // 螺旋铣：圆形面/圆孔，一圈一圈螺旋下刀
    private static func generateSpiral(_ s: PocketSpec) -> String {
        var L: [String] = []
        L.append("%")
        L.append("O1004 (螺旋铣宏程序)")
        L.append("G21 G40 G49 G80 G90 G\(s.coord)")
        L.append("G52 X\(fmt(s.cx)) Y\(fmt(s.cy)) (平移到圆心)")
        L.append("G43 H\(s.hNo) Z\(fmt(s.safeZ, 1))")
        L.append("M3 S\(s.spindle)")
        L.append("M8")
        L.append("#1=\(fmt(s.spiralDia, 1)) (圆直径)")
        L.append("#2=\(fmt(s.toolDia, 1)) (刀具直径)")
        L.append("#3=0 (起始Z)")
        L.append("#4=\(fmt(-s.depth, 3)) (终点Z)")
        L.append("#5=\(fmt(s.stepDown, 2)) (每圈下刀)")
        L.append("#6=[#1/2.-#2/2.] (刀心圆半径)")
        L.append("#7=#3 (当前Z)")
        L.append("G0 X-#6 Y0 (进到圆上)")
        L.append("G1 Z#3 F\(s.feed / 2)")
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
        L.append("M30")
        L.append("%")
        return join(L)
    }

    // 铣飞面：长宽刀径、起止Z、每层都可改，Z0 起刀逐层往复
    private static func generateFace(_ s: PocketSpec) -> String {
        var L: [String] = []
        L.append("%")
        L.append("O1003 (飞面宏程序)")
        L.append("G21 G40 G49 G80 G90 G\(s.coord)")
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
        L.append("#7=[#1/2.] (半长)")
        L.append("#8=[#2/2.] (半宽)")
        L.append("#9=[#3*0.75] (行距)")
        L.append("#10=1 (方向)")
        L.append("#11=#4 (当前Z)")
        L.append("WHILE[#11GT#5]DO1")
        L.append("#11=#11-#6")
        L.append("IF[#11LT#5]THEN#11=#5")
        L.append("#12=-#7 (X起点)")
        L.append("WHILE[#12LE#7]DO2")
        L.append("G0 Z[#11+2.]")
        L.append("G0 X#12 Y[#8*#10]")
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
        L.append("M30")
        L.append("%")
        return join(L)
    }

    // 各模式的新手使用说明（App 里显示在程序下方）
    static func manual(_ s: PocketSpec) -> String {
        switch s.mode {
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
            #6 当前深度、#11 大头半径、#7 刀尖R补偿、#8 Z向补偿、#12 刀心半径、#13 下刀 Z 都是程序自己算的。

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
            螺旋铣圆形面或圆孔。刀具在刀心圆上走 G3，每转一圈往下吃一层，Z 是连续下降的。

            【上机前必须做】
            1. Z0 对在工件顶面
            2. G54 的 X0 Y0 对在圆心，程序会自动 G52 平移
            3. 刀具直径填真实值——刀心圆半径就是靠它算的

            【可以改的变量】
            #1 = 圆直径（要铣的圆）
            #2 = 刀具直径
            #3 = 起始 Z
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
