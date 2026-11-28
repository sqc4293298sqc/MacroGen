import Foundation

enum CornerType: String, CaseIterable, Identifiable {
    case radius = "R 圆角"
    case chamfer = "C 倒角"
    case square = "直角"

    var id: String { rawValue }
}

enum RCornerKind: String, CaseIterable, Identifiable, Hashable {
    case outerCylinder = "圆柱外R"
    case hole = "孔口R"
    case outerRect = "长方形外R"
    case slot = "槽底内R"

    var id: String { rawValue }
}

enum ArcKind: String, CaseIterable, Identifiable, Hashable {
    case inner = "内圆弧面"
    case outer = "外圆弧面"

    var id: String { rawValue }
}

enum MachiningMode: String, CaseIterable, Identifiable {
    case pocket = "方形型腔"
    case taper = "锥孔"
    case taperHelix = "锥孔螺旋"
    case face = "铣飞面"
    case spiral = "螺旋铣"
    case oblique = "非正交螺旋"
    case thread = "圆周螺纹"
    case key = "铣键槽"
    case outer = "只铣外方形"
    case innerChamfer = "内圆倒角"
    case odCham = "外圆倒角"
    case rCorner = "R角分层"
    case arcSurface = "圆弧面"

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

    // 外圆倒角（圆柱外缘端面倒角）
    var odDia: Double = 50           // 外圆直径
    var odAngle: Double = 90         // 锥角（全角）
    var odDepth: Double = 2          // 倒角深
    var odStep: Double = 0.1         // 每层

    // 铣斜面（在 face 上叠加；0 = 普通平面）
    var slopeAngle: Double = 0       // 正值向 +Y 下斜，负值向 -Y 下斜

    // 螺旋孔阵列
    var holeCount: Int = 1           // 1 = 单孔
    var holePatternRadius: Double = 60
    var holeStartAngle: Double = 0   // 度
    var holeAngleStep: Double = 0    // 0 = 360 / 孔数
    var obliqueAngle: Double = 70    // 非正交螺旋：孔轴在 XY 平面内旋转角

    // 圆周螺纹
    var threadDia: Double = 30       // 螺纹公称直径
    var threadPitch: Double = 3.5    // 螺距
    var threadLength: Double = 59.5  // 螺纹有效长度
    var threadTop: Double = 2        // 螺纹顶面 Z（相对工件顶面）
    var threadRadialStep: Double = 0.5 // 径向进刀步距

    // R 角分层
    var rKind: RCornerKind = .outerCylinder
    var rValue: Double = 15          // R 角半径
    var rAngleStep: Double = 3       // 沿 1/4 圆的角步距（度）
    var rCylinderDia: Double = 100   // 圆柱外 R 的圆柱直径
    var rHoleDia: Double = 100       // 孔口 R 的孔径

    // 圆弧面（往返排刀）
    var arcKind: ArcKind = .inner
    var arcTravel: Double = 122      // 单侧行程（X 从 -travel 到 +travel）
    var arcRadius: Double = 25       // 圆弧半径
    var arcStraightDepth: Double = 25 // 内圆弧的直边深度；外圆弧忽略
    var arcSweep: Double = 90        // 扫掠角度（度）
    var arcAngleStep: Double = 3     // 每刀角度步距（度）
    var arcCenterY: Double = -70     // 圆弧轴心相对工件中心的 Y 偏移

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
    var zTop: Double = 0             // 加工起始 Z；多台阶时是台阶顶面

    var toolRadius: Double { toolDia / 2 }
    var halfAngle: Double { atan((taperDia - taperDiaSmall) / (2 * taperDepth)) * 180 / .pi }

    var issues: [String] {
        switch mode {
        case .taper: return taperIssues
        case .taperHelix: return taperHelixIssues
        case .face: return faceIssues
        case .spiral: return spiralIssues
        case .oblique: return obliqueIssues
        case .thread: return threadIssues
        case .key: return keyIssues
        case .outer: return outerIssues
        case .innerChamfer: return chamferIssues
        case .odCham: return odChamIssues
        case .rCorner: return rCornerIssues
        case .arcSurface: return arcIssues
        default: return pocketIssues
        }
    }

    private var rCornerIssues: [String] {
        var out: [String] = []
        if rValue <= 0 { out.append("R 角必须大于 0") }
        if toolDia <= 0 { out.append("刀具直径必须大于 0") }
        if toolCornerR < 0 { out.append("刀尖 R 不能为负") }
        if toolCornerR > toolRadius { out.append("刀尖 R 不能大于刀具半径") }
        if rAngleStep <= 0 { out.append("角度步距必须大于 0") }
        if rAngleStep < 0.5 { out.append("角度步距太小，层数过多；建议 0.5° 以上") }
        if rAngleStep > 30 { out.append("角度步距建议不超过 30°，否则 R 面会有明显棱") }

        switch rKind {
        case .outerCylinder:
            if rCylinderDia <= 0 { out.append("圆柱直径必须大于 0") }
            if toolDia >= rCylinderDia { out.append("刀具直径必须小于圆柱直径") }
            if rValue > rCylinderDia / 2 { out.append("R 角不能大于圆柱半径") }
            if (toolDia + rCylinderDia) / 2 <= toolCornerR + rValue {
                out.append("刀尖 R + R 角太大，顶层刀心半径会小于等于 0")
            }
        case .hole:
            if rHoleDia <= 0 { out.append("孔径必须大于 0") }
            if toolDia >= rHoleDia { out.append("刀具直径必须小于孔径，否则刀进不去") }
            if rValue > rHoleDia / 2 { out.append("R 角不能大于孔半径") }
            if (rHoleDia - toolDia) / 2 <= 1 {
                out.append("孔径减刀径太小，孔口 R 没有足够刀心半径")
            }
        case .outerRect:
            if length <= 0 || width <= 0 { out.append("长宽必须大于 0") }
            if rValue >= min(length, width) / 2 { out.append("R 角必须小于工件最小边的一半") }
            if toolDia - 2 * toolCornerR <= 0 {
                out.append("刀尖 R 太大，刀具有效平底部分小于等于 0")
            }
        case .slot:
            if length <= 0 || width <= 0 { out.append("槽长、槽宽必须大于 0") }
            if depth <= 0 { out.append("槽深必须大于 0") }
            let centerR = rValue - toolDia / 2
            let verticalR = centerR - toolCornerR
            let halfW = (width - 2 * centerR - toolDia) / 2
            let halfL = (length - 2 * centerR - toolDia) / 2
            if centerR <= 0 { out.append("R 角必须大于刀具半径，否则刀心没有 R 可走") }
            if verticalR <= 0 { out.append("R 角减刀半径再减刀尖 R 太小，没有垂直分层空间") }
            if halfW <= 0 { out.append("槽宽太小：扣掉 R 角和刀径后没有直线段") }
            if halfL <= 0 { out.append("槽长太小：扣掉 R 角和刀径后没有直线段") }
            if verticalR > depth { out.append("槽深不够容纳 R 角的垂直分层") }
        }
        return out
    }

    private var odChamIssues: [String] {
        var out: [String] = []
        let half = odAngle / 2 * .pi / 180
        let w = odDepth * tan(half)
        if odDia <= 0 { out.append("外圆直径必须大于 0") }
        if toolDia <= 0 { out.append("刀具直径必须大于 0") }
        if toolDia >= odDia { out.append("刀具直径必须小于外圆直径，否则整个盖面都会被切") }
        if odDepth <= 0 { out.append("倒角深必须大于 0") }
        if odAngle <= 1 || odAngle >= 179 { out.append("锥角应在 1~179 度之间（按图纸全角填）") }
        if odStep <= 0 { out.append("每层切深必须大于 0") }
        if odStep > odDepth + 1e-9 { out.append("每层切深大于倒角深，改小一点") }
        if w >= odDia / 2 { out.append("倒角宽超过外圆半径，改小倒角深或锥角") }
        return out
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
        if abs(slopeAngle) >= 80 { out.append("斜面角应小于 80°，否则每层 Y 偏移过大") }
        let shift = abs(depth * tan(slopeAngle * .pi / 180))
        if slopeAngle != 0 && shift > width / 2 + toolDia * 2 {
            out.append("斜面角/深度让 Y 偏移超过毛坯范围，检查工件宽度或角度")
        }
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
        if holeCount < 1 { out.append("孔数至少为 1") }
        if holeCount > 200 { out.append("孔数过多，最多 200 个") }
        if holeCount > 1 {
            if holePatternRadius <= 0 { out.append("多孔时分布半径必须大于 0") }
            if holePatternRadius < spiralDia / 2 { out.append("分布半径小于孔半径，孔会重叠") }
            if holeAngleStep < 0 { out.append("角步距不能为负") }
        }
        return out
    }

    private var obliqueIssues: [String] {
        var out: [String] = []
        if spiralDia <= 0 { out.append("孔径必须大于 0") }
        if toolDia <= 0 { out.append("刀具直径必须大于 0") }
        if toolDia >= spiralDia { out.append("刀具直径必须小于孔径") }
        if depth <= 0 { out.append("加工深度必须大于 0") }
        if stepDown <= 0 { out.append("每圈下刀量必须大于 0") }
        if obliqueAngle < -360 || obliqueAngle > 360 { out.append("旋转角必须在 -360°~360° 之间") }
        let turns = Int(ceil(depth / max(stepDown, 0.001)))
        if turns > 2000 { out.append("圈数过多，建议增大每圈切深") }
        return out
    }

    private var threadIssues: [String] {
        var out: [String] = []
        if threadDia <= 0 { out.append("螺纹直径必须大于 0") }
        if toolDia <= 0 { out.append("螺纹刀直径必须大于 0") }
        if toolDia >= threadDia { out.append("螺纹刀直径必须小于螺纹直径") }
        if threadPitch <= 0 { out.append("螺距必须大于 0") }
        if threadLength <= 0 { out.append("螺纹长度必须大于 0") }
        if threadLength < threadPitch { out.append("螺纹长度小于一个螺距，至少加长到 1 个螺距") }
        if threadRadialStep <= 0 { out.append("径向步距必须大于 0") }
        if (threadDia - toolDia) / 2 <= 0 { out.append("螺纹直径减刀径太小，刀心没有径向空间") }
        if holeCount < 1 { out.append("孔数至少为 1") }
        if holeCount > 200 { out.append("孔数过多，最多 200 个") }
        if holeCount > 1 {
            if holePatternRadius <= 0 { out.append("多孔时分布半径必须大于 0") }
            if holePatternRadius < threadDia / 2 { out.append("分布半径小于螺纹半径，孔会重叠") }
            if holeAngleStep < 0 { out.append("角步距不能为负") }
        }
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

    private var taperHelixIssues: [String] {
        var out: [String] = []
        if taperDia <= 0 || taperDiaSmall <= 0 { out.append("大头/小头必须大于 0") }
        if taperDia <= taperDiaSmall { out.append("大头必须大于小头") }
        if taperDepth <= 0 { out.append("深度必须大于 0") }
        if toolDia <= 0 { out.append("刀具直径必须大于 0") }
        if taperDia <= toolDia { out.append("大头必须大于刀径") }
        if taperDiaSmall <= toolDia { out.append("小头必须大于刀径，否则底部没有刀心半径") }
        if stepDown <= 0 { out.append("每圈下刀量必须大于 0") }
        if stepDown > taperDepth { out.append("每圈下刀量大于总深，改小一点") }
        let turns = Int(ceil(taperDepth / max(stepDown, 0.001)))
        if turns > 2000 { out.append("圈数过多，建议增大每圈下刀量") }
        return out
    }

    private var arcIssues: [String] {
        var out: [String] = []
        if arcTravel <= 0 { out.append("单侧行程必须大于 0") }
        if arcRadius <= 0 { out.append("圆弧半径必须大于 0") }
        if arcAngleStep <= 0 { out.append("角度步距必须大于 0") }
        if arcAngleStep > 30 { out.append("角度步距建议不超过 30°，否则弧面有明显棱") }
        if arcSweep <= 0 || arcSweep > 90 { out.append("扫掠角度必须在 0~90° 之间") }
        if toolDia <= 0 { out.append("刀具直径必须大于 0") }
        if arcKind == .inner {
            if arcStraightDepth < 0 { out.append("直边深度不能为负") }
            if arcRadius * 2 < toolDia { out.append("圆弧半径太小，刀进不去；R 至少大于刀半径") }
        } else {
            if toolCornerR < 0 || toolCornerR > toolRadius { out.append("刀尖 R 不能大于刀具半径") }
            let calcR = toolCornerR + arcRadius
            if calcR <= 0 { out.append("刀尖 R + 圆弧半径必须大于 0") }
            if arcRadius < toolCornerR { out.append("外圆弧半径建议大于刀尖 R，否则实际计算半径过小") }
        }
        let passes = Int(ceil(arcSweep / max(arcAngleStep, 0.001)))
        if passes > 1000 { out.append("扫掠刀数过多，建议增大角度步距") }
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
        case .taperHelix: return generateTaperHelix(s)
        case .face: return generateFace(s)
        case .spiral: return generateSpiral(s)
        case .oblique: return generateOblique(s)
        case .thread: return generateThread(s)
        case .key: return generateKey(s)
        case .outer: return generateOuter(s)
        case .innerChamfer: return generateInnerChamfer(s)
        case .odCham: return generateODCham(s)
        case .rCorner: return generateRCorner(s)
        case .arcSurface: return generateArcSurface(s)
        default: return generatePocket(s)
        }
    }

    // MARK: - 外圆倒角（圆柱外缘端面倒角）
    private static func generateODCham(_ s: PocketSpec) -> String {
        let half = s.odAngle / 2 * .pi / 180
        let w = s.odDepth * tan(half)
        let topDia = s.odDia - 2 * w
        let plunge = max(50, s.feed / 3)
        var L: [String] = []
        L.append("%")
        L.append("O1007 (外圆倒角宏程序)")
        L.append("( 外圆Ø\(fmt(s.odDia, 2))  锥角\(fmt(s.odAngle, 1))°  深\(fmt(s.odDepth, 2))  刀Ø\(fmt(s.toolDia, 2)) )")
        L.append("( 倒角宽\(fmt(w, 2))  顶口Ø\(fmt(topDia, 2))  每层\(fmt(s.odStep, 3))  中心X=\(fmt(s.cx, 2)) Y=\(fmt(s.cy, 2)) )")
        L.append("( Z0=工件上表面  圆柱外缘端面倒角 )")
        L.append("( 由 MacroGen 生成 上机前请核对 )")
        L.append("G17 G21 G40 G49 G80 G90 G\(s.coord)")
        let shift = abs(s.cx) > 1e-9 || abs(s.cy) > 1e-9
        if shift {
            L.append("G52 X\(fmt(s.cx, 3)) Y\(fmt(s.cy, 3)) (平移到圆心)")
        } else {
            L.append("( X0 Y0 就是 G\(s.coord) 零点, 不对刀就不用改 )")
        }
        L.append("G43 H\(s.hNo) Z\(fmt(s.safeZ, 1))")
        L.append("M3 S\(s.spindle)")
        L.append("M8")
        L.append("#1=\(fmt(s.odDia, 2)) (外圆直径)")
        L.append("#2=\(fmt(s.toolDia, 2)) (刀径)")
        L.append("#3=\(fmt(s.odDepth, 2)) (倒角深)")
        L.append("#4=\(fmt(s.odStep, 3)) (每层)")
        L.append("#5=\(fmt(s.odAngle, 1)) (锥角 全角)")
        L.append("#6=\(plunge) (下刀F)")
        L.append("#7=\(s.feed) (圆周F)")
        L.append("#25=TAN[#5/2.] (半角正切)")
        L.append("#26=FIX[#3/#4] (层数)")
        L.append("IF[#26LT1]THEN#26=1 (至少一层)")
        L.append("#20=0 (层号)")
        L.append("#21=[[#1/2.]-[#3*#25]]+[#2/2.] (顶层刀心半径)")
        L.append("G0 Z[#3+2.] (到锥面起点上方)")
        L.append("G0 X#21 Y0 (对准顶口)")
        L.append("G1 Z0 F#6 (只下到工件表面, 刀已经在倒角位置)")
        L.append("( === 一圈一圈螺旋下, 中途不抬刀 === )")
        L.append("WHILE[#20LT#26]DO1")
        L.append("#20=#20+1")
        L.append("#22=[#20*#4] (本层深度Z)")
        L.append("#23=[[#1/2.]-[[#3-#22]*#25]]+[#2/2.] (本层刀心半径)")
        L.append("G3 I-#21 Z-#22 F#7 (整圆螺旋, 一圈降一层)")
        L.append("G1 X#23 F#6 (径向外挪一层, 不抬刀)")
        L.append("#21=#23")
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
        return join(L)
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
        L.append("IF[#26LT1]THEN#26=1 (至少一层)")
        L.append("#20=0 (层号)")
        L.append("#21=[[#1/2.]+[#3*#25]]-[#2/2.] (顶层刀心半径)")
        L.append("G0 Z[#3+2.] (到孔口上方)")
        L.append("G0 X#21 Y0 (对准顶口)")
        L.append("G1 Z0 F#6 (只下到工件表面, 刀已经在倒角位置)")
        L.append("( === 一圈一圈螺旋下, 中途不抬刀 === )")
        L.append("WHILE[#20LT#26]DO1")
        L.append("#20=#20+1")
        L.append("#22=[#20*#4] (本层深度Z)")
        L.append("#23=[[#1/2.]+[[#3-#22]*#25]]-[#2/2.] (本层刀心半径)")
        L.append("G2 I-#21 Z-#22 F#7 (整圆螺旋, 一圈降一层)")
        L.append("G1 X#23 F#6 (径向内收一层, 不抬刀)")
        L.append("#21=#23")
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
        L.append("#9=[#3/2.+2.] (半圆弧进刀半径)")
        L.append("#10=[#1/2.] (半长)")
        L.append("#11=[#2/2.] (半宽)")
        L.append("#12=[#10-#4] (角起点X)")
        L.append("#13=#7 (当前Z)")
        L.append("WHILE[#13GT#8]DO1")
        L.append("#13=#13-#6")
        L.append("IF[#13LT#8]THEN#13=#8")
        L.append("G0 Z[#13+2.] (抬到本层上方2mm)")
        L.append("G0 X0 Y[#11+#9*2.] (到上边中点正上方)")
        L.append("G1 Z#13 F\(s.feed / 2) (落刀到本层)")
        L.append("G41 D\(s.hNo) G3 X0 Y#11 I0 J-#9 F\(s.feed) (半圆弧切向进刀, 刀在轮廓外)")
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
        L.append("G1 X0 F\(s.feed) (上边回到中点)")
        L.append("G40 G3 X0 Y[#11+#9*2.] J#9 F\(s.feed) (半圆弧切向退刀)")
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
        L.append("#4=\(fmt(s.zTop, 3)) (起始Z，含毛坯顶面余量)")
        L.append("#5=\(fmt(-s.depth, 3)) (终点Z)")
        L.append("#6=\(fmt(s.stepDown, 2)) (每层)")
        L.append("#7=[#1/2.+#3/2.] (半长+刀半径，刀心走出工件边缘)")
        L.append("#8=[#2/2.+#3/2.] (半宽+刀半径，进出刀都在料外)")
        L.append("#9=[#3*0.75] (行距)")
        L.append("#10=1 (方向)")
        L.append("#11=#4 (当前Z)")
        L.append("#13=TAN[\(fmt(s.slopeAngle, 3))] (斜面：每下降1mm的Y偏移；0=平面)")
        L.append("#14=0 (当前层Y偏移)")
        L.append("WHILE[#11GT#5]DO1")
        L.append("#11=#11-#6")
        L.append("IF[#11LT#5]THEN#11=#5")
        L.append("#14=#13*[#4-#11] (当前层斜面偏移)")
        L.append("#12=-#7 (X起点)")
        L.append("WHILE[#12LE#7]DO2")
        L.append("G0 Z[#4+2.] (抬到工件表面上方2mm再横移)")
        L.append("G0 X#12 Y[#8*#10+#14]")
        L.append("G0 Z[#11+0.5]")
        L.append("G1 Z#11 F\(s.feed / 2)")
        L.append("G1 Y[-#8*#10+#14] F\(s.feed)")
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
        L.append("#10=#9 (当前行半径)")
        L.append("#11=\(fmt(max(0.5, s.toolDia * 0.75))) (自动分行距，75%刀径)")
        L.append("#13=#6 (当前Z)")
        L.append("WHILE[#13GT#7]DO1")
        L.append("#13=#13-#5")
        L.append("IF[#13LT#7]THEN#13=#7")
        L.append("G0 Z[#13+2.] (抬到本层上方2mm)")
        L.append("G0 X0 Y0 (在槽中心落刀，别贴壁下刀)")
        L.append("G1 Z#13 F\(s.feed / 2) (落刀到本层)")
        L.append("#10=#9 (每层从最外圈重新开始)")
        L.append("WHILE[#10GT0.]DO2")
        L.append("G1 X-#8 Y-#10 F\(s.feed / 2) (切到左端弧起点)")
        L.append("G1 X#8 F\(s.feed) (下壁走到右端)")
        L.append("G3 Y#10 I0. J#10 F\(s.feed) (右端圆弧 R)")
        L.append("G1 X-#8 F\(s.feed) (上壁走回左端)")
        L.append("G3 Y-#10 I0. J-#10 F\(s.feed) (左端圆弧 R)")
        L.append("#10=#10-#11 (向内收一行)")
        L.append("END2")
        L.append("G1 X-#8 Y0 F\(s.feed / 2) (最后一刀走槽中心)")
        L.append("G1 X#8 F\(s.feed)")
        L.append("G1 X-#8 F\(s.feed) (把中间残留清干净)")
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
        let patternR = s.holeCount > 1 ? s.holePatternRadius : 0
        L.append("%")
        L.append("O1004 (螺旋铣宏程序)")
        L.append("( 圆Ø\(fmt(s.spiralDia, 1))  深\(fmt(s.depth, 2))  每圈\(fmt(s.stepDown, 2))  孔数\(s.holeCount) )")
        L.append("G17 G21 G40 G49 G80 G90 G\(s.coord)")
        L.append("G52 X\(fmt(s.cx)) Y\(fmt(s.cy)) (平移到基准中心)")
        L.append("G43 H\(s.hNo) Z\(fmt(s.safeZ + s.zTop, 1))")
        L.append("M3 S\(s.spindle)")
        L.append("M8")
        L.append("#1=\(fmt(s.spiralDia, 1)) (圆直径)")
        L.append("#2=\(fmt(s.toolDia, 1)) (刀具直径)")
        L.append("#3=\(fmt(s.zTop, 1)) (工件表面Z)")
        L.append("#4=\(fmt(s.zTop - s.depth, 3)) (终点Z)")
        L.append("#5=\(fmt(s.stepDown, 2)) (每圈下刀)")
        L.append("#6=[#1/2.-#2/2.] (刀心圆半径)")
        L.append("IF[#6LT0.01]THEN#6=0.01 (防半径算成 0 或负数)")
        L.append("#30=\(s.holeCount) (孔数)")
        L.append("#31=\(fmt(patternR, 3)) (圆周分布半径；单孔=0)")
        L.append("#32=\(fmt(s.holeStartAngle, 3)) (起始角)")
        L.append("#33=\(fmt(s.holeAngleStep, 3)) (角步距；0=自动)")
        L.append("IF[#33EQ0]THEN#33=360./#30 (自动均分)")
        L.append("#34=0 (孔号)")
        L.append("WHILE[#34LT#30]DO1")
        L.append("#35=COS[#32+#34*#33]*#31 (当前孔X)")
        L.append("#36=SIN[#32+#34*#33]*#31 (当前孔Y)")
        L.append("G52 X[\(fmt(s.cx))+#35] Y[\(fmt(s.cy))+#36] (平移到当前孔中心)")
        L.append("#7=#3 (当前Z)")
        L.append("G0 X-#6 Y0 (进到当前孔的圆上)")
        L.append("G0 Z[#3+2.] (只到工件上方2mm，不再直插到Z0)")
        L.append("WHILE[#7GT#4]DO2")
        L.append("#7=#7-#5")
        L.append("IF[#7LT#4]THEN#7=#4")
        L.append("G3 I#6 Z#7 F\(s.feed)")
        L.append("END2")
        L.append("G0 Z\(fmt(s.safeZ + s.zTop, 1))")
        L.append("#34=#34+1")
        L.append("END1")
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

    // MARK: - 非正交螺旋铣孔（孔轴在 XY 平面内旋转）
    private static func generateOblique(_ s: PocketSpec) -> String {
        let radius = (s.spiralDia - s.toolDia) / 2
        let turns = max(1, Int(ceil(s.depth / max(s.stepDown, 0.001))))
        let totalDeg = Double(turns) * 360
        let perDeg = s.depth / totalDeg
        let entryX = -max(10, s.spiralDia / 2 + 5)
        var L: [String] = []
        L.append("%")
        L.append("O1012 (非正交螺旋铣孔)")
        L.append("( 孔Ø\(fmt(s.spiralDia, 2)) 刀Ø\(fmt(s.toolDia, 2)) 深\(fmt(s.depth, 2)) 旋转\(fmt(s.obliqueAngle, 2))° )")
        L.append("( 圈数\(turns) 每圈\(fmt(s.stepDown, 2)) 总角度\(fmt(totalDeg, 1))° 中心X\(fmt(s.cx, 2)) Y\(fmt(s.cy, 2)) )")
        L.append("( G68 先把孔轴在 XY 平面内旋转；X 进给，YZ 走圆，到底再走一圈平底 )")
        L.append("( 由 MacroGen 生成 上机前请核对 )")
        L.append("G17 G21 G40 G49 G80 G90 G\(s.coord)")
        L.append("G52 X\(fmt(s.cx, 3)) Y\(fmt(s.cy, 3)) Z\(fmt(s.zTop, 3))")
        L.append("G43 H\(s.hNo) Z\(fmt(s.safeZ + s.zTop, 1))")
        L.append("M3 S\(s.spindle)")
        L.append("M8")
        L.append("#20=\(fmt(s.toolDia, 2)) (刀具直径)")
        L.append("#21=\(fmt(s.spiralDia, 2)) (孔径)")
        L.append("#22=\(fmt(s.obliqueAngle, 2)) (旋转角度)")
        L.append("#2=[#21-#20]/2 (刀心圆半径)")
        L.append("#5=\(turns) (圈数)")
        L.append("#6=\(fmt(totalDeg, 1)) (总角度)")
        L.append("#4=\(fmt(perDeg, 9)) (每度X进给)")
        L.append("#10=\(fmt(s.depth, 3)) (加工深度)")
        L.append("G68 X0 Y0 R#22 (旋转孔轴)")
        L.append("G0 X\(fmt(entryX, 2)) Y0 Z0 (XY 安全位)")
        L.append("G1 X0 F\(s.feed) (直线切到孔口中心)")
        L.append("#1=0 (角度)")
        L.append("WHILE[#1LE#6]DO1")
        L.append("#7=SIN[#1]*#2 (YZ 圆的 Z)")
        L.append("#8=COS[#1]*#2 (YZ 圆的 Y)")
        L.append("#9=#4*#1 (沿孔轴的 X)")
        L.append("G1 X#9 Y#8 Z-#7 F\(s.feed)")
        L.append("#1=#1+1")
        L.append("END1")
        L.append("#11=0 (平底起始角)")
        L.append("WHILE[#11LE360]DO2")
        L.append("#13=SIN[#11]*#2 (平底 Z)")
        L.append("#14=COS[#11]*#2 (平底 Y)")
        L.append("G1 Z-#13 Y#14 F\(s.feed)")
        L.append("#11=#11+1")
        L.append("END2")
        L.append("G1 Y0 Z0 (切到圆心)")
        L.append("G0 X\(fmt(entryX, 2)) (退刀)")
        L.append("G69 (取消旋转)")
        L.append("G52 X0 Y0 Z0")
        L.append("M5")
        L.append("M9")
        L.append("G28 G91 Z0")
        L.append("G28 G91 Y0")
        L.append("G90")
        L.append("M30")
        L.append("%")
        return join(L)
    }

    // MARK: - 圆周分布铣螺纹
    private static func generateThread(_ s: PocketSpec) -> String {
        let centerR = (s.threadDia - s.toolDia) / 2
        let radialStep = max(0.1, s.threadRadialStep)
        let radialStart = max(0.1, centerR - 2 * radialStep)
        let radialEnd = max(radialStart, centerR)
        let holeN = max(1, s.holeCount)
        let patternR = holeN > 1 ? s.holePatternRadius : 0
        let angleStep = s.holeAngleStep == 0 ? 360 / Double(holeN) : s.holeAngleStep
        let bottom = s.threadTop - s.threadLength
        var L: [String] = []
        L.append("%")
        L.append("O1013 (圆周分布铣螺纹)")
        L.append("( M\(fmt(s.threadDia, 1)) 螺纹  螺距\(fmt(s.threadPitch, 2))  长\(fmt(s.threadLength, 2)) )")
        L.append("( 螺纹刀Ø\(fmt(s.toolDia, 2))  孔数\(holeN)  分布R\(fmt(patternR, 2))  起始角\(fmt(s.holeStartAngle, 2))° )")
        L.append("( 径向\(fmt(radialStart, 2))→\(fmt(radialEnd, 2)) 步距\(fmt(radialStep, 2))  Z\(fmt(bottom, 3))→\(fmt(s.threadTop, 3)) )")
        L.append("( 由 MacroGen 生成 上机前请核对 )")
        L.append("G17 G21 G40 G49 G80 G90 G\(s.coord)")
        L.append("G43 H\(s.hNo) Z\(fmt(s.safeZ + s.zTop, 1))")
        L.append("M3 S\(s.spindle)")
        L.append("M8")
        L.append("#20=\(fmt(angleStep, 3)) (夹角度数)")
        L.append("#24=\(holeN) (孔数)")
        L.append("#4=\(fmt(patternR, 3)) (圆周分布半径；单孔=0)")
        L.append("#10=\(fmt(s.holeStartAngle, 3)) (起始角度)")
        L.append("#1=\(fmt(bottom, 3)) (螺纹起始Z)")
        L.append("#2=\(fmt(s.threadTop, 3)) (螺纹终止Z)")
        L.append("#3=\(fmt(radialStart, 3)) (起始单边切削量)")
        L.append("#21=\(fmt(radialEnd, 3)) (最终单边切削量)")
        L.append("#22=\(fmt(radialStep, 3)) (径向步距)")
        L.append("#23=\(fmt(s.threadPitch, 3)) (螺距)")
        L.append("G0 Z\(fmt(s.safeZ, 1))")
        L.append("WHILE[#10LT360]DO1")
        L.append("#5=SIN[#10]*#4 (Y 偏移)")
        L.append("#6=COS[#10]*#4 (X 偏移)")
        L.append("G52 X[\(fmt(s.cx, 3))+#6] Y[\(fmt(s.cy, 3))+#5] Z\(fmt(s.zTop, 3))")
        L.append("X0 Y0")
        L.append("#3=\(fmt(radialStart, 3))")
        L.append("WHILE[#3LE#21]DO2")
        L.append("#1=\(fmt(bottom, 3))")
        L.append("G0 Z[#1-#23] (下到螺纹底部以下一个螺距)")
        L.append("G1 X#3 Y0 F\(s.feed) (径向进到切削半径)")
        L.append("WHILE[#1LE#2]DO3")
        L.append("G03 I-#3 Z#1 F\(s.feed)")
        L.append("#1=#1+#23")
        L.append("END3")
        L.append("G1 X0")
        L.append("#3=#3+#22")
        L.append("END2")
        L.append("G0 Z\(fmt(s.safeZ, 1))")
        L.append("#10=#10+#20")
        L.append("G52 X0 Y0 Z0")
        L.append("END1")
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
        L.append("#25=#20 (最小半边长，先按半长)")
        L.append("IF[#21LT#25]THEN#25=#21 (窄边小于长边时用半宽)")
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
        L.append("WHILE[[#22+#24*#7]LE[#25-0.5]]DO2")
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
        L.append("G17 G21 G\(s.coord) G80 G90 G40 G49")
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
        L.append("#12=[#11+#7-#4/2.] (顶层刀心半径)")
        L.append("G0 X#12 Y0 (对准锥口)")
        L.append("G0 Z[#8+2.] (到工件上方)")
        L.append("G1 Z#8 F[#9/2.] (下到锥面起点)")
        L.append("( === 一圈一圈螺旋下, 中途不抬刀 === )")
        L.append("WHILE[#6LT#21]DO2")
        L.append("#6=#6+#16")
        L.append("IF[#6GT#21]THEN#6=#21")
        L.append("#13=[#8-#6](本层Z)")
        L.append("#14=[#11+#7-#4/2.-#6*TAN[#3]](本层刀心半径)")
        L.append("IF[#14LT.001]THEN#14=.001")
        L.append("G3 I-#12 Z#13 F[#9](整圆螺旋, 一圈降一层)")
        L.append("G1 X#14 F[#9](径向内收一层, 不抬刀)")
        L.append("#12=#14")
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

    // MARK: - 锥孔螺旋（图例 15 的简化算法）
    private static func generateTaperHelix(_ s: PocketSpec) -> String {
        let topR = (s.taperDia - s.toolDia) / 2
        let botR = (s.taperDiaSmall - s.toolDia) / 2
        let turns = max(1, Int(ceil(s.taperDepth / max(s.stepDown, 0.001))))
        let totalDeg = Double(turns) * 360
        let perDegZ = s.taperDepth / totalDeg
        let shrink = (topR - botR) / totalDeg
        var L: [String] = []
        L.append("%")
        L.append("O1014 (锥孔螺旋)")
        L.append("( 大头Ø\(fmt(s.taperDia, 2)) 小头Ø\(fmt(s.taperDiaSmall, 2)) 深\(fmt(s.taperDepth, 2)) 刀Ø\(fmt(s.toolDia, 2)) )")
        L.append("( 刀心R \(fmt(topR, 3))→\(fmt(botR, 3)) 圈数\(turns) 每圈\(fmt(s.stepDown, 2)) )")
        L.append("( 中心X\(fmt(s.cx, 2)) Y\(fmt(s.cy, 2)) Z0=顶面；由 MacroGen 生成 上机前请核对 )")
        L.append("G17 G21 G40 G49 G80 G90 G\(s.coord)")
        L.append("G52 X\(fmt(s.cx, 3)) Y\(fmt(s.cy, 3)) Z\(fmt(s.zTop, 3))")
        L.append("G43 H\(s.hNo) Z\(fmt(s.safeZ + s.zTop, 1))")
        L.append("M3 S\(s.spindle)")
        L.append("M8")
        L.append("#1=\(fmt(topR, 4)) (大头刀心半径)")
        L.append("#2=\(fmt(botR, 4)) (小头刀心半径)")
        L.append("#4=\(fmt(s.stepDown, 4)) (每圈下刀量)")
        L.append("#7=\(turns) (圈数)")
        L.append("#6=\(fmt(totalDeg, 1)) (总角度)")
        L.append("#5=\(fmt(perDegZ, 9)) (每度下刀量)")
        L.append("#8=\(fmt(shrink, 9)) (每度半径缩小值)")
        L.append("#3=0 (起始角度)")
        L.append("G0 X0 Y0")
        L.append("WHILE[#3LE#6]DO1")
        L.append("#11=#8*#3 (当前半径缩小量)")
        L.append("#13=[#1-#11]*COS[#3] (X)")
        L.append("#14=[#1-#11]*SIN[#3] (Y)")
        L.append("#15=#5*#3 (当前Z)")
        L.append("G1 X-#13 Y-#14 Z-#15 F\(s.feed)")
        L.append("#3=#3+1")
        L.append("END1")
        L.append("G03 I#2 F\(s.feed) (平底整圆)")
        L.append("G1 X0")
        L.append("G0 Z\(fmt(s.safeZ, 1))")
        L.append("G52 X0 Y0 Z0")
        L.append("M5")
        L.append("M9")
        L.append("G28 G91 Z0")
        L.append("G28 G91 Y0")
        L.append("G90")
        L.append("M30")
        L.append("%")
        return join(L)
    }

    // MARK: - 圆弧面（往返排刀）
    private static func generateArcSurface(_ s: PocketSpec) -> String {
        let inner = s.arcKind == .inner
        let travel = max(0.001, s.arcTravel)
        let sweep = min(90, max(0.001, s.arcSweep))
        let step = max(0.001, s.arcAngleStep)
        let calcR = inner ? s.arcRadius : s.toolCornerR + s.arcRadius
        let zBase = inner ? s.zTop : s.zTop - calcR
        let lift = inner ? s.safeZ : s.safeZ + calcR
        let g52Y = s.cy + s.arcCenterY
        var L: [String] = []
        L.append("%")
        L.append(inner ? "O1015 (内圆弧面 往返排刀)" : "O1016 (外圆弧面 往返排刀)")
        L.append("( R\(fmt(s.arcRadius, 2)) 单侧行程\(fmt(travel, 1)) 扫掠\(fmt(sweep, 1))° 角度步距\(fmt(step, 1))° )")
        L.append("( 刀Ø\(fmt(s.toolDia, 2)) 刀尖R\(fmt(s.toolCornerR, 2)) 轴心Y\(fmt(g52Y, 2)) )")
        L.append("( 由 MacroGen 生成 上机前请核对 )")
        L.append("G17 G21 G40 G49 G80 G90 G\(s.coord)")
        L.append("G52 X\(fmt(s.cx, 3)) Y\(fmt(g52Y, 3)) Z\(fmt(zBase, 3))")
        L.append("G43 H\(s.hNo) Z\(fmt(lift, 1))")
        L.append("M3 S\(s.spindle)")
        L.append("M8")
        L.append("#3=\(fmt(travel, 3)) (单侧行程)")
        if inner {
            L.append("#4=\(fmt(s.arcStraightDepth, 3)) (直边深度)")
        } else {
            L.append("#4=\(fmt(s.toolCornerR, 3)) (刀片R角)")
        }
        L.append("#5=\(fmt(s.arcRadius, 3)) (圆弧半径)")
        if !inner {
            L.append("#6=#4+#5 (实际计算圆弧半径)")
        }
        L.append("#1=0 (第一刀角度)")
        L.append("#2=\(fmt(sweep, 1)) (最终角度)")
        L.append("G0 X-#3 Y0")
        L.append("WHILE[#1LE#2]DO1")
        if inner {
            L.append("#6=#4+SIN[#1]*#5 (当前Z深度)")
            L.append("#7=COS[#1]*#5 (当前Y移动量)")
            L.append("G0 Z-#6")
            L.append("G0 Y#7")
        } else {
            L.append("#7=COS[#1]*#6 (当前Z)")
            L.append("#8=SIN[#1]*#6 (当前Y移动量)")
            L.append("G0 Y-#8")
            L.append("Z#7")
        }
        L.append("G1 X#3 F\(s.feed)")
        L.append("#1=#1+\(fmt(step, 3)) (每刀角度步距)")
        L.append("#3=-#3 (改变 X 正负方向)")
        L.append("END1")
        L.append("G0 Z\(fmt(lift, 1))")
        L.append("G52 X0 Y0 Z0")
        L.append("M5")
        L.append("M9")
        L.append("G28 G91 Z0")
        L.append("G28 G91 Y0")
        L.append("G90")
        L.append("M30")
        L.append("%")
        return join(L)
    }

    // MARK: - R 角分层
    private static func generateRCorner(_ s: PocketSpec) -> String {
        switch s.rKind {
        case .outerCylinder: return generateOuterCylinderR(s)
        case .hole: return generateHoleR(s)
        case .outerRect: return generateOuterRectR(s)
        case .slot: return generateSlotInnerR(s)
        }
    }

    /// 圆柱外缘顶部 R：沿 1/4 圆分层，每层一整圈
    private static func generateOuterCylinderR(_ s: PocketSpec) -> String {
        let totalR = s.toolCornerR + s.rValue
        let zShift = s.zTop - totalR
        let steps = max(1, Int(ceil(90 / max(s.rAngleStep, 0.001))))
        let step = 90 / Double(steps)
        var L: [String] = []
        L.append("%")
        L.append("O1008 (圆柱外 R 角分层)")
        L.append("( 圆柱Ø\(fmt(s.rCylinderDia, 2))  R\(fmt(s.rValue, 2))  刀Ø\(fmt(s.toolDia, 2))  刀尖R\(fmt(s.toolCornerR, 2)) )")
        L.append("( 角步距\(fmt(step, 2))°  R+刀尖=\(fmt(totalR, 2))  中心X\(fmt(s.cx, 2)) Y\(fmt(s.cy, 2)) )")
        L.append("( Z0=圆柱顶面；程序用 G52 把 Z 移到 R 角圆心 )")
        L.append("( 由 MacroGen 生成 上机前请核对 )")
        L.append("G17 G21 G40 G49 G80 G90 G\(s.coord)")
        L.append("G52 X\(fmt(s.cx, 3)) Y\(fmt(s.cy, 3)) Z\(fmt(zShift, 3))")
        L.append("G43 H\(s.hNo) Z\(fmt(s.safeZ + s.zTop, 1))")
        L.append("M3 S\(s.spindle)")
        L.append("M8")
        L.append("#1=\(fmt(s.rCylinderDia, 2)) (圆柱直径)")
        L.append("#2=\(fmt(s.toolDia, 2)) (刀径)")
        L.append("#3=\(fmt(s.toolCornerR, 2)) (刀尖R)")
        L.append("#4=\(fmt(s.rValue, 2)) (R角)")
        L.append("#5=\(fmt(step, 2)) (角度步距，已按 90° 均分)")
        L.append("#6=#3+#4 (刀尖R+R)")
        L.append("#7=[#2+#1]/2-#6 (顶层刀心半径)")
        L.append("#8=[#2+#1]/2+1 (起始半径)")
        L.append("#9=0 (角度)")
        L.append("#10=90 (结束角度)")
        L.append("G0 X#8 Y0")
        L.append("WHILE[#9LE#10]DO1")
        L.append("#11=COS[#9]*#6 (本层Z偏移)")
        L.append("#12=#7+SIN[#9]*#6 (本层刀心半径)")
        L.append("G0 Z#11")
        L.append("G1 X#12 F\(s.feed)")
        L.append("G3 I-#12 (整圆)")
        L.append("G1 X#8")
        L.append("#9=#9+#5")
        L.append("END1")
        L.append("G0 Z\(fmt(s.safeZ + s.zTop, 1))")
        L.append("G52 X0 Y0 Z0")
        L.append("M5")
        L.append("M9")
        L.append("G28 G91 Z0")
        L.append("G28 G91 Y0")
        L.append("G90")
        L.append("M30")
        L.append("%")
        return join(L)
    }

    /// 孔口 R：刀心在孔内沿 1/4 圆分层，越往下越靠孔壁
    private static func generateHoleR(_ s: PocketSpec) -> String {
        let totalR = s.toolCornerR + s.rValue
        let zShift = s.zTop - totalR
        let steps = max(1, Int(ceil(90 / max(s.rAngleStep, 0.001))))
        let step = 90 / Double(steps)
        var L: [String] = []
        L.append("%")
        L.append("O1009 (孔口 R 角分层)")
        L.append("( 孔Ø\(fmt(s.rHoleDia, 2))  R\(fmt(s.rValue, 2))  刀Ø\(fmt(s.toolDia, 2))  刀尖R\(fmt(s.toolCornerR, 2)) )")
        L.append("( 角步距\(fmt(step, 2))°  R+刀尖=\(fmt(totalR, 2))  中心X\(fmt(s.cx, 2)) Y\(fmt(s.cy, 2)) )")
        L.append("( Z0=孔口顶面；孔要先打穿或至少深过 R 角 )")
        L.append("( 由 MacroGen 生成 上机前请核对 )")
        L.append("G17 G21 G40 G49 G80 G90 G\(s.coord)")
        L.append("G52 X\(fmt(s.cx, 3)) Y\(fmt(s.cy, 3)) Z\(fmt(zShift, 3))")
        L.append("G43 H\(s.hNo) Z\(fmt(s.safeZ + s.zTop, 1))")
        L.append("M3 S\(s.spindle)")
        L.append("M8")
        L.append("#1=\(fmt(s.rHoleDia, 2)) (孔径)")
        L.append("#2=\(fmt(s.toolDia, 2)) (刀径)")
        L.append("#3=\(fmt(s.toolCornerR, 2)) (刀尖R)")
        L.append("#4=\(fmt(s.rValue, 2)) (R角)")
        L.append("#5=\(fmt(step, 2)) (角度步距，已按 90° 均分)")
        L.append("#6=#3+#4 (刀尖R+R)")
        L.append("#7=[#1-#2]/2+#6 (顶层刀心半径)")
        L.append("#8=[#1-#2]/2-1 (起始半径)")
        L.append("#9=0 (角度)")
        L.append("#10=90 (结束角度)")
        L.append("G0 X#8 Y0")
        L.append("WHILE[#9LE#10]DO1")
        L.append("#11=COS[#9]*#6 (本层Z偏移)")
        L.append("#12=#7-SIN[#9]*#6 (本层刀心半径)")
        L.append("G0 Z#11")
        L.append("G1 X#12 F\(s.feed)")
        L.append("G3 I-#12 (整圆)")
        L.append("G1 X#8")
        L.append("#9=#9+#5")
        L.append("END1")
        L.append("G0 Z\(fmt(s.safeZ + s.zTop, 1))")
        L.append("G52 X0 Y0 Z0")
        L.append("M5")
        L.append("M9")
        L.append("G28 G91 Z0")
        L.append("G28 G91 Y0")
        L.append("G90")
        L.append("M30")
        L.append("%")
        return join(L)
    }

    /// 长方形四角外 R：沿 1/4 圆分层，每层走一圈圆角矩形
    private static func generateOuterRectR(_ s: PocketSpec) -> String {
        let totalR = s.toolCornerR + s.rValue
        let zShift = s.zTop - totalR
        let steps = max(1, Int(ceil(90 / max(s.rAngleStep, 0.001))))
        let step = 90 / Double(steps)
        var L: [String] = []
        L.append("%")
        L.append("O1010 (长方形外 R 角分层)")
        L.append("( 长\(fmt(s.length, 2)) 宽\(fmt(s.width, 2))  R\(fmt(s.rValue, 2))  刀Ø\(fmt(s.toolDia, 2)) 刀尖R\(fmt(s.toolCornerR, 2)) )")
        L.append("( 角步距\(fmt(step, 2))°  R+刀尖=\(fmt(totalR, 2))  中心X\(fmt(s.cx, 2)) Y\(fmt(s.cy, 2)) )")
        L.append("( Z0=工件顶面；四角 R 分层，不是侧面轮廓 R )")
        L.append("( 由 MacroGen 生成 上机前请核对 )")
        L.append("G17 G21 G40 G49 G80 G90 G\(s.coord)")
        L.append("G52 X\(fmt(s.cx, 3)) Y\(fmt(s.cy, 3)) Z\(fmt(zShift, 3))")
        L.append("G43 H\(s.hNo) Z\(fmt(s.safeZ + s.zTop, 1))")
        L.append("M3 S\(s.spindle)")
        L.append("M8")
        L.append("#1=\(fmt(s.length, 2)) (长)")
        L.append("#2=\(fmt(s.width, 2)) (宽)")
        L.append("#3=\(fmt(s.toolDia, 2)) (刀径)")
        L.append("#4=\(fmt(s.toolCornerR, 2)) (刀尖R)")
        L.append("#5=\(fmt(s.rValue, 2)) (R角)")
        L.append("#6=#4+#5 (刀尖R+R)")
        L.append("#7=#3-#4*2 (刀具有效平底)")
        L.append("#8=#6-#5+#7/2 (刀具有效半径)")
        L.append("#9=[#1-#5*2+#3-#4*2]/2 (X半长)")
        L.append("#10=[#2-#5*2+#3-#4*2]/2 (Y半宽)")
        L.append("#11=0 (角度)")
        L.append("#12=90 (结束角度)")
        L.append("#19=\(fmt(step, 2)) (角度步距，已按 90° 均分)")
        L.append("G0 X-[#9+#6] Y-[#10-#8]")
        L.append("WHILE[#11LE#12]DO1")
        L.append("#13=COS[#11]*#6 (本层Z偏移)")
        L.append("#14=#9+SIN[#11]*#6 (本层X半长)")
        L.append("#15=#10+SIN[#11]*#6 (本层Y半宽)")
        L.append("#16=#8+SIN[#11]*#6 (本层角R)")
        L.append("#17=#14-#16 (X直边端点)")
        L.append("#18=#15-#16 (Y直边端点)")
        L.append("G0 Z#13")
        L.append("G1 X-#14 F\(s.feed)")
        L.append("G1 Y-#18")
        L.append("G1 Y#18")
        L.append("G02 X-#17 Y#15 R#16")
        L.append("G1 X#17")
        L.append("G02 X#14 Y#18 R#16")
        L.append("G1 Y-#18")
        L.append("G02 X#17 Y-#15 R#16")
        L.append("G1 X-#17")
        L.append("G02 X-#14 Y-#18 R#16")
        L.append("G1 X-[#9+#6]")
        L.append("#11=#11+#19")
        L.append("END1")
        L.append("G0 Z\(fmt(s.safeZ + s.zTop, 1))")
        L.append("G52 X0 Y0 Z0")
        L.append("M5")
        L.append("M9")
        L.append("G28 G91 Z0")
        L.append("G28 G91 Y0")
        L.append("G90")
        L.append("M30")
        L.append("%")
        return join(L)
    }

    /// 槽底内 R：圆角槽轮廓沿 1/4 圆逐层收角
    private static func generateSlotInnerR(_ s: PocketSpec) -> String {
        let centerR = s.rValue - s.toolDia / 2
        let verticalR = centerR - s.toolCornerR
        let halfW = (s.width - 2 * centerR - s.toolDia) / 2
        let halfL = (s.length - 2 * centerR - s.toolDia) / 2
        let steps = max(1, Int(ceil(90 / max(s.rAngleStep, 0.001))))
        let step = 90 / Double(steps)
        var L: [String] = []
        L.append("%")
        L.append("O1011 (槽底内 R 角分层)")
        L.append("( 槽宽\(fmt(s.width, 2)) 槽长\(fmt(s.length, 2)) 槽深\(fmt(s.depth, 2))  R\(fmt(s.rValue, 2)) )")
        L.append("( 刀Ø\(fmt(s.toolDia, 2)) 刀尖R\(fmt(s.toolCornerR, 2))  中心路径R\(fmt(centerR, 2)) 垂直层R\(fmt(verticalR, 2)) )")
        L.append("( 角步距\(fmt(step, 2))°  中心X\(fmt(s.cx, 2)) Y\(fmt(s.cy, 2)) )")
        L.append("( Z0=槽口顶面；G52 先把 Z 移到槽口，再按层下到槽底 )")
        L.append("( 由 MacroGen 生成 上机前请核对 )")
        L.append("G17 G21 G40 G49 G80 G90 G\(s.coord)")
        L.append("G52 X\(fmt(s.cx, 3)) Y\(fmt(s.cy, 3)) Z\(fmt(s.zTop, 3))")
        L.append("G43 H\(s.hNo) Z\(fmt(s.safeZ + s.zTop, 1))")
        L.append("M3 S\(s.spindle)")
        L.append("M8")
        L.append("#14=\(fmt(s.depth, 2)) (槽深)")
        L.append("#15=\(fmt(s.width, 2)) (槽宽)")
        L.append("#16=\(fmt(s.length, 2)) (槽长)")
        L.append("#17=\(fmt(s.toolDia, 2)) (刀径)")
        L.append("#12=\(fmt(s.toolCornerR, 2)) (刀尖R)")
        L.append("#18=\(fmt(s.rValue, 2)) (R角)")
        L.append("#10=#18-#17/2 (刀心圆角R)")
        L.append("#13=#10-#12 (垂直分层R)")
        L.append("#3=[#15-2*#10-#17]/2 (半宽直线段)")
        L.append("#4=[#16-2*#10-#17]/2 (半长直线段)")
        L.append("#1=0 (起始角度)")
        L.append("#2=90 (结束角度)")
        L.append("#19=\(fmt(step, 2)) (角度步距，已按 90° 均分)")
        L.append("G0 X#4 Y0")
        L.append("WHILE[#1LE#2]DO1")
        L.append("#5=[#14-#13]+SIN[#1]*#13 (本层Z深度)")
        L.append("#6=#3+COS[#1]*#13 (本层半宽)")
        L.append("#7=#4+COS[#1]*#13 (本层半长)")
        L.append("#11=COS[#1]*#10 (本层圆角R)")
        L.append("IF[#11LT0.001]THEN#11=0.001")
        L.append("#8=#6-#11 (本层直线半宽)")
        L.append("#9=#7-#11 (本层直线半长)")
        L.append("G0 Z-#5")
        L.append("G1 X#7 F\(s.feed)")
        L.append("G1 Y#8")
        L.append("G3 X#9 Y#6 R#11")
        L.append("G1 X-#9")
        L.append("G3 X-#7 Y#8 R#11")
        L.append("G1 Y-#8")
        L.append("G3 X-#9 Y-#6 R#11")
        L.append("G1 X#9")
        L.append("G3 X#7 Y-#8 R#11")
        L.append("G1 Y0")
        L.append("#1=#1+#19")
        L.append("END1")
        L.append("G0 Z\(fmt(s.safeZ + s.zTop, 1))")
        L.append("G52 X0 Y0 Z0")
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
        case .odCham:
            return """
            【干什么用】
            给圆柱工件的【外缘顶边】倒一圈角（图纸上写 1×45°、2×30° 的那种端面倒角）。
            刀压在倒角锥面上，刀心落在外圆外侧，一层一层往下、一圈一圈绕整圆，把锥面叠出来。
            注意这是"外圆顶边"，不是外形方料的四个尖角倒 C。

            【上机前必须做】
            1. Z0 对在工件上表面（圆柱顶面）
            2. G54 的 X0 Y0 对在圆柱中心，程序自动 G52 平移
            3. 刀具直径、刀补号 H 按实际填

            【可以改的变量】
            #1 = 外圆直径（Ø50 就填 50）
            #2 = 刀具直径
            #3 = 倒角深（从上表面往下倒多深）
            #4 = 每层（0.1 很稳，赶时间 0.2）
            #5 = 锥角（填图纸全角：45°倒角填 90，30°填 60）
            #6 下刀进给、#7 圆周进给

            【尺寸怎么核对】
            倒角宽 = 倒角深 × tan(锥角/2)
            顶口直径 = 外圆直径 - 2 × 倒角宽
            例：Ø50、90°、深 2 → 倒角宽 2，顶口 Ø46，正好 2×45°。

            【注意】
            - 刀径必须小于外圆直径，否则一刀把整个顶面都刮了，程序会拦下来
            - 倒角宽不能超过外圆半径，否则会说"超过外圆半径"
            - 圆柱有缺口 / 键槽 / 台阶时，整圆那一圈会把缺口也切一刀，先确认那里能过刀
            - 逐层是"从浅到深"，最后一层的刀心最大，越往下越靠外
            """
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
        case .taperHelix:
            return """
            【干什么用】
            用螺旋方式铣锥孔：刀心半径从大头到小头连续缩小，Z 逐度下降，到底再走一整圈平底。
            和图例一样适合大锥度、深一点的锥孔，刀路连续，不一层层抬刀。

            【上机前必须做】
            1. Z0 对在工件顶面
            2. G54 的 X0 Y0 对在锥孔中心，程序用 G52 平移
            3. 刀具实际直径、刀补号 H 按实际填
            4. 先用空跑确认锥面方向和底部平底圆

            【可以改的变量】
            #1 = 大头刀心半径 =（大头直径 - 刀径）/2
            #2 = 小头刀心半径 =（小头直径 - 刀径）/2
            #4 = 每圈下刀量
            #5 = 每度下刀量
            #7 = 圈数
            #6 = 总角度
            #8 = 每度半径缩小值
            #3 = 当前角度
            #10 = 加工深度

            【注意】
            - 小头必须大于刀径，否则底部没有刀心半径
            - 大头必须大于小头
            - 每圈下刀量别超过刀尖强度，#4 建议 0.1~0.3
            - 到底的 G03 I#2 是平底整圆；I 为正是逆时针
            - 想反旋向把 G03 改 G02，同时把 I 的符号改掉
            """
        case .arcSurface:
            return """
            【干什么用】
            用 X 向往返排刀铣圆弧面：每刀走一条 X 直线，Y 和 Z 按 SIN/COS 变化，逐刀叠出内圆弧或外圆弧。
            内圆弧适合凹面，外圆弧会用刀尖 R 补成实际计算半径。

            【上机前必须做】
            1. Z0 对在工件顶面
            2. G54 的 X0 Y0 对在工件中心，G52 再把圆弧轴心平移到 arcCenterY
            3. 刀具直径、刀尖 R、刀补号按实际填
            4. 先空跑，确认圆弧轴心在工件哪一侧，以及 X 往返范围不撞夹具

            【可以改的变量】
            #3 = 单侧行程
            #4 = 内圆弧的直边深度 / 外圆弧的刀片 R 角
            #5 = 圆弧半径
            #6 = 外圆弧实际计算半径 = 刀片R + 圆弧半径
            #1 = 当前角度
            #2 = 最终角度

            【注意】
            - 内圆弧：Z = -(直边深度 + SIN[角度]×R)，Y = COS[角度]×R
            - 外圆弧：Z = COS[角度]×(刀片R+R)，Y = -SIN[角度]×(刀片R+R)
            - 每刀走完 X 后自动把 X 方向反过来，形成往返排刀
            - 内圆弧没算刀尖 R，实际弧面会偏小；要精确就换球刀或把 R 补进程序
            - 圆弧轴心 Y 偏移在“圆弧面参数”里改；G52 会把它加到工件中心 Y 上
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
            #13 = 斜面角的正切值；平面写 0，斜面填 TAN[角度]

            【自动算的】
            #7 半长、#8 半宽、#9 行距（=75% 刀径）、#10 方向、#11 当前Z、#12 X位置、#14 当前层 Y 偏移

            【斜面怎么用】
            角度填 0 就是普通平面。要铣 25° 斜面，界面填 25：
            每下降 1mm，Y 偏移 TAN[25]=0.466mm；走到 64.5mm 深，Y 总共偏 30mm。
            正角向 +Y 下斜，负角向 -Y 下斜；先用空跑确认方向，再上料。

            【改法举例】
            毛坯要飞掉 2mm，每刀 0.5：
            #5=-2.  #6=0.5
            行距想更密，把 #9 那行改成 #9=[#3*0.6]

            【注意】
            - #5 必须比 #4 小（更负），否则循环一次都不进，程序空跑
            - 每一趟都先抬到 [#11+2] 再定位，不在材料里横着快走
            - 最后一层如果除不尽，会自动落到 #5，不会多切
            - 斜面角不要超过 60°，角度越大 Y 偏移越快，毛坯两侧要留够余量
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
            #30 = 孔数（单孔写 1）
            #31 = 圆周分布半径（单孔自动按 0）
            #32 = 起始角（度）
            #33 = 角步距（0 = 360/孔数 自动均分）

            【自动算的】
            #6 = 刀心圆半径 =（圆直径-刀径）/2
            #7 = 当前 Z
            #35/#36 = 当前孔的 X/Y 偏置

            【多孔怎么用】
            要在一圈上铣 7 个孔，分布半径 200：
            #30=7  #31=200  #32=0  #33=0
            程序会用 G52 把坐标移到每个孔中心，再走同样的螺旋；孔与孔之间先抬到安全高度。
            分布半径必须大于孔半径，否则孔会重叠；孔数最多 200。

            【改法举例】
            Ø50 的圆用 Ø30 刀：
            #1=50  #2=30 → 刀心半径自动 10
            和手工写的 G1 X-10.78 / G3 I10.78 是同一个意思，这个程序会自动算出来。

            【注意】
            - 刀具直径必须小于圆直径，等于或大于程序会拦下来
            - 每圈下刀量别超过刀尖强度，#5 建议 0.3~0.6
            - 下刀靠 G0 Z[#3+2.] + 后面整段 G3，全程螺旋，没有直插；照抄时别把它改回 G1 Z0
            - 想顺铣把 G3 改成 G2，同时 #6 前面加负号（G2 I-#6）
            - 多孔时每个孔都从安全高度重新下刀，孔深一致；要跳孔/乱序就改 #32 起始角或 #33 步距
            """
        case .oblique:
            return """
            【干什么用】
            铣与 XY 平面不平行的斜向孔/侧孔。程序先用 G68 把孔轴在 XY 平面内旋转一个角度，
            再沿孔轴 X 逐度进给，同时 YZ 走圆，像螺旋一样把孔掏出来；到底后再走一整圈平底。

            【上机前必须做】
            1. Z0 对在工件顶面
            2. G54 的 X0 Y0 对在孔口中心
            3. 刀具实际直径、刀补号 H 按实际填
            4. 先用空跑确认 G68 旋转方向和孔轴朝向，再上料

            【可以改的变量】
            #20 = 刀具直径
            #21 = 孔径
            #22 = 孔轴旋转角（度）
            #5 = 圈数
            #6 = 总角度
            #4 = 每度沿孔轴的 X 进给
            #10 = 加工深度

            【自动算的】
            #2 =（孔径 - 刀径）/2
            #7 = YZ 圆的 Z
            #8 = YZ 圆的 Y
            #9 = 当前 X

            【注意】
            - 刀径必须小于孔径，否则孔进不去
            - 旋转角 0° 时孔轴沿 X；70° 就是图例里的斜向孔
            - 每圈切深建议 0.3~1.0；圈数太多程序会很长
            - G68 只旋转 XY 平面，孔轴不是绕 Z 倾斜的
            - 退刀前先 G69 取消旋转，再抬 Z，避免坐标系还转着
            """
        case .thread:
            return """
            【干什么用】
            在圆周上分布的一组孔里铣螺纹（例如一圈 8 个 M30 螺纹孔）。
            每个孔先用螺纹刀径向进到切削半径，再 G03 螺旋上升：一圈走一整圆、Z 上升一个螺距。

            【上机前必须做】
            1. Z0 对在工件顶面
            2. G54 的 X0 Y0 对在圆周分布中心
            3. 螺纹刀实际直径、刀补号 H 按实际填
            4. 先用空跑确认螺纹旋向和径向进刀方向

            【可以改的变量】
            #20 = 夹角度数（孔间角步距）
            #24 = 孔数
            #4 = 圆周分布半径（单孔=0）
            #10 = 起始角度
            #1 = 螺纹起始 Z
            #2 = 螺纹终止 Z
            #3 = 起始单边切削量
            #21 = 最终单边切削量
            #22 = 径向步距
            #23 = 螺距

            【自动算的】
            螺纹刀心半径 =（螺纹直径 - 刀径）/2
            起始单边切削量 = 刀心半径 - 2×径向步距（至少 0.1）
            最终到刀心半径，按径向步距分 3 刀左右
            螺纹长度 = 螺纹顶 Z - 螺纹起始 Z

            【注意】
            - 刀径必须小于螺纹直径
            - 螺纹长度至少一个螺距
            - 多孔时分布半径要大于螺纹半径，否则孔会重叠
            - 默认参数按 M30×3.5、8 孔、R100、起始 22.5° 示例
            - 如果螺纹是左旋，把 G03 改成 G02，同时 I 的符号跟着改
            """
        case .rCorner:
            return """
            【干什么用】
            给圆柱外缘、孔口、长方形四角或槽底做 R 角分层。不是侧面轮廓倒圆，而是把 R 面沿 90° 分很多层，
            每层走一整圈/一圈圆角槽，刀心半径从大到小（孔口、槽底）或从小到大（外圆），一层层把 R 面叠出来。

            【上机前必须做】
            1. Z0 对在工件顶面
            2. G54 的 X0 Y0 对在圆柱/孔/长方形/槽中心，程序用 G52 平移
            3. 刀具实际直径、刀尖 R、刀补号 H 按实际填
            4. 先用空跑确认 R 面方向和刀心位置，再上料

            【可以改的变量】
            圆形类（圆柱外 R / 孔口 R）：
            #1 = 直径（圆柱填圆柱直径，孔填孔径）
            #2 = 刀具直径
            #3 = 刀尖 R（平底刀填 0；圆鼻刀填刀片 R）
            #4 = R 角半径
            #5 = 角度步距（一般 3°；越小越光，程序越长）

            长方形外 R：
            #1 = 长、#2 = 宽、#3 = 刀径、#4 = 刀尖 R、#5 = R 角
            长方形类的角度步距用 #19，生成时已写入。

            槽底内 R：
            #14 = 槽深、#15 = 槽宽、#16 = 槽长、#17 = 刀径、#18 = R 角
            #12 = 刀尖 R、#10 = 刀心圆角 R、#13 = 垂直分层 R、#19 = 角度步距
            必须满足 R 角 > 刀半径，且 R 角 - 刀半径 - 刀尖 R > 0；否则程序会拦。

            【自动算的（圆形/长方形类）】
            #6 = 刀尖 R + R 角
            #7 = 顶层刀心半径
            #8 = 起始半径
            #9 = 当前角度
            #11 = 当前层 Z 偏移
            #12 = 当前层刀心半径
            槽底内 R 的 #10/#13/#3/#4 已单独算好，直接看程序头注释。

            【注意】
            - 刀尖 R + R 角不能太大，否则顶层刀心半径算成 0 或负数，程序会拦
            - 孔口 R 的孔径必须先打穿或至少深过 R 角，否则刀在孔底顶料
            - 外圆 R 是整圆一刀，圆柱上有缺口/键槽时会切进去，先确认
            - 长方形外 R 每层走一圈圆角矩形，G02 圆弧半径是 #16，不要和侧面轮廓 R 混淆
            - 槽底内 R 每层走一圈圆角槽，最后一层圆角 R 已夹到 0.001，避免 G3 R0 报警
            - 角度步距 3° 是示例值；想更光可改 2°，但程序会变长
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
