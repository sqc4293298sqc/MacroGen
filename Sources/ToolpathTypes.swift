import Foundation
import CoreGraphics

/// 一段刀路：cut 切削 / 快移，z 该段深度，pts 折线点（XY，单位 mm）
struct TPSeg {
    var cut: Bool
    var z: Double
    var pts: [CGPoint]
    var len: Double
}
