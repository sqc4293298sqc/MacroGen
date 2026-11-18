import Foundation
import CoreGraphics

/// 圆腔 / 圆孔 / 沉头 / 沉孔的 2.5D 整圆清腔。
/// 不是只走一圈刀心圆：从外圈按行距一圈圈缩到中心，每层再下 stepDown。
/// 输出的是程序主体（不含 % / O / M30），由 PartProg.add 统一加抬头和换刀。
enum CircularClear {
    static func code(dia: Double, depth: Double, zTop: Double,
                     toolDia: Double, stepDown: Double, stepOver: Double,
                     feed: Int, spindle: Int, safeZ: Double,
                     hNo: Int, cx: Double, cy: Double, coord: Int) -> String {
        let outer = max(0.01, dia / 2 - toolDia / 2)
        let cut = max(depth, 0.1)
        let ap = max(stepDown, 0.2)
        let ae = max(min(stepOver, toolDia * 0.65), 0.2)
        let plunge = max(50, Int(Double(feed) / 3))
        var L: [String] = []
        L.append("G52 X\(ncf(cx)) Y\(ncf(cy)) (平移到圆心)")
        L.append("G43 H\(hNo) Z\(ncf(safeZ + zTop, 1))")
        L.append("M3 S\(spindle)")
        L.append("M8")
        L.append("#1=\(ncf(dia)) (圆直径)")
        L.append("#2=\(ncf(toolDia)) (刀具直径)")
        L.append("#3=\(ncf(cut)) (总深)")
        L.append("#4=\(ncf(ap)) (每层切深)")
        L.append("#5=\(ncf(ae)) (行距)")
        L.append("#6=\(ncf(zTop)) (工件表面Z)")
        L.append("#7=[#1/2.-#2/2.] (外圈刀心半径)")
        L.append("IF[#7LT0.01]THEN#7=0.01")
        L.append("#8=#6 (当前层Z)")
        L.append("WHILE[#8GT[#6-#3]]DO1")
        L.append("#8=#8-#4")
        L.append("IF[#8LT[#6-#3]]THEN#8=[#6-#3]")
        L.append("#9=#7 (当前圈刀心半径)")
        L.append("G0 Z\(ncf(safeZ + zTop, 1))")
        L.append("G0 X#9 Y0 (回外圈)")
        L.append("G1 Z#8 F\(plunge) (下到本层)")
        L.append("WHILE[#9GE0.01]DO2")
        L.append("G3 I-#9 J0 F\(feed) (整圆清一圈)")
        L.append("G1 X[#9-#5] F\(plunge) (向中心缩一个行距)")
        L.append("#9=#9-#5")
        L.append("END2")
        L.append("END1")
        L.append("G0 Z\(ncf(safeZ + zTop, 1))")
        L.append("G52 X0 Y0")
        L.append("M5")
        L.append("M9")
        L.append("G90")
        L.append("M30")
        return L.joined(separator: "\n")
    }

    /// 给 2D 刀路检查用：与 code 同样的逐层、逐圈缩圆。
    static func segs(dia: Double, depth: Double, zTop: Double,
                     toolDia: Double, stepDown: Double, stepOver: Double) -> [TPSeg] {
        let outer = max(0.01, dia / 2 - toolDia / 2)
        let cut = max(depth, 0.1)
        let ap = max(stepDown, 0.2)
        let ae = max(min(stepOver, toolDia * 0.65), 0.2)
        var out: [TPSeg] = []
        var layerZ = zTop
        let bottom = zTop - cut
        var layers = 0
        while layerZ > bottom + 1e-9 && layers < 200 {
            layerZ = max(bottom, layerZ - ap)
            out.append(TPSeg(cut: false, z: layerZ, pts: [CGPoint(x: 0, y: 0), CGPoint(x: outer, y: 0)], len: outer))
            var r = outer
            var guardCount = 0
            while r >= 0.01 && guardCount < 200 {
                var pts: [CGPoint] = [CGPoint(x: r, y: 0)]
                let n = 48
                for i in 1...n {
                    let a = Double(i) / Double(n) * 2 * Double.pi
                    pts.append(CGPoint(x: r * cos(a), y: r * sin(a)))
                }
                out.append(TPSeg(cut: true, z: layerZ, pts: pts, len: 2 * Double.pi * r))
                r -= ae
                guardCount += 1
            }
            layers += 1
        }
        return out
    }
}
