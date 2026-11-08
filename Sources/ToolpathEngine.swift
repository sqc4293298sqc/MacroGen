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
        case .face:
            let hl = s.length / 2, hw = s.width / 2
            p = [CGPoint(x: -hl, y: -hw), CGPoint(x: hl, y: -hw),
                 CGPoint(x: hl, y: hw), CGPoint(x: -hl, y: hw), CGPoint(x: -hl, y: -hw)]
        case .spiral:
            p += circlePts(s.spiralDia / 2)
        case .key:
            let R = s.toolDia / 2
            let xc = s.keyLength / 2 - R
            let yh = s.keyWidth / 2
            p = [CGPoint(x: -xc, y: -yh), CGPoint(x: xc, y: -yh)]
            p += arc(cx: xc, cy: 0, r: yh, from: -90, to: 90)
            p += [CGPoint(x: xc, y: yh), CGPoint(x: -xc, y: yh)]
            p += arc(cx: -xc, cy: 0, r: yh, from: 90, to: 270)
            p.append(CGPoint(x: -xc, y: -yh))
        }
        return p
    }

    // MARK: - 各模式轨迹

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
                let rc = max(0.002, min(s.cornerValue - inset, min(ra, rb)))
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
        var z = 0.0
        while z < s.taperDepth - 1e-9 {
            let zz = min(z + s.stepDown, s.taperDepth)
            let rad = max(0.01, bigR - r - zz * tanA)
            var pts = [CGPoint(x: rad, y: 0)]
            pts += circlePts(rad)
            out.append(TPSeg(cut: true, z: -zz, pts: pts, len: polyLen(pts)))
            z = zz
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

    private static func key(_ s: PocketSpec) -> [TPSeg] {
        var out: [TPSeg] = []
        let xh = s.keyLength / 2 - s.toolDia / 2
        let yh = s.keyWidth / 2 - s.toolDia / 2
        let row = s.toolDia * 0.7
        var y = -yh
        while true {
            let yy = min(y, yh)
            var z = 0.0
            while z > -s.depth - 1e-9 {
                let zz = max(z - s.stepDown, -s.depth)
                let pts = [CGPoint(x: -xh, y: yy), CGPoint(x: xh, y: yy), CGPoint(x: -xh, y: yy)]
                out.append(TPSeg(cut: true, z: zz, pts: pts, len: xh * 4))
                if zz <= -s.depth { break }
                z = zz
            }
            if yy >= yh { break }
            y += row
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
