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
    /// 新建的矩形台阶按“中心”解释 cx/cy；旧工程默认 false，保持原来的左下角偏移，避免升级后整层乱跑。
    var centeredRect: Bool = false

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
        case template, rectL, rectW, rectR, circleD, slotL, slotW, nodes, cx, cy, centeredRect
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
        centeredRect = try c.decodeIfPresent(Bool.self, forKey: .centeredRect) ?? false
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
        try c.encode(centeredRect, forKey: .centeredRect)
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
    /// 工序禁用（旧工程兼容字段，当前 3D 流程不使用）
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
    /// 残料清角 / 二次开粗：基础外形和台阶仍沿边界补刀；
    /// 方腔按大刀 2D 刀路扫掠差集判断，有残料才整腔二次开粗；
    /// 圆腔/孔用小刀整圆清一次。仍是 2.5D，不做 3D 实体布尔。
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
