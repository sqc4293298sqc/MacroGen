import Foundation
import OCCTSwift

enum True3DEdgeMode: String, CaseIterable, Identifiable, Codable {
    case none = "无"
    case fillet = "圆角"
    case chamfer = "倒角"
    var id: String { rawValue }
}

enum True3DBaseShape: String, CaseIterable, Identifiable, Codable {
    case box = "矩形"
    case circle = "圆形"
    case profile = "轮廓"
    var id: String { rawValue }
}

struct True3DPoint: Codable, Equatable, Hashable {
    var x: Double
    var y: Double
}

enum True3DHoleKind: String, CaseIterable, Identifiable, Codable {
    case through = "通孔"
    case blind = "盲孔"
    case counterbore = "沉头孔"
    case countersink = "沉孔"
    case thread = "螺纹底孔"
    var id: String { rawValue }
}

enum True3DFeatureKind: String, CaseIterable, Identifiable, Codable {
    case hole = "孔"
    case boss = "凸台"
    case circularPocket = "圆腔"
    case rectPocket = "方腔"
    case slot = "腰形槽"
    case profileBoss = "草图凸台"
    case profileCut = "草图切除"
    var id: String { rawValue }
}

struct True3DFeatureSpec: Identifiable, Equatable, Codable {
    var id = UUID()
    var name = ""
    var kind: True3DFeatureKind = .hole
    var suppressed = false
    var x: Double = 0
    var y: Double = 0
    var dia: Double = 10
    var width: Double = 30
    var depthY: Double = 20
    var depth: Double = 5
    var bossHeight: Double = 6
    var holeKind: True3DHoleKind = .through
    var holeDepth: Double = 10
    var cbDia: Double? = nil
    var cbDepth: Double? = nil
    var csDia: Double? = nil
    var csAngle: Double? = nil
    var topZ: Double? = nil
    var cornerRadius: Double = 0
    /// 草图拉伸特征的闭合轮廓，坐标是基础块坐标系（mm）。
    var profile: [True3DPoint] = []

    init(kind: True3DFeatureKind = .hole, x: Double = 0, y: Double = 0) {
        self.kind = kind
        self.x = x
        self.y = y
        switch kind {
        case .hole:
            name = "通孔"; dia = 10; holeKind = .through; holeDepth = 10
        case .boss:
            name = "凸台"; dia = 20; bossHeight = 6
        case .circularPocket:
            name = "圆腔"; dia = 24; depth = 5
        case .rectPocket:
            name = "方腔"; width = 24; depthY = 18; depth = 5; cornerRadius = 0
        case .slot:
            name = "腰形槽"; width = 40; depthY = 12; depth = 5
        case .profileBoss:
            name = "草图凸台"; bossHeight = 5
        case .profileCut:
            name = "草图切除"; depth = 5
        }
    }

    var detail: String {
        let p = "(" + fmt(x) + ", " + fmt(y) + ")"
        switch kind {
        case .hole:
            switch holeKind {
            case .through: return "Ø\(fmt(dia)) 通孔 @ \(p)"
            case .blind: return "Ø\(fmt(dia)) 盲孔 深\(fmt(holeDepth)) @ \(p)"
            case .counterbore: return "Ø\(fmt(dia)) 通孔 + 沉头 Ø\(fmt(cbDia ?? dia + 2)) 深\(fmt(cbDepth ?? 2)) @ \(p)"
            case .countersink: return "Ø\(fmt(dia)) 通孔 + 沉孔 Ø\(fmt(csDia ?? dia + 2)) \(fmt(csAngle ?? 90))° @ \(p)"
            case .thread: return "螺纹底孔 Ø\(fmt(dia)) 深\(fmt(holeDepth)) @ \(p)"
            }
        case .boss:
            return "Ø\(fmt(dia)) H\(fmt(bossHeight)) @ \(p)"
        case .circularPocket:
            return "Ø\(fmt(dia)) 深\(fmt(depth)) @ \(p)"
        case .rectPocket:
            return "\(fmt(width))×\(fmt(depthY)) 深\(fmt(depth)) R\(fmt(cornerRadius)) @ \(p)"
        case .slot:
            return "\(fmt(width))×\(fmt(depthY)) 深\(fmt(depth)) @ \(p)"
        case .profileBoss:
            return "\(profile.count) 点轮廓 H\(fmt(bossHeight))"
        case .profileCut:
            return "\(profile.count) 点轮廓 深\(fmt(depth))"
        }
    }
}

private func makeDefaultTrue3DFeatures() -> [True3DFeatureSpec] {
    var hole = True3DFeatureSpec(kind: .hole, x: 0, y: 0)
    hole.name = "通孔"; hole.dia = 24; hole.holeKind = .through
    var boss = True3DFeatureSpec(kind: .boss, x: 35, y: 20)
    boss.name = "凸台"; boss.dia = 24; boss.bossHeight = 6
    var pocket = True3DFeatureSpec(kind: .rectPocket, x: -42, y: -28)
    pocket.name = "方腔"; pocket.width = 24; pocket.depthY = 18; pocket.depth = 5
    return [hole, boss, pocket]
}

struct True3DParams: Equatable, Codable {
    var projectName: String = "未命名工程"
    var width: Double = 120
    var depth: Double = 80
    var height: Double = 10
    var baseShape: True3DBaseShape = .box
    var profile: [True3DPoint] = []
    var edgeMode: True3DEdgeMode = .fillet
    var edgeSize: Double = 4
    var features: [True3DFeatureSpec] = makeDefaultTrue3DFeatures()

    static var defaultFeatures: [True3DFeatureSpec] { makeDefaultTrue3DFeatures() }

    var activeFeatures: [True3DFeatureSpec] { features.filter { !$0.suppressed } }
    var bossFeatures: [True3DFeatureSpec] { activeFeatures.filter { $0.kind == .boss || $0.kind == .profileBoss } }
    var pocketFeatures: [True3DFeatureSpec] { activeFeatures.filter { $0.kind == .circularPocket || $0.kind == .rectPocket || $0.kind == .slot || $0.kind == .profileCut } }
    var holeFeatures: [True3DFeatureSpec] { activeFeatures.filter { $0.kind == .hole } }

    func bossTop(_ f: True3DFeatureSpec) -> Double { (f.topZ ?? height) + max(f.bossHeight, 0) }
    func pocketBottom(_ f: True3DFeatureSpec) -> Double { (f.topZ ?? height) - max(f.depth, 0) }
}

struct True3DStats {
    var volume: Double
    var faces: Int
    var edges: Int
    var triangles: Int
    var valid: Bool
    var sizeX: Double
    var sizeY: Double
    var sizeZ: Double
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
    case featureFailed(String)
    case invalid
    case invalidParameter(String)
    case meshFailed

    var errorDescription: String? {
        switch self {
        case .baseFailed: return "基础形状创建失败，请检查尺寸或轮廓"
        case .edgeFailed(let detail): return detail
        case .featureFailed(let detail): return detail
        case .invalid: return "OCCT 生成了实体，但 BRepCheck 判定无效"
        case .invalidParameter(let detail): return detail
        case .meshFailed: return "实体三角化失败"
        }
    }
}

enum True3DKernel {
    static func build(_ input: True3DParams) throws -> True3DResult {
        try validate(input)
        let h = input.height
        let base = try makeBase(input)
        var features: [True3DFeature] = [
            True3DFeature(name: "基础块", detail: baseDetail(input), ok: true)
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
        for feature in input.features {
            if feature.suppressed {
                features.append(True3DFeature(name: feature.name, detail: "已抑制 · " + feature.detail, ok: false))
                continue
            }
            do {
                current = try apply(feature, to: current, baseHeight: h)
                features.append(True3DFeature(name: feature.name, detail: feature.detail, ok: true))
            } catch let error as True3DModelError {
                throw error
            } catch {
                throw True3DModelError.featureFailed("\(feature.name) 生成失败：\(error.localizedDescription)")
            }
        }

        guard current.isValid else { throw True3DModelError.invalid }
        guard let mesh = current.mesh(linearDeflection: 0.18, angularDeflection: 0.35) else {
            throw True3DModelError.meshFailed
        }
        let size: (Double, Double, Double)
        if let b = current.bounds {
            size = (b.max.x - b.min.x, b.max.y - b.min.y, b.max.z - b.min.z)
        } else {
            size = (input.width, input.depth, input.height)
        }
        return True3DResult(
            shape: current,
            mesh: mesh,
            stats: True3DStats(
                volume: current.volume ?? 0,
                faces: current.faceCount,
                edges: current.edgeCount,
                triangles: mesh.triangleCount,
                valid: current.isValid,
                sizeX: size.0,
                sizeY: size.1,
                sizeZ: size.2
            ),
            features: features,
            params: input
        )
    }

    private static func makeBase(_ p: True3DParams) throws -> Shape {
        switch p.baseShape {
        case .box:
            guard let base = Shape.box(
                origin: SIMD3<Double>(-p.width / 2, -p.depth / 2, 0),
                width: p.width,
                height: p.depth,
                depth: p.height
            ) else { throw True3DModelError.baseFailed }
            return base
        case .circle:
            let d = min(p.width, p.depth)
            guard let base = Shape.cylinder(
                at: SIMD2<Double>(0, 0),
                bottomZ: 0,
                radius: d / 2,
                height: p.height
            ) else { throw True3DModelError.baseFailed }
            return base
        case .profile:
            let pts = p.profile.map { SIMD2<Double>($0.x, $0.y) }
            guard pts.count >= 3, let wire = Wire.polygon(pts, closed: true),
                  let base = Shape.extrude(profile: wire, direction: SIMD3<Double>(0, 0, 1), length: p.height) else {
                throw True3DModelError.baseFailed
            }
            return base
        }
    }

    private static func apply(_ f: True3DFeatureSpec, to current: Shape, baseHeight h: Double) throws -> Shape {
        switch f.kind {
        case .hole:
            guard let tool = holeTool(f, baseHeight: h), let cut = current - tool else {
                throw True3DModelError.featureFailed("\(f.name) 布尔切除失败")
            }
            return cut
        case .boss:
            guard let boss = Shape.cylinder(
                at: SIMD2<Double>(f.x, f.y),
                bottomZ: f.topZ ?? h,
                radius: f.dia / 2,
                height: f.bossHeight
            ), let fused = current + boss else {
                throw True3DModelError.featureFailed("\(f.name) 布尔合并失败")
            }
            return fused
        case .circularPocket:
            guard let tool = circularPocketTool(f, baseHeight: h), let cut = current - tool else {
                throw True3DModelError.featureFailed("\(f.name) 布尔切除失败")
            }
            return cut
        case .rectPocket:
            guard let tool = rectPocketTool(f, baseHeight: h), let cut = current - tool else {
                throw True3DModelError.featureFailed("\(f.name) 布尔切除失败")
            }
            return cut
        case .slot:
            guard let tool = slotTool(f, baseHeight: h), let cut = current - tool else {
                throw True3DModelError.featureFailed("\(f.name) 布尔切除失败")
            }
            return cut
        case .profileBoss:
            guard let tool = profileTool(f, baseHeight: h, isBoss: true), let fused = current + tool else {
                throw True3DModelError.featureFailed("\(f.name) 草图拉伸合并失败，轮廓可能不自交或不在实体上")
            }
            return fused
        case .profileCut:
            guard let tool = profileTool(f, baseHeight: h, isBoss: false), let cut = current - tool else {
                throw True3DModelError.featureFailed("\(f.name) 草图切除失败，轮廓可能不自交或切不到实体")
            }
            return cut
        }
    }

    private static func holeTool(_ f: True3DFeatureSpec, baseHeight h: Double) -> Shape? {
        let top = f.topZ ?? h
        let r = f.dia / 2
        switch f.holeKind {
        case .through:
            return Shape.cylinder(at: SIMD2<Double>(f.x, f.y), bottomZ: -1, radius: r, height: top + 2)
        case .blind, .thread:
            let d = min(max(f.holeDepth, 0.1), max(top + 1, 0.2))
            return Shape.cylinder(at: SIMD2<Double>(f.x, f.y), bottomZ: top - d, radius: r, height: d + 1)
        case .counterbore:
            guard let main = Shape.cylinder(at: SIMD2<Double>(f.x, f.y), bottomZ: -1, radius: r, height: top + 2),
                  let cb = Shape.cylinder(at: SIMD2<Double>(f.x, f.y), bottomZ: top - max(f.cbDepth ?? 2, 0.1), radius: max(f.cbDia ?? r * 2 * 1.8, r + 0.2) / 2, height: max(f.cbDepth ?? 2, 0.1) + 1),
                  let combined = main + cb else { return nil }
            return combined
        case .countersink:
            let rTop = max(f.csDia ?? f.dia * 1.6, f.dia + 0.2) / 2
            let angle = min(max(f.csAngle ?? 90, 20), 160)
            let coneDepth = (rTop - r) / max(tan(angle * .pi / 360), 0.01)
            guard coneDepth > 0.05,
                  let main = Shape.cylinder(at: SIMD2<Double>(f.x, f.y), bottomZ: -1, radius: r, height: top + 2),
                  let cone = Shape.cone(at: SIMD3<Double>(f.x, f.y, top - coneDepth), direction: SIMD3<Double>(0, 0, 1), bottomRadius: r, topRadius: rTop, height: coneDepth),
                  let combined = main + cone else { return nil }
            return combined
        }
    }

    private static func circularPocketTool(_ f: True3DFeatureSpec, baseHeight h: Double) -> Shape? {
        let top = f.topZ ?? h
        let depth = min(max(f.depth, 0.1), h)
        return Shape.cylinder(at: SIMD2<Double>(f.x, f.y), bottomZ: top - depth, radius: f.dia / 2, height: depth + 1)
    }

    private static func rectPocketTool(_ f: True3DFeatureSpec, baseHeight h: Double) -> Shape? {
        let top = f.topZ ?? h
        let depth = min(max(f.depth, 0.1), h)
        let rr = min(max(f.cornerRadius, 0), min(f.width, f.depthY) / 2 - 0.01)
        if rr > 0.01,
           let wire = Wire.rectangle(width: f.width, height: f.depthY)?.filletedAll2D(radius: rr),
           let prism = Shape.extrude(profile: wire, direction: SIMD3<Double>(0, 0, 1), length: depth + 1) {
            return prism.translated(by: SIMD3<Double>(f.x, f.y, top - depth))
        }
        return Shape.box(
            origin: SIMD3<Double>(f.x - f.width / 2, f.y - f.depthY / 2, top - depth),
            width: f.width,
            height: f.depthY,
            depth: depth + 1
        )
    }

    private static func slotTool(_ f: True3DFeatureSpec, baseHeight h: Double) -> Shape? {
        let top = f.topZ ?? h
        let depth = min(max(f.depth, 0.1), h)
        let w = max(f.depthY, 0.2)
        let r = w / 2
        let straight = max(f.width - w, 0)
        var parts: [Shape] = []
        if straight > 0.01 {
            if let box = Shape.box(
                origin: SIMD3<Double>(f.x - straight / 2, f.y - w / 2, top - depth),
                width: straight,
                height: w,
                depth: depth + 1
            ) { parts.append(box) }
        }
        for x in [f.x - straight / 2, f.x + straight / 2] {
            if let c = Shape.cylinder(at: SIMD2<Double>(x, f.y), bottomZ: top - depth, radius: r, height: depth + 1) {
                parts.append(c)
            }
        }
        guard var result = parts.first else { return nil }
        for p in parts.dropFirst() {
            guard let u = result + p else { return nil }
            result = u
        }
        return result
    }

    private static func profileTool(_ f: True3DFeatureSpec, baseHeight h: Double, isBoss: Bool) -> Shape? {
        guard f.profile.count >= 3 else { return nil }
        let pts = f.profile.map { SIMD2<Double>($0.x, $0.y) }
        guard let wire = Wire.polygon(pts, closed: true) else { return nil }
        let top = f.topZ ?? h
        let length: Double
        let z: Double
        if isBoss {
            length = max(f.bossHeight, 0.1)
            z = top
        } else {
            length = max(f.depth, 0.1) + 1
            z = top - max(f.depth, 0.1)
        }
        guard let prism = Shape.extrude(profile: wire, direction: SIMD3<Double>(0, 0, 1), length: length) else {
            return nil
        }
        return prism.translated(by: SIMD3<Double>(0, 0, z))
    }

    private static func baseDetail(_ p: True3DParams) -> String {
        switch p.baseShape {
        case .box: return "\(fmt(p.width))×\(fmt(p.depth))×\(fmt(p.height))"
        case .circle: return "Ø\(fmt(min(p.width, p.depth)))×\(fmt(p.height))"
        case .profile: return "\(p.profile.count) 点轮廓 ×\(fmt(p.height))"
        }
    }

    private static func validate(_ p: True3DParams) throws {
        let finite = [p.width, p.depth, p.height, p.edgeSize]
        guard finite.allSatisfy({ $0.isFinite }), p.width > 0.5, p.depth > 0.5, p.height > 0.5 else {
            throw True3DModelError.invalidParameter("基础块长、宽、高必须大于 0.5 mm")
        }
        if p.baseShape == .profile {
            guard p.profile.count >= 3,
                  p.profile.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
                throw True3DModelError.invalidParameter("轮廓至少需要 3 个有效点")
            }
        }
        if p.edgeMode != .none {
            let maxEdge = min(p.width, p.depth, p.height) / 2
            guard p.edgeSize > 0.05, p.edgeSize < maxEdge - 0.001 else {
                throw True3DModelError.invalidParameter("R/C 必须大于 0.05，且小于最小边的一半（当前上限 \(fmt(maxEdge)) mm）")
            }
        }
        let edgeInset = (p.edgeMode != .none ? p.edgeSize : 0)
        for f in p.features {
            let vals = [f.x, f.y, f.dia, f.width, f.depthY, f.depth, f.bossHeight, f.holeDepth, f.cornerRadius]
            guard vals.allSatisfy({ $0.isFinite }) else {
                throw True3DModelError.invalidParameter("\(f.name) 参数里有非有限数值")
            }
            if let topZ = f.topZ, !topZ.isFinite {
                throw True3DModelError.invalidParameter("\(f.name) 的顶面 Z 无效")
            }
            switch f.kind {
            case .hole:
                let r = f.dia / 2
                guard f.dia > 0.1 else { throw True3DModelError.invalidParameter("\(f.name) 直径必须大于 0.1 mm") }
                guard abs(f.x) + r <= p.width / 2 - 0.05, abs(f.y) + r <= p.depth / 2 - 0.05 else {
                    throw True3DModelError.invalidParameter("\(f.name) 超出基础块范围")
                }
                if f.holeKind == .blind || f.holeKind == .thread {
                    guard f.holeDepth > 0.05 else { throw True3DModelError.invalidParameter("\(f.name) 深度必须大于 0.05 mm") }
                }
                if f.holeKind == .counterbore {
                    guard (f.cbDia ?? f.dia + 2) > f.dia, (f.cbDepth ?? 2) > 0.05 else {
                        throw True3DModelError.invalidParameter("\(f.name) 沉头尺寸不合理")
                    }
                }
                if f.holeKind == .countersink {
                    guard (f.csDia ?? f.dia + 2) > f.dia else { throw True3DModelError.invalidParameter("\(f.name) 沉孔直径必须大于底孔") }
                }
            case .boss:
                let r = f.dia / 2
                guard f.dia > 0.1, f.bossHeight > 0.1 else { throw True3DModelError.invalidParameter("\(f.name) 直径和高度必须大于 0.1 mm") }
                guard abs(f.x) + r <= p.width / 2 - edgeInset - 0.02,
                      abs(f.y) + r <= p.depth / 2 - edgeInset - 0.02 else {
                    throw True3DModelError.invalidParameter("\(f.name) 必须完整落在基础块顶面，不能悬出边缘")
                }
            case .circularPocket:
                guard f.dia > 0.1, f.depth > 0.05, f.depth <= p.height else {
                    throw True3DModelError.invalidParameter("\(f.name) 直径和深度不合理")
                }
                guard abs(f.x) + f.dia / 2 <= p.width / 2 - 0.02,
                      abs(f.y) + f.dia / 2 <= p.depth / 2 - 0.02 else {
                    throw True3DModelError.invalidParameter("\(f.name) 超出基础块范围")
                }
            case .rectPocket:
                guard f.width > 0.1, f.depthY > 0.1, f.depth > 0.05, f.depth <= p.height else {
                    throw True3DModelError.invalidParameter("\(f.name) 长宽和深度不合理")
                }
                guard abs(f.x) + f.width / 2 <= p.width / 2 - 0.02,
                      abs(f.y) + f.depthY / 2 <= p.depth / 2 - 0.02 else {
                    throw True3DModelError.invalidParameter("\(f.name) 超出基础块范围")
                }
                guard f.cornerRadius >= 0, f.cornerRadius < min(f.width, f.depthY) / 2 else {
                    throw True3DModelError.invalidParameter("\(f.name) 圆角半径过大")
                }
            case .slot:
                guard f.width >= f.depthY, f.depthY > 0.1, f.depth > 0.05, f.depth <= p.height else {
                    throw True3DModelError.invalidParameter("\(f.name) 尺寸不合理，长度必须不小于槽宽")
                }
                guard abs(f.x) + f.width / 2 <= p.width / 2 - 0.02,
                      abs(f.y) + f.depthY / 2 <= p.depth / 2 - 0.02 else {
                    throw True3DModelError.invalidParameter("\(f.name) 超出基础块范围")
                }
            case .profileBoss, .profileCut:
                guard f.profile.count >= 3,
                      f.profile.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
                    throw True3DModelError.invalidParameter("\(f.name) 草图轮廓至少需要 3 个有效点")
                }
                let xs = f.profile.map(\.x), ys = f.profile.map(\.y)
                guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else {
                    throw True3DModelError.invalidParameter("\(f.name) 草图轮廓无效")
                }
                guard maxX - minX > 0.1, maxY - minY > 0.1 else {
                    throw True3DModelError.invalidParameter("\(f.name) 草图轮廓太小")
                }
                guard minX >= -p.width / 2 + 0.02, maxX <= p.width / 2 - 0.02,
                      minY >= -p.depth / 2 + 0.02, maxY <= p.depth / 2 - 0.02 else {
                    throw True3DModelError.invalidParameter("\(f.name) 草图轮廓超出基础块范围")
                }
                if f.kind == .profileBoss {
                    guard f.bossHeight > 0.05 else { throw True3DModelError.invalidParameter("\(f.name) 拉伸高度必须大于 0.05 mm") }
                } else {
                    guard f.depth > 0.05, f.depth <= p.height else { throw True3DModelError.invalidParameter("\(f.name) 切除深度不合理") }
                }
            }
        }
        for i in p.features.indices where !p.features[i].suppressed {
            for j in p.features.indices where j > i && !p.features[j].suppressed {
                let a = p.features[i], b = p.features[j]
                if a.kind == .hole, b.kind == .hole {
                    if hypot(a.x - b.x, a.y - b.y) < (a.dia + b.dia) / 2 + 0.05 {
                        throw True3DModelError.invalidParameter("\(a.name) 与 \(b.name) 重叠")
                    }
                }
            }
        }
    }

}

private func fmt(_ value: Double) -> String {
    if abs(value.rounded() - value) < 0.0001 { return String(format: "%.0f", value) }
    return String(format: "%.1f", value)
}
