import Foundation
import CoreGraphics

/// 一段刀路：cut 切削 / 快移，z 该段深度，pts 折线点（XY，单位 mm）
struct TPSeg {
    var cut: Bool
    var z: Double
    var pts: [CGPoint]
    var len: Double
}

enum ToolpathEngine {

    static func totalLen(_ segs: [TPSeg]) -> Double {
        segs.reduce(0) { $0 + $1.len }
    }

    static func build(_ s: PocketSpec) -> [TPSeg] {
        switch s.mode {
        case .taper: return taper(s)
        case .face: return face(s)
        case .spiral: return spiral(s)
        case .key: return key(s)
        case .outer: return outer(s)
        case .innerChamfer: return chamfer(s)
        case .odCham: return odCham(s)
        default: return pocket(s)
        }
    }

    // 工件轮廓参考线（闭合）
    static func outline(_ s: PocketSpec) -> [CGPoint] {
        var p: [CGPoint] = []
        switch s.mode {
        case .pocket:
            let a = s.length / 2, b = s.width / 2, rc = min(s.cornerValue, min(a, b))
            p.append(CGPoint(x: a, y: 0))
            p.append(CGPoint(x: a, y: b - rc))
            p += arc(cx: a - rc, cy: b - rc, r: rc, from: 0, to: 90)
            p.append(CGPoint(x: -(a - rc), y: b))
            p += arc(cx: -(a - rc), cy: b - rc, r: rc, from: 90, to: 180)
            p.append(CGPoint(x: -a, y: -(b - rc)))
            p += arc(cx: -(a - rc), cy: -(b - rc), r: rc, from: 180, to: 270)
            p.append(CGPoint(x: a - rc, y: -b))
            p += arc(cx: a - rc, cy: -(b - rc), r: rc, from: 270, to: 360)
            p.append(CGPoint(x: a, y: 0))
        case .taper:
            p += circlePts(s.taperDia / 2)
        case .innerChamfer:
            p += circlePts(s.chaDia / 2 + s.chaDepth * tan(s.chaAngle / 2 * .pi / 180))
        case .face:
            let hl = s.length / 2, hw = s.width / 2
            p = [CGPoint(x: -hl, y: -hw), CGPoint(x: hl, y: -hw),
                 CGPoint(x: hl, y: hw), CGPoint(x: -hl, y: hw), CGPoint(x: -hl, y: -hw)]
        case .spiral:
            p += circlePts(s.spiralDia / 2)
        case .outer:
            let a = s.length / 2, b = s.width / 2
            let rc = s.cornerType == .radius ? min(s.cornerValue, min(a, b)) : 0
            p = [CGPoint(x: -(a - rc), y: b), CGPoint(x: a - rc, y: b)]
            p += arc(cx: a - rc, cy: b - rc, r: rc, from: 90, to: 0)
            p.append(CGPoint(x: a, y: -(b - rc)))
            p += arc(cx: a - rc, cy: -(b - rc), r: rc, from: 0, to: -90)
            p.append(CGPoint(x: -(a - rc), y: -b))
            p += arc(cx: -(a - rc), cy: -(b - rc), r: rc, from: 270, to: 180)
            p.append(CGPoint(x: -a, y: b - rc))
            p += arc(cx: -(a - rc), cy: b - rc, r: rc, from: 180, to: 90)
            p.append(CGPoint(x: -(a - rc), y: b))
        case .key:
            let xc = (s.keyLength - s.keyWidth) / 2
            let yh = s.keyWidth / 2
            p = [CGPoint(x: -xc, y: -yh), CGPoint(x: xc, y: -yh)]
            p += arc(cx: xc, cy: 0, r: yh, from: -90, to: 90)
            p += [CGPoint(x: xc, y: yh), CGPoint(x: -xc, y: yh)]
            p += arc(cx: -xc, cy: 0, r: yh, from: 90, to: 270)
            p.append(CGPoint(x: -xc, y: -yh))
        case .odCham:
            p += circlePts(s.odDia / 2)
        }
        return p
    }

    // MARK: - 各模式轨迹

    /// 外圆倒角：刀心在外圆外侧绕整圆，逐层向外扩
    private static func odCham(_ s: PocketSpec) -> [TPSeg] {
        var out: [TPSeg] = []
        let hr = tan(s.odAngle / 2 * .pi / 180)
        let n = max(1, Int(floor(s.odDepth / max(s.odStep, 0.001) + 1e-9)))
        var r = s.odDia / 2 - s.odDepth * hr + s.toolDia / 2     // 顶层(Z0)刀心半径
        out.append(TPSeg(cut: false, z: 0, pts: [CGPoint(x: r, y: 0)], len: 0))
        var z = 0.0
        for k in 1...n {
            let zn = -min(Double(k) * s.odStep, s.odDepth)
            let rn = max(0.001, s.odDia / 2 - (s.odDepth + zn) * hr + s.toolDia / 2)
            out.append(contentsOf: helix(cx: 0, cy: 0, r: r, z0: z, z1: zn, cw: false))
            out.append(TPSeg(cut: true, z: zn, pts: [CGPoint(x: r, y: 0), CGPoint(x: rn, y: 0)],
                             len: abs(rn - r)))
            r = rn; z = zn
        }
        return out
    }

    /// 内圆倒角：逐层整圆，半径一层比一层小
    private static func chamfer(_ s: PocketSpec) -> [TPSeg] {
        var out: [TPSeg] = []
        let hr = tan(s.chaAngle / 2 * .pi / 180)
        let n = max(1, Int(floor(s.chaDepth / max(s.chaStep, 0.001) + 1e-9)))
        var r = max(0.01, s.chaDia / 2 + s.chaDepth * hr - s.toolDia / 2)   // 顶层刀心半径
        out.append(TPSeg(cut: false, z: 0, pts: [CGPoint(x: r, y: 0)], len: 0))
        var z = 0.0
        for k in 1...n {
            let zn = -min(Double(k) * s.chaStep, s.chaDepth)
            let rn = max(0.01, s.chaDia / 2 + (s.chaDepth + zn) * hr - s.toolDia / 2)
            out.append(contentsOf: helix(cx: 0, cy: 0, r: r, z0: z, z1: zn, cw: true))
            out.append(TPSeg(cut: true, z: zn, pts: [CGPoint(x: r, y: 0), CGPoint(x: rn, y: 0)],
                             len: abs(rn - r)))
            r = rn; z = zn
        }
        return out
    }

    private static func pocket(_ s: PocketSpec) -> [TPSeg] {
        var out: [TPSeg] = []
        let a = s.length / 2, b = s.width / 2, r = s.toolDia / 2
        var z = 0.0
        while z > -s.depth - 1e-9 {
            let zz = max(z - s.stepDown, -s.depth)
            out.append(TPSeg(cut: false, z: zz, pts: [CGPoint(x: 0, y: 0), CGPoint(x: a - r, y: 0)], len: a - r))
            var inset = r
            var guardCount = 0
            while inset < min(a, b) - 0.001 && guardCount < 200 {
                let ra = a - inset, rb = b - inset
                let rc = max(0.002, min((s.cornerType == .radius ? s.cornerValue : 0) - inset, min(ra, rb)))
                var pts = [CGPoint(x: ra, y: 0), CGPoint(x: ra, y: rb - rc)]
                pts += arc(cx: ra - rc, cy: rb - rc, r: rc, from: 0, to: 90)
                pts += [CGPoint(x: -(ra - rc), y: rb)]
                pts += arc(cx: -(ra - rc), cy: rb - rc, r: rc, from: 90, to: 180)
                pts += [CGPoint(x: -ra, y: -(rb - rc))]
                pts += arc(cx: -(ra - rc), cy: -(rb - rc), r: rc, from: 180, to: 270)
                pts += [CGPoint(x: ra - rc, y: -rb)]
                pts += arc(cx: ra - rc, cy: -(rb - rc), r: rc, from: 270, to: 360)
                pts.append(CGPoint(x: ra, y: 0))
                out.append(TPSeg(cut: true, z: zz, pts: pts, len: polyLen(pts)))
                inset += s.stepOver
                guardCount += 1
            }
            z = zz == -s.depth ? -s.depth - 1 : z - s.stepDown
            if zz <= -s.depth { break }
        }
        return out
    }

    private static func taper(_ s: PocketSpec) -> [TPSeg] {
        var out: [TPSeg] = []
        let bigR = s.taperDia / 2, r = s.toolDia / 2
        let halfAngle = atan((s.taperDia / 2 - s.taperDiaSmall / 2) / s.taperDepth)
        let tanA = tan(halfAngle)
        let n = max(1, Int(ceil(s.taperDepth / max(s.stepDown, 0.001))))
        var rad = max(0.01, bigR - r)          // 顶层刀心半径
        var z = 0.0
        out.append(TPSeg(cut: false, z: 0, pts: [CGPoint(x: rad, y: 0)], len: 0))
        for k in 1...n {
            let zn = -min(Double(k) * s.stepDown, s.taperDepth)
            let rn = max(0.01, bigR - r + zn * tanA)
            out.append(contentsOf: helix(cx: 0, cy: 0, r: rad, z0: z, z1: zn, cw: false))
            out.append(TPSeg(cut: true, z: zn, pts: [CGPoint(x: rad, y: 0), CGPoint(x: rn, y: 0)],
                             len: abs(rn - rad)))
            rad = rn; z = zn
        }
        return out
    }

    private static func face(_ s: PocketSpec) -> [TPSeg] {
        var out: [TPSeg] = []
        let hl = s.length / 2, hw = s.width / 2
        let row = s.toolDia * 0.75
        var z = 0.0
        while z > -s.depth - 1e-9 {
            let zz = max(z - s.stepDown, -s.depth)
            var dir = 1.0
            var x = -hl
            while x <= hl + 1e-9 {
                let pts = [CGPoint(x: x, y: hw * dir), CGPoint(x: x, y: -hw * dir)]
                out.append(TPSeg(cut: true, z: zz, pts: pts, len: hw * 2))
                dir = -dir
                x += row
            }
            if zz <= -s.depth { break }
            z = zz
        }
        return out
    }

    private static func spiral(_ s: PocketSpec) -> [TPSeg] {
        var out: [TPSeg] = []
        let R = s.spiralDia / 2 - s.toolDia / 2
        let turns = Int(ceil(s.depth / s.stepDown))
        out.append(TPSeg(cut: false, z: 0, pts: [CGPoint(x: -R, y: 0)], len: 0))
        for t in 0..<max(1, turns) {
            let z = -min(s.depth, Double(t + 1) * s.stepDown)
            var pts = [CGPoint(x: -R, y: 0)]
            pts += circlePts(R)
            out.append(TPSeg(cut: true, z: z, pts: pts, len: polyLen(pts)))
        }
        return out
    }

    private static func outer(_ s: PocketSpec) -> [TPSeg] {
        var out: [TPSeg] = []
        let a = s.length / 2 + s.toolDia / 2
        let b = s.width / 2 + s.toolDia / 2
        let lead = s.toolDia / 2 + 2            // 半圆弧进刀半径
        let useR = s.cornerType == .radius
        let rc = useR ? min(s.cornerValue, min(a, b)) + s.toolDia / 2 : 0
        let cc = s.cornerType == .chamfer ? s.cornerValue : 0
        var z0 = 0.0
        while true {
            let zz = max(z0 - s.stepDown, -s.depth)
            z0 = zz
            var pts: [CGPoint] = [CGPoint(x: 0, y: b + lead * 2)]
            pts += arc(cx: 0, cy: b + lead, r: lead, from: 90, to: 270)      // 半圆弧切入
            if useR {
                pts.append(CGPoint(x: a - rc, y: b))
                pts += arc(cx: a - rc, cy: b - rc, r: rc, from: 90, to: 0)
                pts.append(CGPoint(x: a, y: -(b - rc)))
                pts += arc(cx: a - rc, cy: -(b - rc), r: rc, from: 0, to: -90)
                pts.append(CGPoint(x: -(a - rc), y: -b))
                pts += arc(cx: -(a - rc), cy: -(b - rc), r: rc, from: 270, to: 180)
                pts.append(CGPoint(x: -a, y: b - rc))
                pts += arc(cx: -(a - rc), cy: b - rc, r: rc, from: 180, to: 90)
                pts.append(CGPoint(x: -(a - rc), y: b))
            } else {
                pts.append(CGPoint(x: a - cc, y: b))
                pts.append(CGPoint(x: a, y: b - cc))
                pts.append(CGPoint(x: a, y: -(b - cc)))
                pts.append(CGPoint(x: a - cc, y: -b))
                pts.append(CGPoint(x: -(a - cc), y: -b))
                pts.append(CGPoint(x: -a, y: -(b - cc)))
                pts.append(CGPoint(x: -a, y: b - cc))
                pts.append(CGPoint(x: -(a - cc), y: b))
            }
            pts.append(CGPoint(x: 0, y: b))
            pts += arc(cx: 0, cy: b + lead, r: lead, from: 270, to: 450)     // 半圆弧切出
            out.append(TPSeg(cut: true, z: zz, pts: pts, len: polyLen(pts)))
            if zz <= -s.depth { break }
        }
        return out
    }

    private static func key(_ s: PocketSpec) -> [TPSeg] {
        var out: [TPSeg] = []
        let xh = (s.keyLength - s.keyWidth) / 2
        let yh = max(0, s.keyWidth / 2 - s.toolDia / 2)
        var z0 = 0.0
        while true {
            let zz = max(z0 - s.stepDown, -s.depth)
            z0 = zz
            var pts: [CGPoint] = [CGPoint(x: -xh, y: -yh), CGPoint(x: xh, y: -yh)]
            pts += arc(cx: xh, cy: 0, r: yh, from: -90, to: 90)
            pts.append(CGPoint(x: -xh, y: yh))
            pts += arc(cx: -xh, cy: 0, r: yh, from: 90, to: 270)
            out.append(TPSeg(cut: true, z: zz, pts: pts, len: xh * 4 + 2 * Double.pi * yh))
            if zz <= -s.depth { break }
        }
        return out
    }

    // MARK: - 工具

    private static func circlePts(_ r: Double) -> [CGPoint] {
        stride(from: 0, through: 72, by: 1).map { i in
            let a = 2 * Double.pi * Double(i) / 72
            return CGPoint(x: r * cos(a), y: r * sin(a))
        }
    }

    /// 螺旋段：一圈切成若干小段，Z 逐段下降，画出来就是连续螺旋（不再逐层抬刀）
    private static func helix(cx: Double, cy: Double, r: Double, z0: Double, z1: Double,
                             cw: Bool, seg: Int = 72) -> [TPSeg] {
        var out: [TPSeg] = []
        let dir = cw ? -1.0 : 1.0
        var a = 0.0
        for i in 0..<seg {
            let a2 = a + dir * 2 * Double.pi / Double(seg)
            let p0 = CGPoint(x: cx + r * cos(a), y: cy + r * sin(a))
            let p1 = CGPoint(x: cx + r * cos(a2), y: cy + r * sin(a2))
            let z = z0 + (z1 - z0) * Double(i + 1) / Double(seg)
            out.append(TPSeg(cut: true, z: z, pts: [p0, p1], len: hypot(Double(p1.x - p0.x), Double(p1.y - p0.y))))
            a = a2
        }
        return out
    }

    private static func arc(cx: Double, cy: Double, r: Double, from a0: Double, to a1: Double) -> [CGPoint] {
        stride(from: 1, through: 6, by: 1).map { i in
            let a = (a0 + (a1 - a0) * Double(i) / 6) * Double.pi / 180
            return CGPoint(x: cx + r * cos(a), y: cy + r * sin(a))
        }
    }

    private static func polyLen(_ pts: [CGPoint]) -> Double {
        guard pts.count > 1 else { return 0 }
        var l = 0.0
        for i in 1..<pts.count {
            l += hypot(Double(pts[i].x - pts[i - 1].x), Double(pts[i].y - pts[i - 1].y))
        }
        return l
    }
}
