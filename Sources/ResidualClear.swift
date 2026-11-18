import Foundation
import CoreGraphics

/// 2D 残料差集：用当前大刀的 2D 刀路扫掠面积，扣掉方腔区域，
/// 算出还剩多少面积没被大刀切到。只用于判断是否需要二次开粗。
/// 不是 3D 实体布尔，也不是万能的复杂轮廓布尔。
enum ResidualClear {
    static func rectPocketHasResidual(_ p: PartSpec, _ f: PartFeat) -> Bool {
        guard f.kind == .rectPocket, f.w > 0, f.h > 0, p.pocketDia > 0 else { return true }
        var s = PocketSpec()
        s.mode = .pocket
        s.length = f.w
        s.width = f.h
        s.cornerType = .square
        s.cornerValue = 0
        s.depth = max(f.depth, 0.1)
        s.stepDown = max(p.stepDown, 0.1)
        s.stepOver = max(p.stepOver, 0.1)
        s.toolDia = p.pocketDia
        s.spindle = p.spindle
        s.feed = p.feed
        s.safeZ = p.safeZ
        s.hNo = p.pocketTool
        s.coord = p.coord
        s.cx = 0
        s.cy = 0
        let segs = ToolpathEngine.build(s).filter { $0.cut }

        let cell = max(0.5, min(p.restDia / 2.5, max(f.w, f.h) / 48))
        let cols = max(3, Int(ceil(f.w / cell)))
        let rows = max(3, Int(ceil(f.h / cell)))
        let cellX = f.w / Double(cols)
        let cellY = f.h / Double(rows)
        let r = p.pocketDia / 2
        var swept = Array(repeating: false, count: cols * rows)

        func markDisk(_ x: Double, _ y: Double) {
            let ix0 = max(0, Int(floor((x - r) / cellX)))
            let ix1 = min(cols - 1, Int(ceil((x + r) / cellX)))
            let iy0 = max(0, Int(floor((y - r) / cellY)))
            let iy1 = min(rows - 1, Int(ceil((y + r) / cellY)))
            guard ix0 <= ix1, iy0 <= iy1 else { return }
            for iy in iy0...iy1 {
                let cy = (Double(iy) + 0.5) * cellY - f.h / 2
                for ix in ix0...ix1 {
                    let cx = (Double(ix) + 0.5) * cellX - f.w / 2
                    if hypot(cx - x, cy - y) <= r + max(cellX, cellY) {
                        swept[iy * cols + ix] = true
                    }
                }
            }
        }

        for seg in segs {
            guard !seg.pts.isEmpty else { continue }
            for i in 1..<seg.pts.count {
                let a = seg.pts[i - 1], b = seg.pts[i]
                let length = hypot(b.x - a.x, b.y - a.y)
                let steps = max(1, Int(ceil(Double(length) / max(0.5, cell / 2))))
                for k in 0...steps {
                    let t = CGFloat(k) / CGFloat(steps)
                    markDisk(Double(a.x + (b.x - a.x) * t), Double(a.y + (b.y - a.y) * t))
                }
            }
        }

        var unswept = 0
        for iy in 0..<rows {
            for ix in 0..<cols {
                if !swept[iy * cols + ix] { unswept += 1 }
            }
        }
        return Double(unswept) * cellX * cellY > max(2, cellX * cellY * 1.5)
    }
}
