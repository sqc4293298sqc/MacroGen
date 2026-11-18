import Foundation
import CoreGraphics

// MARK: - 零件模型（草图 + 特征）

enum HoleMode: String, CaseIterable, Identifiable, Codable {
    case spiral = "螺旋铣"
    case g81 = "钻孔 G81"
    case g83 = "钻孔 G83"
    case tap = "攻丝 G84"
    var id: String { rawValue }
}

/// 2.5D 能表达的孔几何类型。沉头/沉孔按圆柱/倒角近似，不冒充真 3D 特征。
enum PartHoleKind: String, CaseIterable, Identifiable, Codable {
    case through = "通孔"
    case blind = "盲孔"
    case counterbore = "沉头孔"
    case countersink = "沉孔"
    case thread = "螺纹底孔"
    var id: String { rawValue }
}

enum PartFeatKind: String, CaseIterable, Identifiable, Codable {
    case hole = "孔"
    case pocket = "圆型腔（盲腔）"
    case rectPocket = "方型腔（盲腔）"
    var id: String { rawValue }

    // 旧工程里孔的 rawValue 是“孔（贯通）”，升级后仍能读
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "孔（贯通）", "孔": self = .hole
        case "圆型腔（盲腔）": self = .pocket
        case "方型腔（盲腔）": self = .rectPocket
        default: self = .hole
        }
    }
}

struct PartFeat: Identifiable, Equatable, Codable {
    var id = UUID()
    var name: String = ""
    var kind: PartFeatKind = .hole
    var suppressed: Bool = false      // 抑制：仍保留特征，但不参与刀路/检查/包围盒
    var x: Double = 0
    var y: Double = 0
    var dia: Double = 10
    var w: Double = 30
    var h: Double = 20
    var depth: Double = 5      // 型腔深度（孔不用）
    /// 手动放置 Z：空 = 自动取所在台阶顶面/Z0；有值 = 放在任意已有面或任意 Z 面
    var placeZ: Double? = nil
    // 孔类型（可选，旧工程缺省按通孔处理）
    var holeKind: PartHoleKind? = nil
    var holeDepth: Double? = nil
    var cbDia: Double? = nil
    var cbDepth: Double? = nil
    var csDia: Double? = nil
    var csAngle: Double? = nil

    init(kind: PartFeatKind = .hole, x: Double = 0, y: Double = 0,
         dia: Double = 10, w: Double = 30, h: Double = 20, depth: Double = 5,
         name: String = "") {
        self.name = name
        self.kind = kind
        self.x = x
        self.y = y
        self.dia = dia
        self.w = w
        self.h = h
        self.depth = depth
    }

    var resolvedHoleKind: PartHoleKind { holeKind ?? .through }
    var resolvedHoleDepth: Double { holeDepth ?? max(depth, 1) }
    var resolvedCbDia: Double { cbDia ?? max(dia * 1.8, dia + 1) }
    var resolvedCbDepth: Double { cbDepth ?? 2 }
    var resolvedCsDia: Double { csDia ?? max(dia * 1.6, dia + 1) }
    var resolvedCsAngle: Double { csAngle ?? 90 }

    var holeSummary: String {
        switch resolvedHoleKind {
        case .through: return "通孔"
        case .blind: return "盲孔 深\(ncf(resolvedHoleDepth))"
        case .counterbore: return "沉头 Ø\(ncf(resolvedCbDia)) 深\(ncf(resolvedCbDepth)) / 通孔 Ø\(ncf(dia))"
        case .countersink: return "沉孔 Ø\(ncf(resolvedCsDia)) \(ncf(resolvedCsAngle))° / 通孔 Ø\(ncf(dia))"
        case .thread: return "螺纹底孔 Ø\(ncf(dia)) 深\(ncf(resolvedHoleDepth))"
        }
    }
}

struct SketchLoop: Identifiable, Equatable, Codable {
    var id = UUID()
    var name: String = "内轮廓"
    var template: ContourTemplate = .circle
    var rectL: Double = 40
    var rectW: Double = 20
    var rectR: Double = 0
    var circleD: Double = 20
    var slotL: Double = 40
    var slotW: Double = 12
    var nodes: [ContourNode] = []
    var cx: Double = 0
    var cy: Double = 0
    var through: Bool = true
    var depth: Double = 5
}

// MARK: - 多台阶（同一零件上的独立 Z 层）

/// 一层台阶的外形。保留模板字段，手画轮廓直接用 nodes。
struct PartShape: Equatable, Codable {
    var template: ContourTemplate = .rect
    var rectL: Double = 120
    var rectW: Double = 80
    var rectR: Double = 0
    var circleD: Double = 100
    var slotL: Double = 120
    var slotW: Double = 30
    var nodes: [ContourNode] = []
    var cx: Double = 0          // 该层轮廓中心 X（UG 里放凸台时的定位）
    var cy: Double = 0          // 该层轮廓中心 Y

    init() {}

    init(_ p: PartSpec) {
        template = p.template
        rectL = p.rectL
        rectW = p.rectW
        rectR = p.rectR
        circleD = p.circleD
        slotL = p.slotL
        slotW = p.slotW
        nodes = p.nodes
    }

    // 旧工程没有 cx/cy 字段，解码时补 0，避免升级后工程读不出来
    private enum CodingKeys: String, CodingKey {
        case template, rectL, rectW, rectR, circleD, slotL, slotW, nodes, cx, cy
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        template = try c.decodeIfPresent(ContourTemplate.self, forKey: .template) ?? .rect
        rectL = try c.decodeIfPresent(Double.self, forKey: .rectL) ?? 120
        rectW = try c.decodeIfPresent(Double.self, forKey: .rectW) ?? 80
        rectR = try c.decodeIfPresent(Double.self, forKey: .rectR) ?? 0
        circleD = try c.decodeIfPresent(Double.self, forKey: .circleD) ?? 100
        slotL = try c.decodeIfPresent(Double.self, forKey: .slotL) ?? 120
        slotW = try c.decodeIfPresent(Double.self, forKey: .slotW) ?? 30
        nodes = try c.decodeIfPresent([ContourNode].self, forKey: .nodes) ?? []
        cx = try c.decodeIfPresent(Double.self, forKey: .cx) ?? 0
        cy = try c.decodeIfPresent(Double.self, forKey: .cy) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(template, forKey: .template)
        try c.encode(rectL, forKey: .rectL)
        try c.encode(rectW, forKey: .rectW)
        try c.encode(rectR, forKey: .rectR)
        try c.encode(circleD, forKey: .circleD)
        try c.encode(slotL, forKey: .slotL)
        try c.encode(slotW, forKey: .slotW)
        try c.encode(nodes, forKey: .nodes)
        try c.encode(cx, forKey: .cx)
        try c.encode(cy, forKey: .cy)
    }

    var summary: String {
        switch template {
        case .rect: return "\(ncf(rectL))×\(ncf(rectW))"
        case .circle: return "Ø\(ncf(circleD))"
        case .slot: return "\(ncf(slotL))×\(ncf(slotW))"
        case .free: return "\(nodes.count) 段"
        }
    }
}

enum PartStepMode: String, CaseIterable, Identifiable, Codable {
    case add = "增料"
    case cut = "除料"
    var id: String { rawValue }
}

struct PartStep: Identifiable, Equatable, Codable {
    var id = UUID()
    var name: String = "台阶"
    var shape: PartShape = PartShape()
    var z0: Double = 0          // 台阶底面 Z（基础顶面 = 0）
    var height: Double = 5      // 台阶厚度
    var mode: PartStepMode = .add
    var colorIndex: Int = 1
    var z1: Double { z0 + height }
    /// 建模/标注用的上下表面：增料向上加，除料从 z0 向下挖
    var drawTop: Double { mode == .add ? z1 : z0 }
    var drawBottom: Double { mode == .add ? z0 : z0 - height }

    init() {}

    init(from p: PartSpec) {
        name = "台阶"
        shape = PartShape(p)
        z0 = 0
        height = 5
    }
}

enum SketchConstraintKind: String, CaseIterable, Identifiable, Hashable, Codable {
    case horizontal = "水平（全部点）"
    case vertical = "竖直（全部点）"
    case coincident = "重合（首尾）"
    case parallel = "平行"
    case perpendicular = "垂直"
    case equal = "等长（末两段）"
    case tangent = "相切（末段圆弧）"
    case midpoint = "中点"
    case concentric = "同心（内轮廓）"
    var id: String { rawValue }
}

struct SketchConstraint: Identifiable, Equatable, Codable {
    var id = UUID()
    var kind: SketchConstraintKind
    var a: Int = 0
    var b: Int = 0
    var c: Int = 0
    var d: Int = 0
    var label: String { kind.rawValue }
    var symbol: String {
        switch kind {
        case .horizontal: return "H"
        case .vertical: return "V"
        case .coincident: return "C"
        case .parallel: return "∥"
        case .perpendicular: return "⊥"
        case .equal: return "="
        case .tangent: return "T"
        case .midpoint: return "M"
        case .concentric: return "◎"
        }
    }
}

struct PartSpec: Equatable, Codable {
    // 工程
    var projectName: String = "未命名工程"
    var stockMarginXY: Double = 5       // 毛坯 XY 单边余量
    var stockExtraTop: Double = 0       // 毛坯顶面余量（Z+）
    var stockExtraBottom: Double = 0    // 毛坯底面余量（Z-）
    var showStock: Bool = true          // 建模页显示毛坯
    var postName: String = "FANUC"      // 后处理标识（当前只输出 FANUC 风格）

    // 外形草图
    var template: ContourTemplate = .rect
    var rectL: Double = 120
    var rectW: Double = 80
    var rectR: Double = 0
    var circleD: Double = 100
    var slotL: Double = 120
    var slotW: Double = 30
    var nodes: [ContourNode] = []

    var height: Double = 10        // 零件厚度（外形铣到底）
    var topStock: Double = 1       // 顶面余量（平面铣深度）

    var feats: [PartFeat] = []
    /// 同一张草图上的内轮廓：内圆/内方/异形，建模时自动当挖孔或型腔
    var innerLoops: [SketchLoop] = []

    /// 基础拉伸之上的独立台阶；空数组就是旧的单实体 2.5D
    var steps: [PartStep] = []
    /// 草图约束（关联节点索引；结构变化时清空）
    var constraints: [SketchConstraint] = []
    /// 工序禁用：id 由 PartProg.opInfo 统一生成
    var disabledOps: Set<String> = []
    /// 手工工序顺序（空 = 按自动顺序）
    var opOrder: [String] = []

    // 切削
    var spindle: Int = 2000
    var feed: Int = 400
    var stepDown: Double = 3
    var stepOver: Double = 6
    var safeZ: Double = 100

    // 刀具（工序列表里的 T 和 D）
    var faceTool: Int = 1
    var faceDia: Double = 6
    var contourTool: Int = 2
    var contourDia: Double = 8
    var holeTool: Int = 3
    var holeDia: Double = 6
    var pocketTool: Int = 4
    var pocketDia: Double = 6

    var doFace = true
    var doContour = true
    /// 外轮廓反向：顺铣/逆铣切换（2.5D 轮廓方向，不是刀具姿态）
    var reverseOuter: Bool = false
    /// 外轮廓起点节点序号（自由轮廓有效，0 = 原来的起点）
    var contourStartNode: Int = 0
    var doHole = true
    var doPocket = true
    /// 2.5D 轮廓倒角近似：沿外形顶边走一刀，不生成真实斜面
    var doChamfer = false
    var chamferSize: Double = 1
    /// 残料清角 / 二次开粗：大刀粗加工后，用小刀沿同一轮廓补一圈。
    /// 2.5D 近似，不生成真实残料实体。
    var doRest = false
    var restTool: Int = 6
    var restDia: Double = 3

    // 孔加工方式
    var holeMode: HoleMode = .spiral
    var peck: Double = 2          // G83 每次啄钻
    var tapPitch: Double = 1.5    // 攻丝螺距
    var tapRpm: Int = 300
    var tapTool: Int = 5
    var tapDia: Double = 10

    var coord: Int = 54           // G54~G59
    var originX: Double = 0       // G54/G55… 的 X0Y0 落在草图坐标的哪个点
    var originY: Double = 0
    var programNo: Int = 1010     // 程序号 O
    var optionalStop: Bool = false // 程序尾 M01
}

// MARK: - 工序清单

enum PartOpStatus: String {
    case ready = "可生成"
    case disabled = "已禁用"
    case modelOnly = "仅建模"
    case stale = "需重算"
}

struct PartOpInfo: Identifiable {
    var id: String
    var title: String
    var kind: String
    var geometry: String
    var tool: Int
    var dia: Double
    var spindle: Int
    var feed: Int
    var zRange: String
    var status: PartOpStatus

    var enabled: Bool { status == .ready || status == .stale }

    var summary: String {
        "\(title) · \(kind)　T\(tool) D\(ncf(dia))　S\(spindle) F\(feed)"
    }
}

// MARK: - 多工序程序

enum PartProg {

    /// 外形几何（供画布和程序共用）
    static func outline(_ p: PartSpec) -> DrawSpec {
        asDraw(p, outward: true, dia: p.contourDia, depth: p.height, hNo: p.contourTool)
    }

    static func asDraw(_ p: PartSpec, outward: Bool, template: ContourTemplate? = nil,
                       circleD: Double? = nil, dia: Double, depth: Double, hNo: Int) -> DrawSpec {
        var shape = PartShape(p)
        if let template { shape.template = template }
        if let circleD { shape.circleD = circleD }
        return asDraw(shape, p, outward: outward, dia: dia, depth: depth, hNo: hNo)
    }

    /// 任意一层外形（基础草图或台阶）转成可画/可出程序的轮廓
    static func asDraw(_ shape: PartShape, _ p: PartSpec, outward: Bool,
                       dia: Double, depth: Double, hNo: Int, zTop: Double = 0) -> DrawSpec {
        var d = DrawSpec()
        d.template = shape.template
        d.rectL = shape.rectL
        d.rectW = shape.rectW
        d.rectR = shape.rectR
        d.circleD = shape.circleD
        d.slotL = shape.slotL
        d.slotW = shape.slotW
        d.nodes = shape.nodes
        if outward, d.template == .free, d.nodes.count > 1, p.contourStartNode > 0 {
            let i = min(max(p.contourStartNode, 0), d.nodes.count - 1)
            d.nodes = Array(d.nodes[i...]) + Array(d.nodes[..<i])
        }
        if outward, p.reverseOuter {
            d.nodes.reverse()
        }
        d.toolDia = dia
        d.depth = depth
        d.stepDown = p.stepDown
        d.feed = Double(p.feed)
        d.rpm = Double(p.spindle)
        d.safeZ = p.safeZ
        d.hNo = hNo
        d.coord = p.coord
        d.outward = outward
        d.zTop = zTop
        return d
    }

    /// 内轮廓转成可以画/出程序的轮廓
    static func drawForLoop(_ l: SketchLoop, _ p: PartSpec, depth: Double,
                            dia: Double, hNo: Int, zTop: Double = 0) -> DrawSpec {
        var d = DrawSpec()
        d.template = l.template
        d.rectL = l.rectL
        d.rectW = l.rectW
        d.rectR = l.rectR
        d.circleD = l.circleD
        d.slotL = l.slotL
        d.slotW = l.slotW
        d.nodes = l.nodes
        d.toolDia = dia
        d.depth = depth
        d.stepDown = p.stepDown
        d.feed = Double(p.feed)
        d.rpm = Double(p.spindle)
        d.safeZ = p.safeZ
        d.hNo = hNo
        d.coord = p.coord
        d.zTop = zTop
        d.outward = false
        return d
    }

    static func loopPoints(_ l: SketchLoop) -> [CGPoint] {
        ContourGeo.flatten(ContourGeo.segments(ContourGeo.buildNodes(
            drawForLoop(l, PartSpec(), depth: l.depth, dia: 6, hNo: 1)))
        )
    }

    static func pts(_ p: PartSpec) -> [CGPoint] {
        ContourGeo.flatten(ContourGeo.segments(ContourGeo.buildNodes(outline(p)))
        )
    }

    static func pts(_ step: PartStep, _ p: PartSpec) -> [CGPoint] {
        let d = asDraw(step.shape, p, outward: true, dia: p.contourDia,
                       depth: max(step.height, 0.1), hNo: p.contourTool, zTop: step.z1)
        return ContourGeo.flatten(ContourGeo.segments(ContourGeo.buildNodes(d)))
            .map { CGPoint(x: Double($0.x) + step.shape.cx, y: Double($0.y) + step.shape.cy) }
    }

    /// 台阶最高点（基础顶面是 0）
    static func maxZ(_ p: PartSpec) -> Double {
        max(0, p.steps.map(\.drawTop).max() ?? 0)
    }

    /// 零件最低点（基础底面是 -height）
    static func minZ(_ p: PartSpec) -> Double {
        min(-p.height, p.steps.map(\.drawBottom).min() ?? -p.height)
    }

    /// 孔底 Z：通孔/沉头/沉孔贯通到底；盲孔/螺纹底孔按给定深度。
    static func holeBottomZ(_ p: PartSpec, _ f: PartFeat, host: Double) -> Double {
        switch f.resolvedHoleKind {
        case .through, .counterbore, .countersink:
            return minZ(p)
        case .blind, .thread:
            return max(host - f.resolvedHoleDepth, minZ(p))
        }
    }

    /// 沉头孔大径圆柱的深度
    static func counterboreDepth(_ f: PartFeat) -> Double {
        max(f.resolvedCbDepth, 0.1)
    }

    /// 90°/120° 沉孔按锥面换算出的深度；2.5D 只做倒角近似
    static func countersinkDepth(_ f: PartFeat) -> Double {
        let halfAngle = max(15, min(f.resolvedCsAngle, 170)) / 2 * Double.pi / 180
        return max((f.resolvedCsDia - f.dia) / 2 / tan(halfAngle), 0.1)
    }

    /// 单孔实际使用的加工方式；螺纹底孔强制攻丝
    static func holeMode(_ p: PartSpec, _ f: PartFeat) -> HoleMode {
        f.resolvedHoleKind == .thread ? .tap : p.holeMode
    }

    /// 点是否在闭合轮廓内（射线法，支持凹多边形）
    static func pointIn(_ pts: [CGPoint], _ x: Double, _ y: Double) -> Bool {
        guard pts.count > 2 else { return false }
        var inside = false
        var j = pts.count - 1
        for i in 0..<pts.count {
            let xi = Double(pts[i].x), yi = Double(pts[i].y)
            let xj = Double(pts[j].x), yj = Double(pts[j].y)
            if (yi > y) != (yj > y) {
                let xCross = (xj - xi) * (y - yi) / (yj - yi) + xi
                if x < xCross { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    /// 找 XY 所在最高的增料台阶；不在台阶上返回 nil（即基础顶面 Z0）
    static func stepAt(_ p: PartSpec, _ x: Double, _ y: Double) -> PartStep? {
        p.steps.filter { $0.mode == .add && pointIn(pts($0, p), x, y) }
            .max(by: { $0.z1 < $1.z1 })
    }

    /// 孔/腔/内轮廓的起始顶面：落在台阶上取该台阶顶面，否则为基础顶面 0
    static func hostZ(_ p: PartSpec, _ x: Double, _ y: Double) -> Double {
        stepAt(p, x, y)?.z1 ?? 0
    }

    /// 特征起始 Z：手动放置优先，否则自动取台阶顶面/Z0。
    static func hostZ(_ p: PartSpec, _ f: PartFeat) -> Double {
        f.placeZ ?? hostZ(p, f)
    }

    /// 按工件原点平移整件：让设定的 X0Y0 点变成程序里的 0,0
    static func shifted(_ p: PartSpec, dx: Double, dy: Double) -> PartSpec {
        var q = p
        // 模板矩形/圆没有节点，直接平移 nodes 不会动。先展平成自由轮廓再整体平移。
        let base = pts(p)
        q.template = .free
        q.nodes = base.map { ContourNode(x: Double($0.x) + dx, y: Double($0.y) + dy) }
        q.feats = p.feats.map { f in
            var m = f; m.x += dx; m.y += dy; return m
        }
        q.innerLoops = p.innerLoops.map { l in
            var m = l
            m.cx += dx; m.cy += dy
            m.nodes = l.nodes.map { n in var k = n; k.x += dx; k.y += dy; return k }
            return m
        }
        q.steps = p.steps.map { s in
            var m = s
            let sp = pts(s, p)
            m.shape.template = .free
            m.shape.nodes = sp.map { ContourNode(x: Double($0.x) + dx, y: Double($0.y) + dy) }
            m.shape.cx = 0; m.shape.cy = 0
            return m
        }
        return q
    }

    static func bbox(_ p: PartSpec) -> CGRect {
        var ps = pts(p)
        for s in p.steps { ps.append(contentsOf: pts(s, p)) }
        guard let f = ps.first else { return CGRect(x: -50, y: -30, width: 100, height: 60) }
        var mnx = f.x, mxx = f.x, mny = f.y, mxy = f.y
        for q in ps {
            mnx = min(mnx, q.x); mxx = max(mxx, q.x)
            mny = min(mny, q.y); mxy = max(mxy, q.y)
        }
        return CGRect(x: mnx, y: mny, width: mxx - mnx, height: mxy - mny)
    }

    /// 结构化工序清单：界面显示 T/D/S/F、几何和状态
    static func ops(_ p: PartSpec) -> [PartOpInfo] {
        var out: [PartOpInfo] = []
        let b = bbox(p)
        let maxZv = maxZ(p), minZv = minZ(p)

        func status(_ id: String, fallback: PartOpStatus = .ready) -> PartOpStatus {
            p.disabledOps.contains(id) ? .disabled : fallback
        }

        if p.doFace && p.topStock > 0 && p.steps.isEmpty {
            out.append(PartOpInfo(
                id: "face", title: "顶面", kind: "平面铣",
                geometry: "毛坯 \(ncf(Double(b.width)))×\(ncf(Double(b.height)))",
                tool: p.faceTool, dia: p.faceDia, spindle: p.spindle, feed: p.feed,
                zRange: "Z\(ncf(maxZv)) → Z\(ncf(maxZv - p.topStock))",
                status: status("face")))
        }
        if p.doContour {
            out.append(PartOpInfo(
                id: "contour", title: "外形轮廓", kind: "轮廓铣",
                geometry: "外形 \(PartShape(p).summary)",
                tool: p.contourTool, dia: p.contourDia, spindle: p.spindle, feed: p.feed,
                zRange: "Z0 → Z\(ncf(-p.height))",
                status: status("contour")))
        }
        if p.doChamfer {
            out.append(PartOpInfo(
                id: "chamfer", title: "轮廓倒角", kind: "倒角（2.5D 近似）",
                geometry: "外形顶边 C\(ncf(p.chamferSize))（只对基础外形）",
                tool: p.contourTool, dia: p.contourDia, spindle: p.spindle, feed: p.feed,
                zRange: "Z0 → Z\(ncf(-p.chamferSize))",
                status: status("chamfer")))
        }
        if p.doRest {
            out.append(PartOpInfo(
                id: "rest", title: "残料清角", kind: "二次开粗（2.5D 近似）",
                geometry: "基础外形 + 台阶 + 孔/腔/内轮廓，小刀沿边界补一圈",
                tool: p.restTool, dia: p.restDia, spindle: p.spindle, feed: p.feed,
                zRange: "Z\(ncf(maxZv)) → Z\(ncf(minZv))",
                status: status("rest")))
        }
        for s in p.steps {
            let zr = "Z\(ncf(s.drawTop)) → Z\(ncf(s.drawBottom))"
            if s.mode == .add {
                let roughID = "steprough-\(s.id.uuidString)"
                out.append(PartOpInfo(
                    id: roughID, title: "\(s.name) 周边粗加工", kind: "轮廓粗加工",
                    geometry: "增料 \(s.shape.summary)",
                    tool: p.contourTool, dia: p.contourDia, spindle: p.spindle, feed: p.feed,
                    zRange: zr, status: status(roughID)))
                let id = "step-\(s.id.uuidString)"
                out.append(PartOpInfo(
                    id: id, title: s.name, kind: "台阶轮廓铣",
                    geometry: "增料 \(s.shape.summary)",
                    tool: p.contourTool, dia: p.contourDia, spindle: p.spindle, feed: p.feed,
                    zRange: zr, status: status(id)))
            } else {
                let id = "stepcut-\(s.id.uuidString)"
                out.append(PartOpInfo(
                    id: id, title: "\(s.name) 除料", kind: "除料清腔",
                    geometry: "除料 \(s.shape.summary)",
                    tool: p.pocketTool, dia: p.pocketDia, spindle: p.spindle, feed: p.feed,
                    zRange: zr, status: status(id)))
            }
        }
        for f in p.feats where !f.suppressed {
            let id = "feat-\(f.id.uuidString)"
            let host = hostZ(p, f)
            if f.kind == .hole {
                guard p.doHole else { continue }
                let hk = f.resolvedHoleKind
                let bottom = holeBottomZ(p, f, host: host)
                let mode = holeMode(p, f)
                // 沉头：先做顶部大径圆柱，再做下面的小孔
                if hk == .counterbore {
                    let cbID = "\(id)-cb"
                    out.append(PartOpInfo(
                        id: cbID, title: f.name.isEmpty ? "沉头" : "\(f.name) 沉头",
                        kind: "沉头（圆柱近似）",
                        geometry: "Ø\(ncf(f.resolvedCbDia)) 深\(ncf(counterboreDepth(f))) @X\(ncf(f.x)) Y\(ncf(f.y))",
                        tool: p.pocketTool, dia: p.pocketDia, spindle: p.spindle, feed: p.feed,
                        zRange: "Z\(ncf(host)) → Z\(ncf(host - counterboreDepth(f)))",
                        status: status(cbID)))
                }
                // 沉孔：顶部锥面倒角近似
                if hk == .countersink {
                    let csID = "\(id)-cs"
                    out.append(PartOpInfo(
                        id: csID, title: f.name.isEmpty ? "沉孔" : "\(f.name) 沉孔",
                        kind: "沉孔（锥面近似）",
                        geometry: "Ø\(ncf(f.resolvedCsDia)) \(ncf(f.resolvedCsAngle))° 深\(ncf(countersinkDepth(f)))",
                        tool: p.pocketTool, dia: p.pocketDia, spindle: p.spindle, feed: p.feed,
                        zRange: "Z\(ncf(host)) → Z\(ncf(host - countersinkDepth(f)))",
                        status: status(csID)))
                }
                let title: String
                switch hk {
                case .through: title = f.name.isEmpty ? "通孔" : f.name
                case .blind: title = f.name.isEmpty ? "盲孔" : f.name
                case .counterbore: title = f.name.isEmpty ? "沉头小孔" : "\(f.name) 小孔"
                case .countersink: title = f.name.isEmpty ? "沉孔小孔" : "\(f.name) 小孔"
                case .thread: title = f.name.isEmpty ? "螺纹底孔" : f.name
                }
                switch mode {
                case .spiral:
                    out.append(PartOpInfo(
                        id: id, title: title, kind: "螺旋铣",
                        geometry: "Ø\(ncf(f.dia)) \(f.holeSummary) @X\(ncf(f.x)) Y\(ncf(f.y))",
                        tool: p.holeTool, dia: p.holeDia, spindle: p.spindle, feed: p.feed,
                        zRange: "Z\(ncf(host)) → Z\(ncf(bottom))",
                        status: status(id)))
                case .g81, .g83:
                    out.append(PartOpInfo(
                        id: id, title: title,
                        kind: mode == .g81 ? "钻孔 G81" : "钻孔 G83",
                        geometry: "Ø\(ncf(f.dia)) \(f.holeSummary) @X\(ncf(f.x)) Y\(ncf(f.y))",
                        tool: p.holeTool, dia: f.dia, spindle: p.spindle, feed: p.feed,
                        zRange: "Z\(ncf(host)) → Z\(ncf(bottom))",
                        status: status(id)))
                case .tap:
                    out.append(PartOpInfo(
                        id: id, title: title, kind: "攻丝 G84",
                        geometry: "Ø\(ncf(f.dia)) \(f.holeSummary) P\(ncf(p.tapPitch)) @X\(ncf(f.x)) Y\(ncf(f.y))",
                        tool: p.tapTool, dia: p.tapDia, spindle: p.tapRpm, feed: p.feed,
                        zRange: "Z\(ncf(host)) → Z\(ncf(bottom))",
                        status: status(id)))
                }
            } else if p.doPocket && f.kind == .rectPocket {
                out.append(PartOpInfo(
                    id: id, title: f.name.isEmpty ? "方腔" : f.name, kind: "型腔铣",
                    geometry: "\(ncf(f.w))×\(ncf(f.h)) 深\(ncf(f.depth)) @X\(ncf(f.x)) Y\(ncf(f.y))",
                    tool: p.pocketTool, dia: p.pocketDia, spindle: p.spindle, feed: p.feed,
                    zRange: "Z\(ncf(host)) → Z\(ncf(host - f.depth))",
                    status: status(id)))
            } else if p.doPocket {
                out.append(PartOpInfo(
                    id: id, title: f.name.isEmpty ? "圆腔" : f.name, kind: "型腔铣",
                    geometry: "Ø\(ncf(f.dia)) 深\(ncf(f.depth)) @X\(ncf(f.x)) Y\(ncf(f.y))",
                    tool: p.pocketTool, dia: p.pocketDia, spindle: p.spindle, feed: p.feed,
                    zRange: "Z\(ncf(host)) → Z\(ncf(host - f.depth))",
                    status: status(id)))
            }
        }
        for l in p.innerLoops {
            let id = "loop-\(l.id.uuidString)"
            let host = hostZ(p, l.cx, l.cy)
            if l.template == .circle && l.through {
                guard p.doHole else { continue }
                let depth = host - minZv + 1
                if p.holeMode == .spiral {
                    out.append(PartOpInfo(
                        id: id, title: l.name, kind: "螺旋铣",
                        geometry: "Ø\(ncf(l.circleD)) @X\(ncf(l.cx)) Y\(ncf(l.cy))",
                        tool: p.holeTool, dia: p.holeDia, spindle: p.spindle, feed: p.feed,
                        zRange: "Z\(ncf(host)) → Z\(ncf(minZv - 1))",
                        status: status(id)))
                } else {
                    out.append(PartOpInfo(
                        id: id, title: l.name, kind: p.holeMode.rawValue,
                        geometry: "Ø\(ncf(l.circleD)) @X\(ncf(l.cx)) Y\(ncf(l.cy)) 深\(ncf(depth))",
                        tool: p.holeTool, dia: l.circleD, spindle: p.spindle, feed: p.feed,
                        zRange: "Z\(ncf(host)) → Z\(ncf(minZv - 1))",
                        status: status(id)))
                }
            } else {
                guard p.doPocket else { continue }
                let depth = l.through ? host - minZv : min(l.depth, host - minZv)
                out.append(PartOpInfo(
                    id: id, title: l.name, kind: "型腔铣",
                    geometry: "\(l.template.rawValue) \(ncf(depth)) 深 @X\(ncf(l.cx)) Y\(ncf(l.cy))",
                    tool: p.pocketTool, dia: p.pocketDia, spindle: p.spindle, feed: p.feed,
                    zRange: "Z\(ncf(host)) → Z\(ncf(host - depth))",
                    status: status(id)))
            }
        }
        return ordered(out, p)
    }

    /// 兼容旧界面的字符串工序清单
    static func opList(_ p: PartSpec) -> [String] {
        ops(p).filter { $0.status != .disabled && $0.status != .modelOnly }.map(\.summary)
    }

    // MARK: - 2D 刀路检查

    /// 闭合折线按法向外/内偏置；只用于 2D 检查示意，G 代码仍走 G41/G42
    static func offsetClosed(_ src: [CGPoint], by d: Double) -> [CGPoint] {
        guard src.count > 2, abs(d) > 1e-9 else { return src }
        let area = ContourGeo.signedArea(src)
        let outwardSign: CGFloat = area >= 0 ? 1 : -1
        var out: [CGPoint] = []
        out.reserveCapacity(src.count)
        for i in src.indices {
            let prev = src[(i + src.count - 1) % src.count]
            let cur = src[i]
            let next = src[(i + 1) % src.count]
            func normal(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
                let dx = b.x - a.x, dy = b.y - a.y
                let l = max(0.0001, hypot(dx, dy))
                return CGPoint(x: outwardSign * dy / l, y: -outwardSign * dx / l)
            }
            let n1 = normal(prev, cur)
            let n2 = normal(cur, next)
            var nx = n1.x + n2.x, ny = n1.y + n2.y
            let l = max(0.0001, hypot(nx, ny))
            nx /= l; ny /= l
            out.append(CGPoint(x: cur.x + nx * CGFloat(d), y: cur.y + ny * CGFloat(d)))
        }
        return out
    }

    static func pathLen(_ pts: [CGPoint]) -> Double {
        guard pts.count > 1 else { return 0 }
        var total = 0.0
        for i in 1..<pts.count {
            total += hypot(Double(pts[i].x - pts[i - 1].x), Double(pts[i].y - pts[i - 1].y))
        }
        return total
    }

    static func shapePoints(_ shape: PartShape, _ p: PartSpec, depth: Double = 1) -> [CGPoint] {
        let d = asDraw(shape, p, outward: true, dia: max(p.contourDia, 0.1),
                       depth: max(depth, 0.1), hNo: p.contourTool)
        // 台阶轮廓的 cx/cy 必须在这里统一补上；
        // 精加工、图纸、DXF、面积计算都走这里，漏一次就会回到原点。
        return ContourGeo.flatten(ContourGeo.segments(ContourGeo.buildNodes(d)))
            .map { CGPoint(x: Double($0.x) + shape.cx, y: Double($0.y) + shape.cy) }
    }

    static func shiftedSegs(_ segs: [TPSeg], dx: Double, dy: Double) -> [TPSeg] {
        segs.map { s in
            var m = s
            m.pts = s.pts.map { CGPoint(x: $0.x + CGFloat(dx), y: $0.y + CGFloat(dy)) }
            return m
        }
    }

    /// 加工页 2D 俯视检查用：按当前启用的工序生成示意刀路（切削/快移分开）
    static func toolpaths2D(_ p: PartSpec) -> [TPSeg] {
        var out: [TPSeg] = []
        func enabled(_ id: String) -> Bool { !p.disabledOps.contains(id) }
        func line(_ pts: [CGPoint], z: Double, cut: Bool) {
            guard pts.count > 1 else { return }
            out.append(TPSeg(cut: cut, z: z, pts: pts, len: pathLen(pts)))
        }
        func addSegs(_ segs: [TPSeg], dx: Double = 0, dy: Double = 0) {
            out.append(contentsOf: shiftedSegs(segs, dx: dx, dy: dy))
        }

        if p.doFace && p.topStock > 0 && p.steps.isEmpty && enabled("face") {
            let b = bbox(p)
            var s = PocketSpec()
            s.mode = .face
            s.length = Double(b.width); s.width = Double(b.height)
            s.depth = p.topStock
            s.stepDown = min(p.topStock + max(0, p.stockExtraTop), max(0.3, p.stepDown))
            s.stepOver = p.stepOver
            s.toolDia = p.faceDia
            s.spindle = p.spindle; s.feed = p.feed; s.safeZ = p.safeZ
            s.hNo = p.faceTool
            s.coord = p.coord
            addSegs(ToolpathEngine.build(s), dx: Double(b.midX), dy: Double(b.midY))
        }

        for s in p.steps {
            let z = s.mode == .add ? s.z1 : s.z0
            let roughID = s.mode == .add ? "steprough-\(s.id.uuidString)" : "stepcut-\(s.id.uuidString)"
            if enabled(roughID) {
                for q in stepRoughLoops(p, s) { line(q, z: z, cut: true) }
            }
            if s.mode == .add && enabled("step-\(s.id.uuidString)") {
                let pts = shapePoints(s.shape, p, depth: max(s.height, 0.1))
                line(offsetClosed(pts, by: p.contourDia / 2), z: s.z1, cut: true)
            }
        }

        if p.doContour && enabled("contour") {
            let pts = offsetClosed(pts(p), by: p.contourDia / 2)
            line(pts, z: 0, cut: true)
        }
        if p.doRest && enabled("rest") {
            line(offsetClosed(pts(p), by: p.restDia / 2), z: 0, cut: true)
            for s in p.steps where s.mode == .add {
                let pts = shapePoints(s.shape, p, depth: max(s.height, 0.1))
                line(offsetClosed(pts, by: p.restDia / 2), z: s.z1, cut: true)
            }
        }

        for f in p.feats where !f.suppressed {
            let id = "feat-\(f.id.uuidString)"
            let host = hostZ(p, f)
            guard enabled(id) else { continue }
            if f.kind == .hole && p.doHole {
                let hk = f.resolvedHoleKind
                let bottom = holeBottomZ(p, f, host: host)
                // 沉头/沉孔的顶部近似层，先在 2D 里单独画一圈
                if hk == .counterbore || hk == .countersink {
                    let bigD = hk == .counterbore ? f.resolvedCbDia : f.resolvedCsDia
                    let bigDepth = hk == .counterbore ? counterboreDepth(f) : countersinkDepth(f)
                    var s = PocketSpec()
                    s.mode = .spiral
                    s.spiralDia = bigD
                    s.toolDia = p.pocketDia
                    s.depth = bigDepth
                    s.stepDown = p.stepDown
                    s.spindle = p.spindle; s.feed = p.feed; s.safeZ = p.safeZ; s.zTop = host
                    s.hNo = p.pocketTool
                    s.coord = p.coord
                    addSegs(ToolpathEngine.build(s), dx: f.x, dy: f.y)
                }
                var s = PocketSpec()
                s.mode = .spiral
                s.spiralDia = f.dia
                s.toolDia = p.holeDia
                s.depth = max(host - bottom, 0.1)
                s.stepDown = p.stepDown
                s.spindle = p.spindle; s.feed = p.feed; s.safeZ = p.safeZ; s.zTop = host
                s.hNo = p.holeTool
                s.coord = p.coord
                addSegs(ToolpathEngine.build(s), dx: f.x, dy: f.y)
            } else if f.kind == .rectPocket && p.doPocket {
                var s = PocketSpec()
                s.mode = .pocket
                s.length = f.w; s.width = f.h
                s.depth = f.depth; s.stepDown = p.stepDown; s.stepOver = p.stepOver
                s.toolDia = p.pocketDia
                s.spindle = p.spindle; s.feed = p.feed; s.safeZ = p.safeZ; s.zTop = host
                s.hNo = p.pocketTool
                s.coord = p.coord
                addSegs(ToolpathEngine.build(s), dx: f.x, dy: f.y)
            } else if p.doPocket {
                var s = PocketSpec()
                s.mode = .spiral
                s.spiralDia = f.dia
                s.toolDia = p.pocketDia
                s.depth = f.depth; s.stepDown = p.stepDown
                s.spindle = p.spindle; s.feed = p.feed; s.safeZ = p.safeZ; s.zTop = host
                s.hNo = p.pocketTool
                s.coord = p.coord
                addSegs(ToolpathEngine.build(s), dx: f.x, dy: f.y)
            }
        }

        for l in p.innerLoops {
            let id = "loop-\(l.id.uuidString)"
            let host = hostZ(p, l.cx, l.cy)
            guard enabled(id) else { continue }
            if l.template == .circle && l.through && p.doHole {
                var s = PocketSpec()
                s.mode = .spiral
                s.spiralDia = l.circleD
                s.toolDia = p.holeDia
                s.depth = host - minZ(p) + 1
                s.stepDown = p.stepDown
                s.spindle = p.spindle; s.feed = p.feed; s.safeZ = p.safeZ; s.zTop = host
                s.hNo = p.holeTool
                s.coord = p.coord
                addSegs(ToolpathEngine.build(s), dx: l.cx, dy: l.cy)
            } else if p.doPocket {
                let pts = loopPoints(l).map { CGPoint(x: $0.x + CGFloat(l.cx), y: $0.y + CGFloat(l.cy)) }
                line(offsetClosed(pts, by: -p.pocketDia / 2), z: host, cut: true)
            }
        }
        return out
    }

    /// 不含台阶的毛坯外形（用于判断台阶周边粗加工是否出界）
    static func stockBBox(_ p: PartSpec) -> CGRect {
        // 毛坯要包住整件，包括比基础更大的凸台；不能只取基础外形
        let part = bbox(p)
        let m = max(0, p.stockMarginXY)
        return part.insetBy(dx: -m, dy: -m)
    }

    /// 毛坯 Z 范围（用于显示和工序单）
    static func stockZRange(_ p: PartSpec) -> (top: Double, bottom: Double) {
        (maxZ(p) + max(0, p.stockExtraTop), minZ(p) - max(0, p.stockExtraBottom))
    }

    /// 工序按手工顺序重排；未列出的工序排在最后
    static func ordered(_ ops: [PartOpInfo], _ p: PartSpec) -> [PartOpInfo] {
        guard !p.opOrder.isEmpty else { return ops }
        var rank: [String: Int] = [:]
        for (i, id) in p.opOrder.enumerated() where rank[id] == nil { rank[id] = i }
        return ops.sorted { a, b in
            let ra = rank[a.id] ?? Int.max
            let rb = rank[b.id] ?? Int.max
            if ra == rb { return a.id < b.id }
            return ra < rb
        }
    }

    /// 台阶周边粗加工 / 除料台阶清腔的多刀轮廓（刀心轨迹，不含刀补）
    static func stepRoughLoops(_ p: PartSpec, _ s: PartStep) -> [[CGPoint]] {
        let base = pts(s, p)
        guard base.count > 2 else { return [] }
        let isAdd = s.mode == .add
        let dia = max(isAdd ? p.contourDia : p.pocketDia, 0.1)
        let r = dia / 2
        let stepOver = max(p.stepOver, 0.5)
        var out: [[CGPoint]] = []
        if isAdd {
            let sb = stockBBox(p)
            var d = r
            for _ in 0..<10 {
                let q = offsetClosed(base, by: d)
                guard q.count > 2 else { break }
                if !q.allSatisfy({ sb.contains($0) }) { break }
                out.append(q)
                d += stepOver
            }
        } else {
            var d = -r
            for _ in 0..<12 {
                let q = offsetClosed(base, by: d)
                guard q.count > 2 else { break }
                let area = abs(ContourGeo.signedArea(q))
                if area < max(1.0, Double(dia * dia) * 0.25) { break }
                out.append(q)
                d -= stepOver
            }
        }
        return out
    }

    /// 台阶周边粗加工 / 除料台阶清腔：按层下刀，输出可直接并入总程序的段
    static func stepRoughBlock(_ p: PartSpec, _ s: PartStep) -> String {
        let isAdd = s.mode == .add
        let tool = isAdd ? p.contourTool : p.pocketTool
        let loops = stepRoughLoops(p, s)
        guard !loops.isEmpty else { return "( 台阶 \(s.name)：没有可用粗加工刀路 )" }
        let zTop = isAdd ? s.z1 : s.z0
        let zBottom = isAdd ? s.z0 : s.drawBottom
        guard zTop > zBottom + 1e-6 else { return "( 台阶 \(s.name)：Z 范围无效 )" }
        let safe = p.safeZ + maxZ(p)
        let plungeF = max(50, Int(p.feed / 3))
        let dz = max(0.2, p.stepDown)
        var levels: [Double] = []
        var z = zTop
        while z > zBottom + 1e-6 {
            z = max(zBottom, z - dz)
            levels.append(z)
        }
        var L: [String] = []
        L.append("G0 Z\(ncf(safe, 1))")
        L.append("G43 H\(tool) Z\(ncf(safe, 1))")
        L.append("M3 S\(p.spindle)")
        L.append("M8")
        for zz in levels {
            for q in loops {
                guard let first = q.first else { continue }
                L.append("G0 X\(ncf(Double(first.x))) Y\(ncf(Double(first.y)))")
                L.append("G1 Z\(ncf(zz)) F\(plungeF)")
                for pt in q.dropFirst() {
                    L.append("G1 X\(ncf(Double(pt.x))) Y\(ncf(Double(pt.y)))")
                }
                L.append("G1 X\(ncf(Double(first.x))) Y\(ncf(Double(first.y)))")
                L.append("G0 Z\(ncf(safe, 1))")
            }
        }
        L.append("G0 Z\(ncf(safe, 1))")
        return L.joined(separator: "\n")
    }

    static func issues(_ p: PartSpec) -> [String] {
        var out: [String] = []
        let base = ContourProg.issues(asDraw(p, outward: true, dia: p.contourDia, depth: p.height, hNo: p.contourTool))
        out.append(contentsOf: base)
        if p.height <= 0 { out.append("零件厚度要大于 0") }
        if p.contourDia <= 0 { out.append("外形刀径要大于 0") }
        for (i, s) in p.steps.enumerated() {
            if s.height <= 0 { out.append("台阶 \(i + 1)：厚度要大于 0") }
            if s.z1 <= s.z0 { out.append("台阶 \(i + 1)：顶面 Z 必须高于底面 Z") }
            let d = asDraw(s.shape, p, outward: true, dia: p.contourDia,
                          depth: max(s.height, 0.1), hNo: p.contourTool, zTop: s.z1)
            out.append(contentsOf: ContourProg.issues(d).map { "台阶 \(i + 1)：\($0)" })
            if s.mode == .cut {
                out.append("台阶 \(i + 1)：除料层按多刀清腔生成粗加工；边界、深度和清角请按实际刀具核对")
            }
        }
        if !p.steps.isEmpty {
            out.append("多台阶按各层 Z 分别出程序；增料台阶已加周边多刀粗加工，整面飞面和复杂清角仍需按实际毛坯补工步")
        }
        for (i, l) in p.innerLoops.enumerated() {
            let host = hostZ(p, l.cx, l.cy)
            let available = host - minZ(p)
            if !l.through && l.depth > available {
                out.append("内轮廓 \(i + 1)：深度超过该处可用厚度 \(ncf(available))")
            }
        }
        let b = bbox(p)
        for (i, f) in p.feats.enumerated() where !f.suppressed {
            let host = hostZ(p, f)
            let available = host - minZ(p)
            let r = f.dia / 2
            let inside = f.x - r >= b.minX + 0.5 && f.x + r <= b.maxX - 0.5
                && f.y - r >= b.minY + 0.5 && f.y + r <= b.maxY - 0.5
            if !inside {
                out.append("特征 \(i + 1)：Ø\(ncf(f.dia))@X\(ncf(f.x)) Y\(ncf(f.y)) 超出外形范围")
            }
            if f.kind == .hole && p.holeMode == .spiral && p.holeDia >= f.dia {
                out.append("特征 \(i + 1)：孔 Ø\(ncf(f.dia))，刀径必须小于孔径")
            }
            if f.kind == .pocket {
                if p.pocketDia / 2 >= f.dia / 2 {
                    out.append("特征 \(i + 1)：沉台 Ø\(ncf(f.dia))，刀径不能超过半径")
                }
                if f.depth > available { out.append("特征 \(i + 1)：沉台深度超过该处可用厚度 \(ncf(available))") }
            }
            if f.kind == .rectPocket {
                if f.w <= p.pocketDia || f.h <= p.pocketDia {
                    out.append("特征 \(i + 1)：方腔 \(ncf(f.w))×\(ncf(f.h)) 比刀径小")
                }
                if f.depth > available { out.append("特征 \(i + 1)：方腔深度超过该处可用厚度 \(ncf(available))") }
            }
        }
        if p.doRest {
            if p.restDia <= 0 { out.append("残料清角刀径要大于 0") }
            if p.restDia >= p.contourDia {
                out.append("残料清角刀径 Ø\(ncf(p.restDia)) 不小于轮廓/开粗刀径 Ø\(ncf(p.contourDia))：清不到残料")
            }
        }
        out.append(contentsOf: collisionIssues(p))
        return out
    }

    /// 2.5D 近似碰撞检查：毛坯边界、安全高度、刀具号冲突。
    /// 不做真实刀柄/夹具几何，只提示明显会撞的设置。
    static func collisionIssues(_ p: PartSpec) -> [String] {
        var out: [String] = []
        let sb = stockBBox(p)
        let sz = stockZRange(p)
        if p.safeZ <= sz.top + 0.5 {
            out.append("安全高度 Z\(ncf(p.safeZ)) 低于毛坯顶面 Z\(ncf(sz.top))：快移会撞毛坯")
        }
        let tools = [(p.faceTool, p.faceDia), (p.contourTool, p.contourDia),
                     (p.holeTool, p.holeDia), (p.pocketTool, p.pocketDia),
                     (p.tapTool, p.tapDia), (p.restTool, p.restDia)]
        var seen: [Int: Double] = [:]
        for (t, d) in tools where t > 0 {
            if let old = seen[t], abs(old - d) > 0.01 {
                out.append("刀具号 T\(t) 同时被 \(ncf(old)) 和 \(ncf(d)) 使用：刀补会冲突")
            } else {
                seen[t] = d
            }
        }
        for (i, f) in p.feats.enumerated() where !f.suppressed {
            let r = max(p.holeDia, p.pocketDia) / 2
            let margin = min(min(Double(f.x) - Double(sb.minX), Double(sb.maxX) - Double(f.x)),
                             min(Double(f.y) - Double(sb.minY), Double(sb.maxY) - Double(f.y)))
            if margin < r {
                out.append("特征 \(i + 1)：距毛坯边 \(ncf(margin)) mm，小于刀半径 \(ncf(r))：注意夹具/边缘过切")
            }
        }
        return out
    }

    /// 残料清角 / 二次开粗：
    /// 基础外形和增料台阶仍用轮廓补刀；孔/腔用大刀刀路做 2D 扫掠差集，
    /// 检测到残料后用小刀整腔/整孔二次开粗（不是只沿边补一刀）。
    static func restBlock(_ p: PartSpec) -> String {
        var pieces: [String] = []

        func addCode(_ title: String, _ code: String, dx: Double = 0, dy: Double = 0) {
            var code = code
            if abs(dx) > 1e-9 || abs(dy) > 1e-9 {
                code = shift(code, dx: dx, dy: dy)
            }
            let body = strip(code)
            if !body.isEmpty {
                pieces.append("( \(title) T\(p.restTool) D\(ncf(p.restDia)) )\n" + body)
            }
        }

        func addPiece(_ draw: DrawSpec, dx: Double = 0, dy: Double = 0) {
            var d = draw
            d.stepDown = min(max(p.stepDown, 0.5), max(0.5, p.restDia * 1.2))
            d.feed = Double(p.feed)
            d.rpm = Double(p.spindle)
            addCode("残料边界补刀", ContourProg.generate(d), dx: dx, dy: dy)
        }

        func restPocket(_ f: PartFeat, circular: Bool, depth: Double, host: Double, name: String) {
            guard p.restDia > 0.01 else { return }
            var s = PocketSpec()
            s.mode = circular ? .spiral : .pocket
            s.length = max(f.w, 0.1)
            s.width = max(f.h, 0.1)
            s.spiralDia = max(f.dia, 0.1)
            s.cornerType = .square
            s.cornerValue = 0
            s.depth = max(depth, 0.1)
            s.stepDown = min(max(p.stepDown, 0.5), max(0.5, p.restDia * 1.2))
            s.stepOver = min(p.stepOver, max(0.8, p.restDia * 0.65))
            s.toolDia = p.restDia
            s.spindle = p.spindle
            s.feed = p.feed
            s.safeZ = p.safeZ
            s.zTop = host
            s.hNo = p.restTool
            s.coord = p.coord
            s.cx = 0
            s.cy = 0
            addCode("残料二次开粗 \(name)", GCodeGenerator.generate(s), dx: f.x, dy: f.y)
        }

        var base = asDraw(p, outward: true, dia: p.restDia, depth: p.height, hNo: p.restTool)
        base.zTop = 0
        addPiece(base)
        for s in p.steps.filter({ $0.mode == .add }).sorted(by: { $0.z1 > $1.z1 }) {
            let d = asDraw(s.shape, p, outward: true, dia: p.restDia,
                          depth: max(s.height, 0.1), hNo: p.restTool, zTop: s.z1)
            addPiece(d)
        }

        // 内轮廓：圆/方按整腔二次开粗；自由轮廓仍按边界补刀。
        for l in p.innerLoops {
            let host = hostZ(p, l.cx, l.cy)
            let depth = l.through ? max(host - minZ(p), 0.1) : max(l.depth, 0.1)
            if l.template == .circle {
                var fake = PartFeat(kind: .pocket, x: l.cx, y: l.cy, dia: l.circleD, depth: l.depth)
                fake.name = l.name
                restPocket(fake, circular: true, depth: depth, host: host, name: l.name)
            } else if l.template == .rect {
                var fake = PartFeat(kind: .rectPocket, x: l.cx, y: l.cy, dia: l.circleD,
                                    w: l.rectL, h: l.rectW, depth: l.depth)
                fake.name = l.name
                restPocket(fake, circular: false, depth: depth, host: host, name: l.name)
            } else {
                let d = drawForLoop(l, p, depth: depth, dia: p.restDia, hNo: p.restTool, zTop: host)
                addPiece(d)
            }
        }

        for f in p.feats where !f.suppressed {
            let host = hostZ(p, f)
            let depth: Double
            if f.kind == .hole {
                depth = max(host - holeBottomZ(p, f, host: host), 0.1)
            } else {
                depth = max(f.depth, 0.1)
            }
            if f.kind == .rectPocket {
                // 真实 2D 扫掠差集：大刀没盖住的区域才安排二次开粗。
                if ResidualClear.rectPocketHasResidual(p, f) {
                    restPocket(f, circular: false, depth: depth, host: host,
                               name: f.name.isEmpty ? "方腔" : f.name)
                }
            } else if f.kind == .pocket || f.kind == .hole {
                // 圆腔/孔用整圆螺旋小刀清一次，确保大刀具留下的边角被清掉。
                restPocket(f, circular: true, depth: depth, host: host,
                           name: f.name.isEmpty ? "圆腔/孔" : f.name)
            }
        }
        return pieces.joined(separator: "\n")
    }

    /// 把所有工序串成一个程序：共用一段抬头，每段自己带换刀后要用的 G43 H、S、F
    static func build(_ spec: PartSpec, only: Set<String>? = nil,
                      prebuilt: [String: String] = [:]) -> String {
        var p = spec
        let ox = spec.originX, oy = spec.originY
        if abs(ox) > 1e-9 || abs(oy) > 1e-9 {
            p = shifted(spec, dx: -ox, dy: -oy)
        }
        var blocks: [String] = []
        var seq = 0
        var lastTool = -1

        func wanted(_ id: String) -> Bool {
            if let only { return only.contains(id) }
            return !p.disabledOps.contains(id)
        }

        func add(_ title: String, _ tool: Int, _ code: String, id: String? = nil) {
            seq += 1
            var seg = "( ===== 工序\(seq)  \(title) ===== )\n"
            if tool != lastTool {
                seg += "M00 (换刀：装 T\(tool) 后按循环启动)\n"
                lastTool = tool
            }
            var body = code
            if only == nil, let id, let cached = prebuilt[id] {
                body = cached
            }
            var clean = strip(body)
            if only == nil, let id, prebuilt[id] != nil {
                // 单段缓存里已经带了自己的 M00；合并时由上面的换刀逻辑统一控制
                clean = clean.components(separatedBy: "\n")
                    .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("M00") }
                    .joined(separator: "\n")
            }
            seg += clean
            blocks.append(seg)
        }

        // 有台阶时不敢自动飞顶面：毛坯高度和台阶顶面不是同一个 Z，贸然飞面会切到台阶
        if p.doFace && p.topStock > 0 && p.steps.isEmpty && wanted("face") {
            let b = stockBBox(p)
            var s = PocketSpec()
            s.mode = .face
            s.length = Double(b.width)
            s.width = Double(b.height)
            s.depth = p.topStock + max(0, p.stockExtraTop)
            s.zTop = max(0, p.stockExtraTop)
            s.stepDown = min(p.topStock, max(0.3, p.stepDown))
            s.stepOver = p.stepOver
            s.toolDia = p.faceDia
            s.spindle = p.spindle
            s.feed = p.feed
            s.safeZ = p.safeZ
            s.hNo = p.faceTool
            s.coord = p.coord
            s.cx = Double(b.midX)
            s.cy = Double(b.midY)
            add("顶面 平面铣 T\(p.faceTool) D\(ncf(p.faceDia))", p.faceTool, GCodeGenerator.generate(s), id: "face")
        }

        // 先高后低：增料台阶先周边粗加工、再轮廓精加工；除料台阶单独清腔
        for s in p.steps.filter({ $0.mode == .add }).sorted(by: { $0.z1 > $1.z1 }) {
            let roughID = "steprough-\(s.id.uuidString)"
            if wanted(roughID) {
                add("台阶 \(s.name) 周边粗加工  Z\(ncf(s.z0))~Z\(ncf(s.z1)) T\(p.contourTool) D\(ncf(p.contourDia))",
                    p.contourTool, stepRoughBlock(p, s), id: roughID)
            }
            let id = "step-\(s.id.uuidString)"
            guard wanted(id) else { continue }
            let d = asDraw(s.shape, p, outward: true, dia: p.contourDia,
                          depth: max(s.height, 0.1), hNo: p.contourTool, zTop: s.z1)
            add("台阶 \(s.name) \(s.shape.summary)  Z\(ncf(s.z0))~Z\(ncf(s.z1)) 轮廓铣 T\(p.contourTool) D\(ncf(p.contourDia))",
                p.contourTool, ContourProg.generate(d), id: id)
        }
        for s in p.steps.filter({ $0.mode == .cut }).sorted(by: { $0.z0 > $1.z0 }) {
            let id = "stepcut-\(s.id.uuidString)"
            guard wanted(id) else { continue }
            add("台阶 \(s.name) 除料清腔  Z\(ncf(s.drawBottom))~Z\(ncf(s.z0)) T\(p.pocketTool) D\(ncf(p.pocketDia))",
                p.pocketTool, stepRoughBlock(p, s), id: id)
        }

        if p.doContour && wanted("contour") {
            add("外形轮廓铣 T\(p.contourTool) D\(ncf(p.contourDia))", p.contourTool, ContourProg.generate(outline(p)), id: "contour")
        }
        if p.doChamfer && wanted("chamfer") {
            var cd = outline(p)
            cd.depth = max(p.chamferSize, 0.1)
            cd.stepDown = max(p.chamferSize, 0.1)
            cd.zTop = 0
            add("轮廓倒角 C\(ncf(p.chamferSize))（2.5D 近似，只对基础外形） T\(p.contourTool) D\(ncf(p.contourDia))",
                p.contourTool, ContourProg.generate(cd), id: "chamfer")
        }
        if p.doRest && wanted("rest") {
            add("残料清角 / 二次开粗（2.5D 近似） T\(p.restTool) D\(ncf(p.restDia))",
                p.restTool, restBlock(p), id: "rest")
        }

        for f in p.feats where !f.suppressed {
            let id = "feat-\(f.id.uuidString)"
            let host = hostZ(p, f)
            guard wanted(id) else { continue }
            if f.kind == .hole {
                guard p.doHole else { continue }
                let hk = f.resolvedHoleKind
                let bottom = holeBottomZ(p, f, host: host)
                let mode = holeMode(p, f)
                // 沉头顶部大径：2.5D 用浅圆柱近似
                if hk == .counterbore {
                    let cbID = "\(id)-cb"
                    if wanted(cbID) {
                        var d = asDraw(p, outward: false, template: .circle,
                                       circleD: f.resolvedCbDia,
                                       dia: p.pocketDia, depth: counterboreDepth(f), hNo: p.pocketTool)
                        d.zTop = host
                        var code = ContourProg.generate(d)
                        code = shift(code, dx: f.x, dy: f.y)
                        add("沉头 Ø\(ncf(f.resolvedCbDia)) 深\(ncf(counterboreDepth(f))) @X\(ncf(f.x)) Y\(ncf(f.y)) 圆柱近似 T\(p.pocketTool) D\(ncf(p.pocketDia))",
                            p.pocketTool, code, id: cbID)
                    }
                }
                // 沉孔顶部锥面：2.5D 用倒角圆近似
                if hk == .countersink {
                    let csID = "\(id)-cs"
                    if wanted(csID) {
                        var d = asDraw(p, outward: false, template: .circle,
                                       circleD: f.resolvedCsDia,
                                       dia: p.pocketDia, depth: countersinkDepth(f), hNo: p.pocketTool)
                        d.zTop = host
                        var code = ContourProg.generate(d)
                        code = shift(code, dx: f.x, dy: f.y)
                        add("沉孔 Ø\(ncf(f.resolvedCsDia)) \(ncf(f.resolvedCsAngle))° 深\(ncf(countersinkDepth(f))) @X\(ncf(f.x)) Y\(ncf(f.y)) 锥面近似 T\(p.pocketTool) D\(ncf(p.pocketDia))",
                            p.pocketTool, code, id: csID)
                    }
                }
                switch mode {
                case .spiral:
                    var s = PocketSpec()
                    s.mode = .spiral
                    s.spiralDia = f.dia
                    s.toolDia = p.holeDia
                    s.depth = max(host - bottom, 0.1)
                    s.stepDown = p.stepDown
                    s.spindle = p.spindle
                    s.feed = p.feed
                    s.safeZ = p.safeZ; s.zTop = host
                    s.hNo = p.holeTool
                    s.coord = p.coord
                    s.cx = f.x
                    s.cy = f.y
                    add("孔 Ø\(ncf(f.dia)) \(f.holeSummary) @X\(ncf(f.x)) Y\(ncf(f.y)) 螺旋铣 T\(p.holeTool) D\(ncf(p.holeDia))",
                        p.holeTool, GCodeGenerator.generate(s), id: id)
                case .g81, .g83:
                    add("孔 Ø\(ncf(f.dia)) \(f.holeSummary) @X\(ncf(f.x)) Y\(ncf(f.y)) 钻孔 \(mode == .g81 ? "G81" : "G83")",
                        p.holeTool, drillBlock(p, f, zTop: host, zBottom: bottom), id: id)
                case .tap:
                    add("孔 Ø\(ncf(f.dia)) \(f.holeSummary) @X\(ncf(f.x)) Y\(ncf(f.y)) 攻丝 G84 P\(ncf(p.tapPitch))",
                        p.tapTool, tapBlock(p, f, zTop: host, zBottom: bottom), id: id)
                }
            } else if p.doPocket && f.kind == .rectPocket {
                var d = asDraw(p, outward: false, template: .rect,
                               dia: p.pocketDia, depth: f.depth, hNo: p.pocketTool)
                d.rectL = f.w
                d.rectW = f.h
                d.rectR = 0
                d.zTop = host
                var code = ContourProg.generate(d)
                code = shift(code, dx: f.x, dy: f.y)
                add("方腔 \(ncf(f.w))×\(ncf(f.h)) 深\(ncf(f.depth)) @X\(ncf(f.x)) Y\(ncf(f.y)) 型腔铣 T\(p.pocketTool) D\(ncf(p.pocketDia))",
                    p.pocketTool, code, id: id)
            } else if p.doPocket {
                var d = asDraw(p, outward: false, template: .circle, circleD: f.dia,
                               dia: p.pocketDia, depth: f.depth, hNo: p.pocketTool)
                d.zTop = host
                var code = ContourProg.generate(d)
                code = shift(code, dx: f.x, dy: f.y)
                add("沉台 Ø\(ncf(f.dia)) 深\(ncf(f.depth)) @X\(ncf(f.x)) Y\(ncf(f.y)) 型腔铣 T\(p.pocketTool) D\(ncf(p.pocketDia))",
                    p.pocketTool, code, id: id)
            }
        }

        for l in p.innerLoops {
            let id = "loop-\(l.id.uuidString)"
            let host = hostZ(p, l.cx, l.cy)
            guard wanted(id) else { continue }
            if l.template == .circle && l.through && !p.doHole { continue }
            if !(l.template == .circle && l.through) && !p.doPocket { continue }
            let depth = l.through ? host - minZ(p) + 1 : min(l.depth, host - minZ(p))
            if l.template == .circle && l.through {
                switch p.holeMode {
                case .spiral:
                    var s = PocketSpec()
                    s.mode = .spiral
                    s.spiralDia = l.circleD
                    s.toolDia = p.holeDia
                    s.depth = depth
                    s.stepDown = p.stepDown
                    s.spindle = p.spindle
                    s.feed = p.feed
                    s.safeZ = p.safeZ; s.zTop = maxZ(p)
                    s.hNo = p.holeTool
                s.coord = p.coord
                    s.cx = l.cx
                    s.cy = l.cy
                    add("\(l.name) Ø\(ncf(l.circleD)) @X\(ncf(l.cx)) Y\(ncf(l.cy)) 螺旋铣 T\(p.holeTool) D\(ncf(p.holeDia))",
                        p.holeTool, GCodeGenerator.generate(s), id: id)
                case .g81, .g83:
                    let f = PartFeat(kind: .hole, x: l.cx, y: l.cy, dia: l.circleD, depth: depth)
                    add("\(l.name) Ø\(ncf(l.circleD)) @X\(ncf(l.cx)) Y\(ncf(l.cy)) 钻孔 \(p.holeMode == .g81 ? "G81" : "G83")",
                        p.holeTool, drillBlock(p, f, zTop: host), id: id)
                case .tap:
                    let f = PartFeat(kind: .hole, x: l.cx, y: l.cy, dia: l.circleD, depth: depth)
                    add("\(l.name) Ø\(ncf(l.circleD)) @X\(ncf(l.cx)) Y\(ncf(l.cy)) 攻丝 G84 P\(ncf(p.tapPitch))",
                        p.tapTool, tapBlock(p, f, zTop: host), id: id)
                }
            } else {
                let d = drawForLoop(l, p, depth: depth, dia: p.pocketDia, hNo: p.pocketTool, zTop: host)
                var code = ContourProg.generate(d)
                code = shift(code, dx: l.cx, dy: l.cy)
                add("\(l.name) \(l.template.rawValue) 深\(ncf(depth)) @X\(ncf(l.cx)) Y\(ncf(l.cy)) 型腔铣 T\(p.pocketTool) D\(ncf(p.pocketDia))",
                    p.pocketTool, code, id: id)
            }
        }

        var L: [String] = []
        L.append("%")
        L.append("O\(p.programNo) (绘图编程 · 多工序)")
        let b = bbox(p)
        let stepNote = p.steps.isEmpty ? "" : "  台阶\(p.steps.count)层"
        let sb = stockBBox(p)
        let sz = stockZRange(p)
        L.append("( 工程 \(p.projectName)  后处理 \(p.postName) )")
        if p.postName.contains("三菱") {
            L.append("( 三菱 M70/M80：按 FANUC 兼容子集输出，G54/G41/G43 与宏B可用 )")
        }
        if p.postName.contains("Siemens") {
            L.append("( Siemens 840D：宏已展开成普通G代码；G43/G28/G52 仍需按机床核对 )")
        }
        L.append("( 外形 \(ncf(Double(b.width))) × \(ncf(Double(b.height)))  厚\(ncf(p.height))\(stepNote)  顶面余量\(ncf(p.topStock)) )")
        L.append("( 毛坯 \(ncf(Double(sb.width))) × \(ncf(Double(sb.height)))  Z\(ncf(sz.bottom))~\(ncf(sz.top))  XY余量\(ncf(p.stockMarginXY)) )")
        L.append("( 工件坐标系 G\(p.coord)  X0=\(ncf(ox)) Y0=\(ncf(oy)) (草图坐标)  Z0=基础顶面；台阶顶面为正值 )")
        L.append("( 共 \(blocks.count) 道工序，每段前面注明了用哪把刀，换刀后从该段重新启动 )")
        L.append("G17 G21 G40 G49 G80 G90 G\(p.coord)")
        L.append("( X0 Y0 为 G\(p.coord) 零点；已按上面基准平移，程序坐标为工件坐标 )")
        L.append(blocks.joined(separator: "\n"))
        L.append("G0 Z\(ncf(p.safeZ + maxZ(p), 1))")
        if p.optionalStop { L.append("M01") }
        L.append("M5")
        L.append("M9")
        L.append("G28 G91 Z0")
        L.append("G90")
        L.append("M30")
        L.append("%")
        let fanuc = L.joined(separator: "\n")
        if p.postName.contains("Siemens") {
            return PostProcessor.siemens(fanuc)
        }
        return fanuc
    }

    // MARK: - 拼装工具

    /// 去掉子程序自己的抬头/结尾，只留可执行的段落
    static func strip(_ code: String) -> String {
        var out: [String] = []
        for raw in code.components(separatedBy: "\n") {
            let t = raw.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            if t.hasPrefix("%") { continue }
            if t.hasPrefix("O"), t.count > 1, let c = t.dropFirst().first, c.isNumber { continue }
            if t.hasPrefix("G17 G21 G40 G49 G80 G90") { continue }
            if t.hasPrefix("G28") { continue }
            if t == "M30" || t == "M5" || t == "M9" { continue }
            out.append(t)
        }
        return out.joined(separator: "\n")
    }

    /// G81 / G83 钻孔
    static func drillBlock(_ p: PartSpec, _ f: PartFeat, zTop: Double, zBottom: Double? = nil) -> String {
        let z = zBottom ?? (minZ(p) - 1)
        var L: [String] = []
        L.append("G0 Z\(ncf(p.safeZ + maxZ(p), 1))")
        L.append("( 孔 Ø\(ncf(f.dia)) \(f.holeSummary) @X\(ncf(f.x)) Y\(ncf(f.y)) )")
        var line = "G98 G\(holeMode(p, f) == .g81 ? "81" : "83") X\(ncf(f.x)) Y\(ncf(f.y)) Z\(ncf(z, 1)) R\(ncf(zTop + 2, 1)) F\(p.feed)"
        if holeMode(p, f) == .g83 { line += " Q\(ncf(p.peck))" }
        L.append(line)
        L.append("G80")
        return L.joined(separator: "\n")
    }

    /// G84 攻丝：M29 刚性攻丝，F = 螺距 × 转速
    static func tapBlock(_ p: PartSpec, _ f: PartFeat, zTop: Double, zBottom: Double? = nil) -> String {
        let z = zBottom ?? (minZ(p) - 1)
        var L: [String] = []
        L.append("G0 Z\(ncf(p.safeZ + maxZ(p), 1))")
        L.append("( 攻丝 Ø\(ncf(f.dia)) P\(ncf(p.tapPitch)) @X\(ncf(f.x)) Y\(ncf(f.y)) )")
        L.append("M29 S\(p.tapRpm)")
        L.append("G98 G84 X\(ncf(f.x)) Y\(ncf(f.y)) Z\(ncf(z, 1)) R\(ncf(zTop + 2, 1)) F\(ncf(Double(p.tapRpm) * p.tapPitch))")
        L.append("G80")
        return L.joined(separator: "\n")
    }

    /// 只平移 X / Y 数值（I、J 是增量，不能动；注释行不动）
    static func shift(_ code: String, dx: Double, dy: Double) -> String {
        let pattern = "([XY])(-?[0-9]+(?:\\.[0-9]*)?)"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return code }
        var out: [String] = []
        for raw in code.components(separatedBy: "\n") {
            let t = raw.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { out.append(t); continue }
            if t.hasPrefix("(") { out.append(t); continue }
            let ns = t as NSString
            let ms = re.matches(in: t, range: NSRange(location: 0, length: ns.length))
            if ms.isEmpty { out.append(t); continue }
            var line = t
            for m in ms.reversed() {
                guard m.numberOfRanges == 3 else { continue }
                let ax = ns.substring(with: m.range(at: 1))
                let vv = ns.substring(with: m.range(at: 2))
                guard let v = Double(vv) else { continue }
                let nv = ax == "X" ? v + dx : v + dy
                let rep = ax + ncf(nv)
                if let r = Range(m.range, in: line) {
                    line.replaceSubrange(r, with: rep)
                }
            }
            out.append(line)
        }
        return out.joined(separator: "\n")
    }
}
