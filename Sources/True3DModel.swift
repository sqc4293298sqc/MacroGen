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
}

enum True3DModelError: LocalizedError {
    case baseFailed
    case edgeFailed(String)
    case holeFailed
    case bossFailed
    case pocketFailed
    case invalid
    case meshFailed

    var errorDescription: String? {
        switch self {
        case .baseFailed: return "基础块创建失败，请检查长宽高"
        case .edgeFailed(let detail): return detail
        case .holeFailed: return "通孔布尔失败"
        case .bossFailed: return "凸台布尔失败"
        case .pocketFailed: return "方腔布尔失败"
        case .invalid: return "OCCT 生成了实体，但 BRepCheck 判定无效"
        case .meshFailed: return "实体三角化失败"
        }
    }
}

enum True3DKernel {
    static func build(_ input: True3DParams) throws -> True3DResult {
        let w = max(input.width, 1)
        let d = max(input.depth, 1)
        let h = max(input.height, 1)

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
            guard let rounded = base.filleted(radius: max(input.edgeSize, 0.1)) else {
                throw True3DModelError.edgeFailed("R\(fmt(input.edgeSize)) 圆角失败：半径可能超过实体允许范围")
            }
            features.append(True3DFeature(name: "圆角", detail: "R\(fmt(input.edgeSize))", ok: true))
            body = rounded
        case .chamfer:
            guard let bevel = base.chamfered(distance: max(input.edgeSize, 0.1)) else {
                throw True3DModelError.edgeFailed("C\(fmt(input.edgeSize)) 倒角失败：距离可能超过实体允许范围")
            }
            features.append(True3DFeature(name: "倒角", detail: "C\(fmt(input.edgeSize))", ok: true))
            body = bevel
        }

        var current = body

        if input.holeEnabled {
            guard let hole = Shape.cylinder(
                at: SIMD2<Double>(0, 0),
                bottomZ: -1,
                radius: max(input.holeDiameter, 0.2) / 2,
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
                radius: max(input.bossDiameter, 0.2) / 2,
                height: max(input.bossHeight, 0.2)
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
            let depth = min(max(input.pocketZ, 0.2), h)
            guard let pocket = Shape.box(
                origin: SIMD3<Double>(
                    input.pocketX - max(input.pocketWidth, 0.2) / 2,
                    input.pocketY - max(input.pocketDepthXY, 0.2) / 2,
                    h - depth
                ),
                width: max(input.pocketWidth, 0.2),
                height: max(input.pocketDepthXY, 0.2),
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
            features: features
        )
    }

    private static func fmt(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.0001 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }
}
