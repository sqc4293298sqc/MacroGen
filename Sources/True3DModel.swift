import Foundation
import OCCTSwift

enum True3DEdgeMode: String, CaseIterable, Identifiable {
    case none = "无"
    case fillet = "圆角"
    case chamfer = "倒角"

    var id: String { rawValue }
}

struct True3DParams: Equatable {
    var width: Double = 120
    var depth: Double = 80
    var height: Double = 10

    var edgeMode: True3DEdgeMode = .fillet
    var edgeSize: Double = 4

    var holeEnabled: Bool = true
    var holeDiameter: Double = 24
    var holeX: Double = 0
    var holeY: Double = 0

    var bossEnabled: Bool = true
    var bossDiameter: Double = 24
    var bossHeight: Double = 6
    var bossX: Double = 35
    var bossY: Double = 20

    var pocketEnabled: Bool = true
    var pocketWidth: Double = 24
    var pocketDepthXY: Double = 18
    var pocketZ: Double = 5
    var pocketX: Double = -42
    var pocketY: Double = -28
}

struct True3DStats {
    var volume: Double
    var faces: Int
    var edges: Int
    var triangles: Int
    var valid: Bool
}

struct True3DFeature: Identifiable {
    let id = UUID()
    let name: String
    let detail: String
    let ok: Bool
}

struct True3DResult {
    let shape: Shape
    let mesh: Mesh
    let stats: True3DStats
    let features: [True3DFeature]
    let params: True3DParams
}

enum True3DModelError: LocalizedError {
    case baseFailed
    case edgeFailed(String)
    case holeFailed
    case bossFailed
    case pocketFailed
    case invalid
    case invalidParameter(String)
    case meshFailed

    var errorDescription: String? {
        switch self {
        case .baseFailed: return "基础块创建失败，请检查长宽高"
        case .edgeFailed(let detail): return detail
        case .holeFailed: return "通孔布尔失败"
        case .bossFailed: return "凸台布尔失败"
        case .pocketFailed: return "方腔布尔失败"
        case .invalid: return "OCCT 生成了实体，但 BRepCheck 判定无效"
        case .invalidParameter(let detail): return detail
        case .meshFailed: return "实体三角化失败"
        }
    }
}

enum True3DKernel {
    static func build(_ input: True3DParams) throws -> True3DResult {
        try validate(input)
        let w = input.width
        let d = input.depth
        let h = input.height

        guard let base = Shape.box(
            origin: SIMD3<Double>(-w / 2, -d / 2, 0),
            width: w,
            height: d,
            depth: h
        ) else {
            throw True3DModelError.baseFailed
        }

        var features: [True3DFeature] = [
            True3DFeature(name: "基础块", detail: "\(fmt(w))×\(fmt(d))×\(fmt(h))", ok: true)
        ]

        let body: Shape
        switch input.edgeMode {
        case .none:
            body = base
        case .fillet:
            guard let rounded = base.filleted(radius: input.edgeSize) else {
                throw True3DModelError.edgeFailed("R\(fmt(input.edgeSize)) 圆角失败：半径可能超过实体允许范围")
            }
            features.append(True3DFeature(name: "圆角", detail: "R\(fmt(input.edgeSize))", ok: true))
            body = rounded
        case .chamfer:
            guard let bevel = base.chamfered(distance: input.edgeSize) else {
                throw True3DModelError.edgeFailed("C\(fmt(input.edgeSize)) 倒角失败：距离可能超过实体允许范围")
            }
            features.append(True3DFeature(name: "倒角", detail: "C\(fmt(input.edgeSize))", ok: true))
            body = bevel
        }

        var current = body

        if input.holeEnabled {
            guard let hole = Shape.cylinder(
                at: SIMD2<Double>(input.holeX, input.holeY),
                bottomZ: -1,
                radius: input.holeDiameter / 2,
                height: h + 2
            ) else {
                throw True3DModelError.holeFailed
            }
            guard let cut = current - hole else {
                throw True3DModelError.holeFailed
            }
            current = cut
            features.append(True3DFeature(name: "通孔", detail: "Ø\(fmt(input.holeDiameter)) 贯通", ok: true))
        }

        if input.bossEnabled {
            guard let boss = Shape.cylinder(
                at: SIMD2<Double>(input.bossX, input.bossY),
                bottomZ: h,
                radius: input.bossDiameter / 2,
                height: input.bossHeight
            ) else {
                throw True3DModelError.bossFailed
            }
            guard let fused = current + boss else {
                throw True3DModelError.bossFailed
            }
            current = fused
            features.append(True3DFeature(
                name: "凸台",
                detail: "Ø\(fmt(input.bossDiameter)) H\(fmt(input.bossHeight)) @ (\(fmt(input.bossX)), \(fmt(input.bossY)))",
                ok: true
            ))
        }

        if input.pocketEnabled {
            let depth = input.pocketZ
            guard let pocket = Shape.box(
                origin: SIMD3<Double>(
                    input.pocketX - input.pocketWidth / 2,
                    input.pocketY - input.pocketDepthXY / 2,
                    h - depth
                ),
                width: input.pocketWidth,
                height: input.pocketDepthXY,
                depth: depth + 1
            ) else {
                throw True3DModelError.pocketFailed
            }
            guard let cut = current - pocket else {
                throw True3DModelError.pocketFailed
            }
            current = cut
            features.append(True3DFeature(
                name: "方腔",
                detail: "\(fmt(input.pocketWidth))×\(fmt(input.pocketDepthXY)) 深\(fmt(depth))",
                ok: true
            ))
        }

        guard current.isValid else {
            throw True3DModelError.invalid
        }
        guard let mesh = current.mesh(linearDeflection: 0.18, angularDeflection: 0.35) else {
            throw True3DModelError.meshFailed
        }

        return True3DResult(
            shape: current,
            mesh: mesh,
            stats: True3DStats(
                volume: current.volume ?? 0,
                faces: current.faceCount,
                edges: current.edgeCount,
                triangles: mesh.triangleCount,
                valid: current.isValid
            ),
            features: features,
            params: input
        )
    }

    private static func validate(_ p: True3DParams) throws {
        let finite = [p.width, p.depth, p.height, p.edgeSize, p.holeDiameter,
                      p.holeX, p.holeY, p.bossDiameter, p.bossHeight,
                      p.bossX, p.bossY, p.pocketWidth, p.pocketDepthXY,
                      p.pocketZ, p.pocketX, p.pocketY]
        guard finite.allSatisfy({ $0.isFinite }) else {
            throw True3DModelError.invalidParameter("参数里包含非有限数值，请检查输入")
        }
        guard p.width > 0.5, p.depth > 0.5, p.height > 0.5 else {
            throw True3DModelError.invalidParameter("基础块长、宽、高必须大于 0.5 mm")
        }
        if p.edgeMode != .none {
            let maxEdge = min(p.width, p.depth, p.height) / 2
            guard p.edgeSize > 0.05, p.edgeSize < maxEdge - 0.001 else {
                throw True3DModelError.invalidParameter("R/C 必须大于 0.05，且小于最小边的一半（当前上限 \(fmt(maxEdge)) mm）")
            }
        }
        if p.holeEnabled {
            let r = p.holeDiameter / 2
            guard p.holeDiameter > 0.1 else {
                throw True3DModelError.invalidParameter("通孔直径必须大于 0.1 mm")
            }
            guard abs(p.holeX) + r <= p.width / 2 - 0.05,
                  abs(p.holeY) + r <= p.depth / 2 - 0.05 else {
                throw True3DModelError.invalidParameter("通孔超出基础块范围，请把孔中心往内移或减小孔径")
            }
        }
        if p.bossEnabled {
            let r = p.bossDiameter / 2
            let inset = (p.edgeMode != .none ? p.edgeSize : 0)
            guard p.bossDiameter > 0.1, p.bossHeight > 0.1 else {
                throw True3DModelError.invalidParameter("凸台直径和高度必须大于 0.1 mm")
            }
            guard abs(p.bossX) + r <= p.width / 2 - inset - 0.02,
                  abs(p.bossY) + r <= p.depth / 2 - inset - 0.02 else {
                throw True3DModelError.invalidParameter("凸台必须完整落在基础块顶面，不能悬出边缘")
            }
            if p.holeEnabled, hypot(p.bossX - p.holeX, p.bossY - p.holeY) < r + p.holeDiameter / 2 + 0.05 {
                throw True3DModelError.invalidParameter("凸台与通孔重叠，请移动凸台或改孔径")
            }
        }
        if p.pocketEnabled {
            guard p.pocketWidth > 0.1, p.pocketDepthXY > 0.1,
                  p.pocketZ > 0.05, p.pocketZ <= p.height else {
                throw True3DModelError.invalidParameter("方腔长宽必须大于 0.1 mm，深度必须在 0.05～基础块高度之间（等于高度为通腔）")
            }
            let minX = p.pocketX - p.pocketWidth / 2
            let maxX = p.pocketX + p.pocketWidth / 2
            let minY = p.pocketY - p.pocketDepthXY / 2
            let maxY = p.pocketY + p.pocketDepthXY / 2
            guard minX >= -p.width / 2 + 0.02, maxX <= p.width / 2 - 0.02,
                  minY >= -p.depth / 2 + 0.02, maxY <= p.depth / 2 - 0.02 else {
                throw True3DModelError.invalidParameter("方腔必须完整落在基础块内，不能切出边缘")
            }
            if p.holeEnabled, rectCircleOverlap(minX: minX, maxX: maxX, minY: minY, maxY: maxY,
                                                 cx: p.holeX, cy: p.holeY, r: p.holeDiameter / 2) {
                throw True3DModelError.invalidParameter("方腔与通孔重叠，请移动方腔或改孔径")
            }
            if p.bossEnabled, rectCircleOverlap(minX: minX, maxX: maxX, minY: minY, maxY: maxY,
                                                 cx: p.bossX, cy: p.bossY, r: p.bossDiameter / 2) {
                throw True3DModelError.invalidParameter("方腔与凸台重叠，请移动方腔或凸台")
            }
        }
    }

    private static func rectCircleOverlap(minX: Double, maxX: Double, minY: Double, maxY: Double,
                                          cx: Double, cy: Double, r: Double) -> Bool {
        let x = min(max(cx, minX), maxX)
        let y = min(max(cy, minY), maxY)
        return hypot(cx - x, cy - y) < r + 0.05
    }

    private static func fmt(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.0001 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }
}
