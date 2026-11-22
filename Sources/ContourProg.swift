import Foundation
import CoreGraphics

// MARK: - 轮廓数据模型

/// 一段轮廓的类型（存在"终点节点"上）
enum ContourKind: String, CaseIterable, Identifiable, Codable {
    case line = "直线"
    case cw = "圆弧 顺 G2"
    case ccw = "圆弧 逆 G3"
    var id: String { rawValue }
}

/// 轮廓节点：kind 表示"从上一个点到本点"这一段用什么走
struct ContourNode: Identifiable, Equatable, Codable {
    var id = UUID()
    var x: Double = 0
    var y: Double = 0
    var kind: ContourKind = .line
    var r: Double = 10
}

enum ContourTemplate: String, CaseIterable, Identifiable, Codable {
    case rect = "矩形"
    case circle = "圆"
    case slot = "腰形槽"
    case free = "自定义"
    var id: String { rawValue }
}

/// 绘图编程的全部输入
struct DrawSpec {
    var template: ContourTemplate = .rect
    // 模板尺寸
    var rectL: Double = 100
    var rectW: Double = 60
    var rectR: Double = 0
    var circleD: Double = 50
    var slotL: Double = 80
    var slotW: Double = 20

    // 自定义节点（只有 template == .free 时生效）
    var nodes: [ContourNode] = []

    // 刀具与切削
    var toolDia: Double = 12
    var depth: Double = 5
    var stepDown: Double = 1
    var feed: Double = 400
    var rpm: Double = 2000
    var safeZ: Double = 50
    var hNo: Int = 13
    var coord: Int = 54          // G54~G59
    var outward: Bool = true      // true 外形（刀在轮廓外） / false 内腔（刀在轮廓内）
    var leadR: Double = 0         // 0 = 自动取 刀径/2 + 2
    var zTop: Double = 0          // 这一层的顶面 Z；基础层为 0，台阶层为正
}

/// 一段真实轮廓（几何）
struct ContourSeg {
    var p0: CGPoint
    var p1: CGPoint
    var kind: ContourKind
    var r: Double
    var full: Bool = false        // 整圆（p0 == p1，靠 I/J 定圆心）

    var isArc: Bool { kind != .line }
}

// MARK: - 几何

enum ContourGeo {

    /// 两点 + 半径求圆心；cw 为 true 表示顺时针（G2）
    static func arcCenter(_ p0: CGPoint, _ p1: CGPoint, _ r: Double, cw: Bool) -> CGPoint? {
        let dx = p1.x - p0.x, dy = p1.y - p0.y
        let d = hypot(dx, dy)
        guard d > 1e-9, r > 1e-6, d <= 2 * r + 1e-6 else { return nil }
        let h = sqrt(max(0, r * r - d * d / 4))
        let mx = (p0.x + p1.x) / 2, my = (p0.y + p1.y) / 2
        let nx = -dy / d, ny = dx / d
        let c1 = CGPoint(x: mx + nx * h, y: my + ny * h)
        let c2 = CGPoint(x: mx - nx * h, y: my - ny * h)
        func left(_ c: CGPoint) -> Bool {
            (p0.x - c.x) * (p1.y - c.y) - (p0.y - c.y) * (p1.x - c.x) > 0
        }
        // 逆时针（G3）要求叉积 > 0
        return (left(c1) != cw) ? c1 : c2
    }

    /// 某段在起点处的单位切向
    static func tangent(_ seg: ContourSeg) -> CGPoint {
        if !seg.isArc {
            let dx = seg.p1.x - seg.p0.x, dy = seg.p1.y - seg.p0.y
            let d = hypot(dx, dy)
            guard d > 1e-9 else { return CGPoint(x: 1, y: 0) }
            return CGPoint(x: dx / d, y: dy / d)
        }
        if seg.full {
            // 整圆：起点在 (cx + r, cy)，顺时针切向朝 -Y
            return seg.kind == .cw ? CGPoint(x: 0, y: -1) : CGPoint(x: 0, y: 1)
        }
        guard let c = arcCenter(seg.p0, seg.p1, seg.r, cw: seg.kind == .cw) else {
            let dx = seg.p1.x - seg.p0.x, dy = seg.p1.y - seg.p0.y
            let d = max(hypot(dx, dy), 1e-9)
            return CGPoint(x: dx / d, y: dy / d)
        }
        let v = CGPoint(x: seg.p0.x - c.x, y: seg.p0.y - c.y)
        let len = max(hypot(v.x, v.y), 1e-9)
        if seg.kind == .cw {
            return CGPoint(x: v.y / len, y: -v.x / len)
        }
        return CGPoint(x: -v.y / len, y: v.x / len)
    }

    /// 各段离散成点，用于预览与方向判断
    static func flatten(_ segs: [ContourSeg], arcStep: Int = 16) -> [CGPoint] {
        var out: [CGPoint] = []
        for seg in segs {
            if out.isEmpty { out.append(seg.p0) }
            if !seg.isArc {
                out.append(seg.p1)
                continue
            }
            if seg.full {
                let cx = seg.p0.x - seg.r
                let cy = seg.p0.y
                for i in 1...max(arcStep * 2, 24) {
                    let t = Double(i) / Double(max(arcStep * 2, 24))
                    let a = (seg.kind == .cw ? -1.0 : 1.0) * 2 * .pi * t
                    out.append(CGPoint(x: cx + seg.r * CGFloat(cos(Double(a))), y: cy + seg.r * CGFloat(sin(Double(a)))))
                }
                continue
            }
            guard let c = arcCenter(seg.p0, seg.p1, seg.r, cw: seg.kind == .cw) else {
                out.append(seg.p1)
                continue
            }
            let a0 = atan2(seg.p0.y - c.y, seg.p0.x - c.x)
            var a1 = atan2(seg.p1.y - c.y, seg.p1.x - c.x)
            if seg.kind == .cw {
                while a1 > a0 - 1e-9 { a1 -= 2 * .pi }
            } else {
                while a1 < a0 + 1e-9 { a1 += 2 * .pi }
            }
            let n = max(arcStep, 6)
            for i in 1...n {
                let t = Double(i) / Double(n)
                let a = a0 + (a1 - a0) * t
                out.append(CGPoint(x: c.x + seg.r * CGFloat(cos(Double(a))), y: c.y + seg.r * CGFloat(sin(Double(a)))))
            }
        }
        return out
    }

    /// 正面积 = 逆时针
    static func signedArea(_ pts: [CGPoint]) -> Double {
        guard pts.count > 2 else { return 0 }
        var s = 0.0
        for i in 0..<pts.count {
            let a = pts[i], b = pts[(i + 1) % pts.count]
            s += a.x * b.y - b.x * a.y
        }
        return s / 2
    }

    // MARK: 模板

    /// 按模板生成节点表（第一个节点是起点，kind 表示从上一个点到它这一段）
    static func buildNodes(_ s: DrawSpec) -> [ContourNode] {
        switch s.template {
        case .rect:
            return rectNodes(s)
        case .circle:
            var n = ContourNode(x: s.circleD / 2, y: 0, kind: .cw, r: s.circleD / 2)
            n.x = s.circleD / 2
            return [n]
        case .slot:
            return slotNodes(s)
        case .free:
            return s.nodes
        }
    }

    private static func rectNodes(_ s: DrawSpec) -> [ContourNode] {
        let l = max(s.rectL, 1), w = max(s.rectW, 1)
        let r = max(0, min(s.rectR, min(l, w) / 2 - 0.001))
        var out: [ContourNode] = []
        if r < 0.01 {
            // 起点取下边中点，进刀不会在角上
            out.append(ContourNode(x: l / 2, y: 0))
            out.append(ContourNode(x: l, y: 0))
            out.append(ContourNode(x: l, y: w))
            out.append(ContourNode(x: 0, y: w))
            out.append(ContourNode(x: 0, y: 0))
            return out
        }
        out.append(ContourNode(x: l / 2, y: 0))
        out.append(ContourNode(x: l - r, y: 0))
        out.append(ContourNode(x: l, y: r, kind: .ccw, r: r))
        out.append(ContourNode(x: l, y: w - r))
        out.append(ContourNode(x: l - r, y: w, kind: .ccw, r: r))
        out.append(ContourNode(x: r, y: w))
        out.append(ContourNode(x: 0, y: w - r, kind: .ccw, r: r))
        out.append(ContourNode(x: 0, y: r))
        out.append(ContourNode(x: r, y: 0, kind: .ccw, r: r))
        return out
    }

    private static func slotNodes(_ s: DrawSpec) -> [ContourNode] {
        let len = max(s.slotL, 1), w = max(s.slotW, 1)
        let r = w / 2
        let dx = max(len / 2 - r, 0)
        var out: [ContourNode] = []
        out.append(ContourNode(x: -dx, y: -r))
        out.append(ContourNode(x: dx, y: -r))
        out.append(ContourNode(x: dx, y: r, kind: .ccw, r: r))
        out.append(ContourNode(x: -dx, y: r))
        out.append(ContourNode(x: -dx, y: -r, kind: .ccw, r: r))
        return out
    }

    /// 节点表 → 轮廓段（末尾自动用直线闭合）
    static func segments(_ nodes: [ContourNode]) -> [ContourSeg] {
        var out: [ContourSeg] = []
        guard !nodes.isEmpty else { return out }
        if nodes.count == 1 {
            let n = nodes[0]
            // 单独一个“直线节点”只是落点，不能当成整圆
            if n.kind == .line { return out }
            let p = CGPoint(x: n.x, y: n.y)
            out.append(ContourSeg(p0: p, p1: p, kind: n.kind,
                                  r: max(n.r, 0.001), full: true))
            return out
        }
        for i in 1..<nodes.count {
            let a = nodes[i - 1], b = nodes[i]
            out.append(ContourSeg(p0: CGPoint(x: a.x, y: a.y),
                                  p1: CGPoint(x: b.x, y: b.y),
                                  kind: b.kind, r: b.r))
        }
        let last = nodes[nodes.count - 1], first = nodes[0]
        let d = hypot(last.x - first.x, last.y - first.y)
        if d > 1e-6 {
            out.append(ContourSeg(p0: CGPoint(x: last.x, y: last.y),
                                  p1: CGPoint(x: first.x, y: first.y),
                                  kind: .line, r: 0))
        }
        return out
    }
}

// MARK: - 程序生成

enum ContourProg {

    static func leadRadius(_ s: DrawSpec) -> Double {
        s.leadR > 0.5 ? s.leadR : s.toolDia / 2 + 2
    }

    static func issues(_ s: DrawSpec) -> [String] {
        var out: [String] = []
        let nodes = ContourGeo.buildNodes(s)
        if nodes.isEmpty { out.append("轮廓至少要有 1 个点"); return out }
        if s.toolDia <= 0 { out.append("刀具直径要大于 0") }
        if s.depth <= 0 { out.append("加工深度要大于 0") }
        if s.stepDown <= 0 { out.append("每层切深要大于 0") }
        if s.stepDown > s.depth { out.append("每层切深比总深还大，会只切一刀") }
        if s.template == .rect && s.rectL <= s.toolDia {
            out.append("矩形长比刀径还小，刀进不去")
        }
        for (i, seg) in ContourGeo.segments(nodes).enumerated() {
            if seg.isArc && !seg.full {
                let d = hypot(seg.p1.x - seg.p0.x, seg.p1.y - seg.p0.y)
                if ContourGeo.arcCenter(seg.p0, seg.p1, seg.r, cw: seg.kind == .cw) == nil {
                    out.append("第 \(i + 1) 段圆弧：R\(ncf(seg.r)) 配不上弦长 \(ncf(d))（R 要大于弦长一半）")
                }
            }
        }
        return out
    }

    static func generate(_ s: DrawSpec) -> String {
        let nodes = ContourGeo.buildNodes(s)
        let segs = ContourGeo.segments(nodes)
        guard let first = segs.first else { return "( 没有轮廓 )" }

        let pts = ContourGeo.flatten(segs)
        let ccw = ContourGeo.signedArea(pts) > 0
        // 外形：顺时针走时刀在左侧(G41)；内腔：逆时针走时刀在左侧(G41)
        let useLeft = s.outward ? !ccw : ccw
        let compCode = useLeft ? "G41" : "G42"
        let leadCode = useLeft ? "G3" : "G2"

        let p0 = first.p0
        let t0 = ContourGeo.tangent(first)
        // 左侧法向 = (-ty, tx)；右侧法向 = (ty, -tx)
        let n = useLeft ? CGPoint(x: -t0.y, y: t0.x) : CGPoint(x: t0.y, y: -t0.x)
        let lead = leadRadius(s)
        let ap = CGPoint(x: p0.x + n.x * lead * 2, y: p0.y + n.y * lead * 2)
        let cp = CGPoint(x: p0.x + n.x * lead, y: p0.y + n.y * lead)

        let layers = max(1, Int(ceil(s.depth / s.stepDown - 1e-9)))
        let plungeF = max(50, Int(s.feed / 3))

        var L: [String] = []
        L.append("%")
        L.append("O1010 (绘图编程 轮廓)")
        L.append("( \(s.outward ? "外形, 刀在轮廓外" : "内腔, 刀在轮廓内")  \(ccw ? "逆时针" : "顺时针") 走向 )")
        L.append("( 刀Ø\(ncf(s.toolDia))  深\(ncf(s.depth))  每层\(ncf(s.stepDown))  层数\(layers) )")
        L.append("( 起点 X\(ncf(p0.x)) Y\(ncf(p0.y))  半圆进刀R\(ncf(lead)) )")
        L.append("G17 G21 G40 G49 G80 G90 G\(s.coord)")
        L.append("( X0 Y0 就是 G54 零点, 不对刀不用改 )")
        L.append("G43 H\(s.hNo) Z\(ncf(s.safeZ + s.zTop, 1))")
        L.append("M3 S\(Int(s.rpm))")
        L.append("M8")
        L.append("#1=\(ncf(s.depth)) (总深)")
        L.append("#2=\(ncf(s.stepDown)) (每层)")
        L.append("#6=\(ncf(s.feed, 1)) (切削F)")
        L.append("#4=\(plungeF) (下刀F, 取切削的1/3)")
        L.append("#10=0 (层号)")
        L.append("#11=\(ncf(s.zTop, 1)) (这一层顶面Z)")
        L.append("G0 X\(ncf(ap.x)) Y\(ncf(ap.y)) (起刀点, 轮廓外)")
        L.append("G0 Z\(ncf(s.zTop + 2, 1))")
        L.append("G1 Z\(ncf(s.zTop, 1)) F#4")
        L.append("( ===== 一层一层往下, 每层到位再切一圈, 不抬Z ===== )")
        L.append("WHILE[#10LT\(layers)]DO1")
        L.append("#10=#10+1")
        L.append("#5=#10*#2")
        L.append("IF[#5GT#1]THEN#5=#1")
        L.append("G1 Z[#11-#5] F#4 (本层下刀)")
        L.append("\(compCode) D\(s.hNo) \(leadCode) X\(ncf(p0.x)) Y\(ncf(p0.y)) I\(ncf(cp.x - ap.x)) J\(ncf(cp.y - ap.y)) F#6 (半圆切入)")

        for seg in segs {
            if !seg.isArc {
                L.append("G1 X\(ncf(seg.p1.x)) Y\(ncf(seg.p1.y))")
                continue
            }
            if seg.full {
                let cx = seg.p0.x - seg.r, cy = seg.p0.y
                L.append("\(seg.kind == .cw ? "G2" : "G3") X\(ncf(seg.p0.x)) Y\(ncf(seg.p0.y)) I\(ncf(cx - seg.p0.x)) J\(ncf(cy - seg.p0.y)) (整圆)")
                continue
            }
            guard let c = ContourGeo.arcCenter(seg.p0, seg.p1, seg.r, cw: seg.kind == .cw) else {
                L.append("G1 X\(ncf(seg.p1.x)) Y\(ncf(seg.p1.y)) (圆弧算不出圆心, 改为直线, 请检查R)")
                continue
            }
            L.append("\(seg.kind == .cw ? "G2" : "G3") X\(ncf(seg.p1.x)) Y\(ncf(seg.p1.y)) I\(ncf(c.x - seg.p0.x)) J\(ncf(c.y - seg.p0.y))")
        }

        L.append("G40 \(leadCode) X\(ncf(ap.x)) Y\(ncf(ap.y)) I\(ncf(cp.x - p0.x)) J\(ncf(cp.y - p0.y)) (半圆切出, 取消刀补)")
        L.append("END1")
        L.append("G0 Z\(ncf(s.safeZ + s.zTop, 1))")
        L.append("M5")
        L.append("M9")
        L.append("G28 G91 Z0")
        L.append("G28 G91 Y0")
        L.append("G90")
        L.append("M30")
        L.append("%")
        return L.joined(separator: "\n")
    }

    /// 给界面用的分段说明
    static func summary(_ s: DrawSpec) -> String {
        let segs = ContourGeo.segments(ContourGeo.buildNodes(s))
        let lineCount = segs.filter { !$0.isArc }.count
        let arcCount = segs.count - lineCount
        let pts = ContourGeo.flatten(segs)
        let ccw = ContourGeo.signedArea(pts) > 0
        return "\(segs.count) 段（直线 \(lineCount) · 圆弧 \(arcCount)），\(ccw ? "逆时针" : "顺时针")，\(s.outward ? "外形刀在轮廓外" : "内腔刀在轮廓内")"
    }
}

/// 去掉多余小数零
func ncf(_ v: Double, _ d: Int = 3) -> String {
    if abs(v) < 5e-4 { return "0" }
    var s = String(format: "%.\(d)f", v)
    if s.contains(".") {
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
    }
    if s == "-0" { s = "0" }
    return s
}
