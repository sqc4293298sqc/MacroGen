import Foundation
import CoreGraphics

enum ToolpathEngine {

    static func totalLen(_ segs: [TPSeg]) -> Double {
        segs.reduce(0) { $0 + $1.len }
    }

    static func build(_ s: PocketSpec) -> [TPSeg] {
        switch s.mode {
        case .taper: return taper(s)
        case .taperHelix: return taperHelix(s)
        case .face: return face(s)
        case .spiral: return spiral(s)
        case .oblique: return oblique(s)
        case .thread: return thread(s)
        case .key: return key(s)
        case .outer: return outer(s)
        case .innerChamfer: return chamfer(s)
        case .odCham: return odCham(s)
        case .rCorner: return rCorner(s)
        case .arcSurface: return arcSurface(s)
        default: return pocket(s)
        }
    }

    // 工件轮廓参考线（闭合）
    static func outline(_ s: PocketSpec) -> [CGPoint] {
        var p: [CGPoint] = []
        switch s.mode {
        case .pocket:            let a = s.length / 2, b = s.width / 2, rc = min(s.cornerValue, min(a, b))
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
        case .taperHelix:
            p += circlePts(s.taperDia / 2)
        case .arcSurface:
            let travel = s.arcTravel
            let yc = s.arcCenterY
            let hw = s.width / 2
            p = [CGPoint(x: -travel, y: yc - hw), CGPoint(x: travel, y: yc - hw),
                 CGPoint(x: travel, y: yc + hw), CGPoint(x: -travel, y: yc + hw),
                 CGPoint(x: -travel, y: yc - hw)]
        case .innerChamfer:
            p += circlePts(s.chaDia / 2 + s.chaDepth * tan(s.chaAngle / 2 * .pi / 180))
        case .face:
            let hl = s.length / 2, hw = s.width / 2
            p = [CGPoint(x: -hl, y: -hw), CGPoint(x: hl, y: -hw),
                 CGPoint(x: hl, y: hw), CGPoint(x: -hl, y: hw), CGPoint(x: -hl, y: -hw)]
        case .spiral:
            if s.holeCount > 1 {
                let n = max(1, s.holeCount)
                let step = s.holeAngleStep == 0 ? 360 / Double(n) : s.holeAngleStep
                for i in 0..<n {
                    let a = (s.holeStartAngle + Double(i) * step) * .pi / 180
                    let cx = s.holePatternRadius * cos(a)
                    let cy = s.holePatternRadius * sin(a)
                    p += circlePts(s.spiralDia / 2, cx: cx, cy: cy)
                }
            } else {
                p += circlePts(s.spiralDia / 2)
            }
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
        case .oblique:
            break
        case .thread:
            break
        case .rCorner:
            switch s.rKind {
            case .outerCylinder:
                p += circlePts(s.rCylinderDia / 2)
            case .hole:
                p += circlePts(s.rHoleDia / 2)
            case .outerRect:
                p = roundedRectPts(hx: s.length / 2, hy: s.width / 2,
                                   rc: min(s.rValue, min(s.length, s.width) / 2))
            case .slot:
                p = roundedRectPts(hx: s.length / 2, hy: s.width / 2,
                                   rc: min(s.rValue, min(s.length, s.width) / 2))
            }
        }
        return p
    }

    /// 多条闭合参考线：多孔螺旋时每个孔单独一条，避免把所有孔连成一根线
    static func outlineLoops(_ s: PocketSpec) -> [[CGPoint]] {
        if s.mode == .spiral && s.holeCount > 1 {
            let n = max(1, s.holeCount)
            let step = s.holeAngleStep == 0 ? 360 / Double(n) : s.holeAngleStep
            return (0..<n).map { i in
                let a = (s.holeStartAngle + Double(i) * step) * .pi / 180
                let cx = s.holePatternRadius * cos(a)
                let cy = s.holePatternRadius * sin(a)
                return circlePts(s.spiralDia / 2, cx: cx, cy: cy)
            }
        }
        let p = outline(s)
        return p.count > 1 ? [p] : []
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

    /// R 角分层：沿 1/4 圆取角度层，每层一整圈/一圈圆角矩形
    private static func rCorner(_ s: PocketSpec) -> [TPSeg] {
        let totalR = s.toolCornerR + s.rValue
        let requested = max(0.5, s.rAngleStep)
        let n = max(1, Int(ceil(90 / requested)))
        let step = 90 / Double(n)
        var out: [TPSeg] = []

        switch s.rKind {
        case .outerCylinder:
            let topR = max(0.001, (s.rCylinderDia + s.toolDia) / 2 - totalR)
            let startR = (s.rCylinderDia + s.toolDia) / 2 + 1
            out.append(TPSeg(cut: false, z: s.zTop, pts: [CGPoint(x: startR, y: 0)], len: 0))
            for i in 0...n {
                let a = min(90, Double(i) * step) * .pi / 180
                let r = topR + sin(a) * totalR
                let z = s.zTop - totalR * (1 - cos(a))
                let pts = circlePts(max(0.001, r))
                out.append(TPSeg(cut: true, z: z, pts: pts, len: polyLen(pts)))
            }
        case .hole:
            let topR = max(0.001, (s.rHoleDia - s.toolDia) / 2 + totalR)
            let startR = max(0.001, (s.rHoleDia - s.toolDia) / 2 - 1)
            out.append(TPSeg(cut: false, z: s.zTop, pts: [CGPoint(x: startR, y: 0)], len: 0))
            for i in 0...n {
                let a = min(90, Double(i) * step) * .pi / 180
                let r = max(0.001, topR - sin(a) * totalR)
                let z = s.zTop - totalR * (1 - cos(a))
                let pts = circlePts(r)
                out.append(TPSeg(cut: true, z: z, pts: pts, len: polyLen(pts)))
            }
        case .outerRect:
            let baseX = (s.length - s.rValue * 2 + s.toolDia - s.toolCornerR * 2) / 2
            let baseY = (s.width - s.rValue * 2 + s.toolDia - s.toolCornerR * 2) / 2
            let baseR = s.toolDia / 2
            out.append(TPSeg(cut: false, z: s.zTop,
                             pts: [CGPoint(x: -(baseX + totalR), y: 0)], len: 0))
            for i in 0...n {
                let a = min(90, Double(i) * step) * .pi / 180
                let k = sin(a) * totalR
                let hx = max(0.001, baseX + k)
                let hy = max(0.001, baseY + k)
                let rc = max(0.001, min(baseR + k, min(hx, hy)))
                let z = s.zTop - totalR * (1 - cos(a))
                let pts = roundedRectPts(hx: hx, hy: hy, rc: rc)
                out.append(TPSeg(cut: true, z: z, pts: pts, len: polyLen(pts)))
            }
        case .slot:
            let centerR = max(0.001, s.rValue - s.toolDia / 2)
            let verticalR = max(0.001, centerR - s.toolCornerR)
            let halfW = (s.width - 2 * centerR - s.toolDia) / 2
            let halfL = (s.length - 2 * centerR - s.toolDia) / 2
            out.append(TPSeg(cut: false, z: s.zTop,
                             pts: [CGPoint(x: max(0.001, halfL), y: 0)], len: 0))
            for i in 0...n {
                let a = min(90, Double(i) * step) * .pi / 180
                let cosA = cos(a), sinA = sin(a)
                let z = s.zTop - s.depth + verticalR - sinA * verticalR
                let outerL = max(0.001, halfL + cosA * verticalR)
                let outerW = max(0.001, halfW + cosA * verticalR)
                let rc = max(0.001, min(cosA * centerR, min(outerL, outerW)))
                let pts = roundedRectPts(hx: outerL, hy: outerW, rc: rc)
                out.append(TPSeg(cut: true, z: z, pts: pts, len: polyLen(pts)))
            }
        }
        return out
    }

    /// 内圆倒角：逐层整圆，半径一层比一层小
    private static func chamfer(_ s: PocketSpec) -> [TPSeg] {        var out: [TPSeg] = []
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

    /// 锥孔螺旋：刀心半径从大头到小头连续缩小，Z 随角度下降
    private static func taperHelix(_ s: PocketSpec) -> [TPSeg] {
        var out: [TPSeg] = []
        let topR = max(0.001, (s.taperDia - s.toolDia) / 2)
        let botR = max(0.001, (s.taperDiaSmall - s.toolDia) / 2)
        let turns = max(1, Int(ceil(s.taperDepth / max(s.stepDown, 0.001))))
        let totalDeg = Double(turns) * 360
        let perDegZ = s.taperDepth / totalDeg
        let shrink = (topR - botR) / totalDeg
        let stepDeg = max(1, Int(ceil(totalDeg / 6000)))
        out.append(TPSeg(cut: false, z: s.zTop, pts: [CGPoint(x: 0, y: 0)], len: 0))
        var pts: [CGPoint] = []
        var zs: [Double] = []
        for i in stride(from: 0, through: Int(totalDeg), by: stepDeg) {
            let d = Double(i)
            let a = d * .pi / 180
            let r = max(0.001, topR - shrink * d)
            pts.append(CGPoint(x: -r * cos(a), y: -r * sin(a)))
            zs.append(s.zTop - perDegZ * d)
        }
        out.append(TPSeg(cut: true, z: s.zTop - s.taperDepth,
                         pts: pts, len: polyLen3D(pts, zs), zs: zs))
        let flat = circlePts(botR)
        out.append(TPSeg(cut: true, z: s.zTop - s.taperDepth,
                         pts: flat, len: polyLen(flat),
                         zs: Array(repeating: s.zTop - s.taperDepth, count: flat.count)))
        return out
    }

    /// 圆弧面：X 往返直线，Y/Z 按 SIN/COS 逐刀变化
    private static func arcSurface(_ s: PocketSpec) -> [TPSeg] {
        var out: [TPSeg] = []
        let inner = s.arcKind == .inner
        let travel = max(0.001, s.arcTravel)
        let sweep = min(90, max(0.001, s.arcSweep))
        let step = max(0.001, s.arcAngleStep)
        let calcR = inner ? s.arcRadius : s.toolCornerR + s.arcRadius
        let passes = Int(ceil(sweep / step))
        out.append(TPSeg(cut: false, z: s.zTop, pts: [CGPoint(x: -travel, y: s.arcCenterY)], len: 0))
        for i in 0...passes {
            let a = min(sweep, Double(i) * step) * .pi / 180
            let y: Double
            let z: Double
            if inner {
                y = s.arcCenterY + s.arcRadius * cos(a)
                z = s.zTop - (s.arcStraightDepth + s.arcRadius * sin(a))
            } else {
                y = s.arcCenterY - calcR * sin(a)
                z = s.zTop - calcR * (1 - cos(a))
            }
            var pts = [CGPoint(x: -travel, y: y), CGPoint(x: travel, y: y)]
            if i % 2 == 1 { pts.reverse() }
            out.append(TPSeg(cut: true, z: z, pts: pts, len: 2 * travel))
        }
        return out
    }

    private static func face(_ s: PocketSpec) -> [TPSeg] {
        var out: [TPSeg] = []
        let hl = s.length / 2, hw = s.width / 2
        let row = s.toolDia * 0.75
        let slope = tan(s.slopeAngle * .pi / 180)
        var z = 0.0
        while z > -s.depth - 1e-9 {
            let zz = max(z - s.stepDown, -s.depth)
            let yShift = slope * (-zz)      // zz 为负，正值向 +Y 下斜
            var dir = 1.0
            var x = -hl
            while x <= hl + 1e-9 {
                let pts = [CGPoint(x: x, y: hw * dir + yShift),
                           CGPoint(x: x, y: -hw * dir + yShift)]
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
        let n = max(1, s.holeCount)
        let patternR = n > 1 ? s.holePatternRadius : 0
        let step = s.holeAngleStep == 0 ? 360 / Double(n) : s.holeAngleStep
        let R = s.spiralDia / 2 - s.toolDia / 2
        let turns = Int(ceil(s.depth / s.stepDown))
        for h in 0..<n {
            let a = (s.holeStartAngle + Double(h) * step) * .pi / 180
            let cx = patternR * cos(a)
            let cy = patternR * sin(a)
            out.append(TPSeg(cut: false, z: 0, pts: [CGPoint(x: cx - R, y: cy)], len: 0))
            for t in 0..<max(1, turns) {
                let z = -min(s.depth, Double(t + 1) * s.stepDown)
                var pts = [CGPoint(x: cx - R, y: cy)]
                pts += circlePts(R, cx: cx, cy: cy)
                out.append(TPSeg(cut: true, z: z, pts: pts, len: polyLen(pts)))
            }
        }
        return out
    }

    /// 非正交螺旋：孔轴在 XY 平面内旋转，沿轴 X 进给，YZ 走圆
    private static func oblique(_ s: PocketSpec) -> [TPSeg] {
        var out: [TPSeg] = []
        let radius = max(0.001, (s.spiralDia - s.toolDia) / 2)
        let turns = max(1, Int(ceil(s.depth / max(s.stepDown, 0.001))))
        let totalDeg = Double(turns) * 360
        let perDeg = s.depth / totalDeg
        let angle = s.obliqueAngle * .pi / 180
        let ca = cos(angle), sa = sin(angle)
        func rot(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: x * ca - y * sa, y: x * sa + y * ca)
        }
        let entry = -max(10, s.spiralDia / 2 + 5)
        out.append(TPSeg(cut: false, z: s.zTop, pts: [rot(entry, 0)], len: 0))

        let stepDeg = max(1, Int(ceil(totalDeg / 6000)))
        var hpts: [CGPoint] = []
        var hzs: [Double] = []
        for i in stride(from: 0, through: Int(totalDeg), by: stepDeg) {
            let d = Double(i)
            let a = d * .pi / 180
            hpts.append(rot(perDeg * d, cos(a) * radius))
            hzs.append(s.zTop - sin(a) * radius)
        }
        out.append(TPSeg(cut: true, z: s.zTop - radius,
                         pts: hpts, len: polyLen3D(hpts, hzs), zs: hzs))

        var fpts: [CGPoint] = []
        var fzs: [Double] = []
        for i in 0...360 {
            let a = Double(i) * .pi / 180
            fpts.append(rot(s.depth, cos(a) * radius))
            fzs.append(s.zTop - sin(a) * radius)
        }
        out.append(TPSeg(cut: true, z: s.zTop - radius,
                         pts: fpts, len: polyLen3D(fpts, fzs), zs: fzs))
        return out
    }

    /// 圆周分布螺纹：每个孔按径向分层，每层走一整圆螺纹螺旋
    private static func thread(_ s: PocketSpec) -> [TPSeg] {
        var out: [TPSeg] = []
        let n = max(1, s.holeCount)
        let patternR = n > 1 ? s.holePatternRadius : 0
        let angleStep = s.holeAngleStep == 0 ? 360 / Double(n) : s.holeAngleStep
        let centerR = max(0.001, (s.threadDia - s.toolDia) / 2)
        let radialStep = max(0.1, s.threadRadialStep)
        let radialStart = max(0.1, centerR - 2 * radialStep)
        let radialEnd = max(radialStart, centerR)
        let bottom = s.threadTop - s.threadLength
        let top = s.threadTop
        var r = radialStart
        while r <= radialEnd + 1e-9 {
            for h in 0..<n {
                let a = (s.holeStartAngle + Double(h) * angleStep) * .pi / 180
                let cx = patternR * cos(a)
                let cy = patternR * sin(a)
                out.append(TPSeg(cut: false, z: s.zTop,
                                 pts: [CGPoint(x: cx + r, y: cy)], len: 0))
                let pts = circlePts(r, cx: cx, cy: cy)
                var zs: [Double] = []
                for i in 0..<pts.count {
                    let t = pts.count > 1 ? Double(i) / Double(pts.count - 1) : 0
                    zs.append(bottom + (top - bottom) * t)
                }
                out.append(TPSeg(cut: true, z: bottom,
                                 pts: pts, len: polyLen3D(pts, zs), zs: zs))
            }
            r += radialStep
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
        let rowStep = max(0.5, s.toolDia * 0.75)
        var z0 = 0.0
        while true {
            let zz = max(z0 - s.stepDown, -s.depth)
            z0 = zz
            var pts: [CGPoint] = []
            var row = yh
            while row > 0.001 {
                pts.append(CGPoint(x: -xh, y: -row))
                pts.append(CGPoint(x: xh, y: -row))
                pts += arc(cx: xh, cy: 0, r: row, from: -90, to: 90)
                pts.append(CGPoint(x: -xh, y: row))
                pts += arc(cx: -xh, cy: 0, r: row, from: 90, to: 270)
                row -= rowStep
            }
            pts.append(CGPoint(x: -xh, y: 0))
            pts.append(CGPoint(x: xh, y: 0))
            pts.append(CGPoint(x: -xh, y: 0))
            out.append(TPSeg(cut: true, z: zz, pts: pts, len: polyLen(pts)))
            if zz <= -s.depth { break }
        }
        return out
    }

    // MARK: - 工具

    private static func circlePts(_ r: Double, cx: Double = 0, cy: Double = 0) -> [CGPoint] {
        stride(from: 0, through: 72, by: 1).map { i in
            let a = 2 * Double.pi * Double(i) / 72
            return CGPoint(x: cx + r * cos(a), y: cy + r * sin(a))
        }
    }

    private static func roundedRectPts(hx: Double, hy: Double, rc: Double) -> [CGPoint] {
        let r = max(0.001, min(rc, min(hx, hy)))
        var pts: [CGPoint] = [CGPoint(x: -hx, y: hy - r)]
        pts += arc(cx: -hx + r, cy: hy - r, r: r, from: 180, to: 90)
        pts.append(CGPoint(x: hx - r, y: hy))
        pts += arc(cx: hx - r, cy: hy - r, r: r, from: 90, to: 0)
        pts.append(CGPoint(x: hx, y: -hy + r))
        pts += arc(cx: hx - r, cy: -hy + r, r: r, from: 0, to: -90)
        pts.append(CGPoint(x: -hx + r, y: -hy))
        pts += arc(cx: -hx + r, cy: -hy + r, r: r, from: 270, to: 180)
        pts.append(CGPoint(x: -hx, y: hy - r))
        return pts
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

    private static func polyLen3D(_ pts: [CGPoint], _ zs: [Double]) -> Double {
        guard pts.count > 1, pts.count == zs.count else { return 0 }
        var l = 0.0
        for i in 1..<pts.count {
            let dxy = hypot(Double(pts[i].x - pts[i - 1].x), Double(pts[i].y - pts[i - 1].y))
            let dz = zs[i] - zs[i - 1]
            l += sqrt(dxy * dxy + dz * dz)
        }
        return l
    }
}
