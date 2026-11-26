import Foundation
import CoreGraphics

/// 一段刀路：cut 切削 / 快移，z 该段深度，pts 折线点（XY，单位 mm）
/// zs 可选：非正交螺旋这类点的 Z 逐点变化时用；为空就全部用 z。
struct TPSeg {
    var cut: Bool
    var z: Double
    var pts: [CGPoint]
    var len: Double
    var zs: [Double]?

    init(cut: Bool, z: Double, pts: [CGPoint], len: Double, zs: [Double]? = nil) {
        self.cut = cut
        self.z = z
        self.pts = pts
        self.len = len
        self.zs = zs
    }

    func z(at index: Int) -> Double {
        guard let zs = zs, index >= 0, index < zs.count else { return z }
        return zs[index]
    }
}
