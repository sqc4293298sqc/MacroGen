import Foundation
import OCCTSwift
import simd

// MARK: - Model source

/// 3D 工作台的模型来源。
///
/// 参数化模型继续走 `True3DParams`；导入的 STEP 作为只读 B-Rep 源，
/// 后续的圆角/倒角等操作记录在 `True3DHistoryOperation` 里，不写回
/// `True3DParams`，避免把导入实体硬塞进参数化特征链。
enum True3DModelSource {
    case parametric(True3DParams)
    case importedStep(True3DImportedPart)

    var displayName: String {
        switch self {
        case .parametric(let params):
            return params.projectName.isEmpty ? "未命名工程" : params.projectName
        case .importedStep(let part):
            return part.name
        }
    }

    var parametricParams: True3DParams? {
        if case .parametric(let params) = self { return params }
        return nil
    }
}

// MARK: - Imported part

/// 从 STEP 导入的零件。`shape`/`mesh` 只保留在内存里，持久化时
/// 只保存文件路径、bookmark 和操作历史。
struct True3DImportedPart: Identifiable, @unchecked Sendable {
    let id: UUID
    var name: String
    var localURL: URL?
    var bookmarkData: Data?
    var unitInMeters: Double
    var shape: Shape
    var mesh: Mesh
    var stats: True3DStats
    var importedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        localURL: URL? = nil,
        bookmarkData: Data? = nil,
        unitInMeters: Double = 0.001,
        shape: Shape,
        mesh: Mesh
    ) {
        self.id = id
        self.name = name
        self.localURL = localURL
        self.bookmarkData = bookmarkData
        self.unitInMeters = unitInMeters
        self.shape = shape
        self.mesh = mesh
        self.stats = True3DStats.measure(shape: shape, mesh: mesh)
        self.importedAt = Date()
    }
}

// MARK: - Edge reference

/// 选择器返回的是当前形状里的边索引；重建后索引可能变化。
/// R1 先保存“索引 + 几何指纹”，重建时优先按索引匹配，匹配不上再按
/// 中点/长度找最近边。R2 再换成 BRepGraph + TopologyRef 的 recipe。
struct True3DEdgeRef: Codable, Equatable, Hashable, Sendable {
    var edgeIndex: Int
    var midpoint: True3DPoint3
    var length: Double
    var adjacentFaceIndices: [Int] = []

    static func make(edge: Edge, in shape: Shape) -> True3DEdgeRef {
        let points = edge.points(count: 9)
        let midpoint: True3DPoint3
        if points.isEmpty {
            midpoint = True3DPoint3(x: 0, y: 0, z: 0)
        } else {
            let sum = points.reduce(SIMD3<Double>(0, 0, 0)) { $0 + $1 }
            midpoint = True3DPoint3(
                x: sum.x / Double(points.count),
                y: sum.y / Double(points.count),
                z: sum.z / Double(points.count)
            )
        }
        var faceIndices: [Int] = []
        if let faces = edge.adjacentFaces(in: shape) {
            faceIndices.append(faces.0.index)
            if let second = faces.1 {
                faceIndices.append(second.index)
            }
        }
        return True3DEdgeRef(
            edgeIndex: edge.index,
            midpoint: midpoint,
            length: edge.length,
            adjacentFaceIndices: faceIndices
        )
    }
}

struct True3DPoint3: Codable, Equatable, Hashable, Sendable {
    var x: Double
    var y: Double
    var z: Double

    var simd: SIMD3<Double> { SIMD3(x, y, z) }
}

// MARK: - History operation

struct True3DHistoryOperation: Identifiable, Codable, Equatable, Sendable {
    enum Kind: Codable, Equatable, Sendable {
        case fillet(edge: True3DEdgeRef, radius: Double)
        case chamfer(edge: True3DEdgeRef, distance: Double)
        case translate(dx: Double, dy: Double, dz: Double, copy: Bool)
        case multiFillet(edges: [True3DEdgeRef], radius: Double)
        case multiChamfer(edges: [True3DEdgeRef], distance: Double)
        case variableFillet(edge: True3DEdgeRef, radius1: Double, radius2: Double)
        case moveFace(points: [True3DPoint3D], normal: True3DPoint3D, distance: Double)
        case rotate(axis: String, angle: Double, copy: Bool)
        case merge
        case booleanCut(base: Int, tool: Int)
        case booleanCommon(base: Int, tool: Int)
        case bodyArray(rows: Int, cols: Int, pitchX: Double, pitchY: Double)
        case bodyMirror(axis: String)
    }

    var id: UUID
    var kind: Kind
    var suppressed: Bool

    init(id: UUID = UUID(), kind: Kind, suppressed: Bool = false) {
        self.id = id
        self.kind = kind
        self.suppressed = suppressed
    }

    var name: String {
        switch kind {
        case .fillet: return "圆角"
        case .chamfer: return "倒角"
        case .translate(_, _, _, let copy): return copy ? "移动拷贝" : "移动体"
        case .multiFillet(let edges, _): return "多边圆角 \(edges.count) 条"
        case .multiChamfer(let edges, _): return "多边倒角 \(edges.count) 条"
        case .variableFillet: return "变半径圆角"
        case .moveFace: return "移动面"
        case .rotate(_, _, let copy): return copy ? "旋转拷贝" : "旋转体"
        case .merge: return "合并"
        case .booleanCut(let base, let tool): return "实体\(base + 1) − 实体\(tool + 1)"
        case .booleanCommon(let base, let tool): return "实体\(base + 1) ∩ 实体\(tool + 1)"
        case .bodyArray(let rows, let cols, let px, let py):
            return "\(rows)×\(cols) · ΔX\(fmt(px)) ΔY\(fmt(py))"
        case .bodyMirror(let axis): return "沿\(axis.uppercased())=0 镜像"
        }
    }

    var detail: String {
        switch kind {
        case .fillet(_, let radius):
            return "R\(fmt(radius))"
        case .chamfer(_, let distance):
            return "C\(fmt(distance))"
        case .translate(let dx, let dy, let dz, _):
            return "ΔX\(fmt(dx)) ΔY\(fmt(dy)) ΔZ\(fmt(dz))"
        case .multiFillet(let edges, let radius):
            return "\(edges.count) 条 · R\(fmt(radius))"
        case .multiChamfer(let edges, let distance):
            return "\(edges.count) 条 · C\(fmt(distance))"
        case .variableFillet(_, let r1, let r2):
            return "R\(fmt(r1))→R\(fmt(r2))"
        case .moveFace(_, _, let distance):
            return distance >= 0 ? "沿法向 +\(fmt(distance))" : "沿法向 \(fmt(distance))"
        case .rotate(let axis, let angle, _):
            return "绕\(axis)轴 \(fmt(angle))°"
        case .merge:
            return "合并独立实体"
        case .booleanCut(let base, let tool):
            return "实体\(base + 1) − 实体\(tool + 1)"
        case .booleanCommon(let base, let tool):
            return "实体\(base + 1) ∩ 实体\(tool + 1)"
        case .bodyArray(let rows, let cols, let px, let py):
            return "\(rows)×\(cols) · ΔX\(fmt(px)) ΔY\(fmt(py))"
        case .bodyMirror(let axis):
            return "沿\(axis.uppercased())=0 镜像"
        }
    }

    private func fmt(_ value: Double) -> String {
        String(format: "%.2f", value).replacingOccurrences(of: ".00", with: "")
    }
}

// MARK: - Tree node

struct True3DTreeNode: Identifiable, Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case root
        case feature
        case fillet
        case chamfer
    }

    enum Status: Equatable, Sendable {
        case ok
        case failed(String)
        case suppressed
    }

    var id: UUID
    var kind: Kind
    var name: String
    var detail: String
    var suppressed: Bool
    var status: Status
    var operationID: UUID?
}

// MARK: - Document

/// 一次 3D 建模会话的完整输入：模型源 + 操作历史。
///
/// `build()` 是同步内核入口，真正的 UI 调用走 `True3DKernelService`，
/// 用串行 actor 把 OCCT 计算移出主线程。
struct True3DModelDocument: Identifiable, @unchecked Sendable {
    let id: UUID
    var name: String
    var source: True3DModelSource
    var operations: [True3DHistoryOperation]
    var selectedNodeID: UUID?

    init(
        id: UUID = UUID(),
        params: True3DParams,
        operations: [True3DHistoryOperation] = [],
        selectedNodeID: UUID? = nil
    ) {
        self.id = id
        self.name = params.projectName.isEmpty ? "未命名工程" : params.projectName
        self.source = .parametric(params)
        self.operations = operations
        self.selectedNodeID = selectedNodeID
    }

    init(
        id: UUID = UUID(),
        imported part: True3DImportedPart,
        operations: [True3DHistoryOperation] = [],
        selectedNodeID: UUID? = nil
    ) {
        self.id = id
        self.name = part.name
        self.source = .importedStep(part)
        self.operations = operations
        self.selectedNodeID = selectedNodeID
    }

    var parametricParams: True3DParams? {
        source.parametricParams
    }

    mutating func append(_ operation: True3DHistoryOperation) {
        operations.append(operation)
        selectedNodeID = operation.id
    }

    /// 同步重建。调用方负责把它放到串行内核队列；UI 不要直接在主线程调用。
    func build() throws -> True3DResult {
        let base = try buildBase()
        var current = base.shape
        var features = base.features
        var nodes = makeBaseNodes(features: base.features, params: base.params)

        for operation in operations {
            if operation.suppressed {
                features.append(
                    True3DFeature(name: operation.name, detail: "已抑制 · " + operation.detail, ok: false)
                )
                nodes.append(
                    True3DTreeNode(
                        id: operation.id,
                        kind: nodeKind(for: operation),
                        name: operation.name,
                        detail: operation.detail,
                        suppressed: true,
                        status: .suppressed,
                        operationID: operation.id
                    )
                )
                continue
            }

            do {
                current = try apply(operation, to: current)
                features.append(True3DFeature(name: operation.name, detail: operation.detail, ok: true))
                nodes.append(
                    True3DTreeNode(
                        id: operation.id,
                        kind: nodeKind(for: operation),
                        name: operation.name,
                        detail: operation.detail,
                        suppressed: false,
                        status: .ok,
                        operationID: operation.id
                    )
                )
            } catch let error as True3DModelError {
                throw error
            } catch {
                throw True3DModelError.featureFailed(
                    "\(operation.name) 生成失败：\(error.localizedDescription)"
                )
            }
        }

        guard current.isValid else { throw True3DModelError.invalid }

        let mesh: Mesh
        let hasActiveOperations = operations.contains { !$0.suppressed }
        if !hasActiveOperations {
            mesh = base.mesh
        } else {
            guard let rebuiltMesh = current.mesh(linearDeflection: 0.18, angularDeflection: 0.35) else {
                throw True3DModelError.meshFailed
            }
            mesh = rebuiltMesh
        }

        return True3DResult(
            shape: current,
            mesh: mesh,
            stats: True3DStats.measure(shape: current, mesh: mesh, fallback: base.params),
            features: features,
            params: base.params,
            documentID: id,
            nodes: nodes
        )
    }

    private func buildBase() throws -> True3DResult {
        switch source {
        case .parametric(let params):
            return try True3DKernel.build(params)
        case .importedStep(let part):
            let root = True3DFeature(name: "导入的 STEP", detail: part.name, ok: true)
            return True3DResult(
                shape: part.shape,
                mesh: part.mesh,
                stats: part.stats,
                features: [root],
                params: True3DParams(),
                documentID: id,
                nodes: [
                    True3DTreeNode(
                        id: id,
                        kind: .root,
                        name: "导入的 STEP",
                        detail: part.name,
                        suppressed: false,
                        status: .ok,
                        operationID: nil
                    )
                ]
            )
        }
    }

    private func makeBaseNodes(features: [True3DFeature], params: True3DParams) -> [True3DTreeNode] {
        guard !features.isEmpty else {
            return [
                True3DTreeNode(
                    id: id,
                    kind: .root,
                    name: source.displayName,
                    detail: "基础体",
                    suppressed: false,
                    status: .ok,
                    operationID: nil
                )
            ]
        }

        var nodes: [True3DTreeNode] = [
            True3DTreeNode(
                id: id,
                kind: .root,
                name: features[0].name,
                detail: features[0].detail,
                suppressed: false,
                status: features[0].ok ? .ok : .failed(features[0].detail),
                operationID: nil
            )
        ]

        for (index, feature) in features.dropFirst().enumerated() {
            let syntheticCount = params.edgeMode == .none ? 0 : 1
            let specIndex = index - syntheticCount
            let featureID: UUID
            if specIndex >= 0, specIndex < params.features.count {
                featureID = params.features[specIndex].id
            } else {
                featureID = UUID()
            }
            nodes.append(
                True3DTreeNode(
                    id: featureID,
                    kind: .feature,
                    name: feature.name,
                    detail: feature.detail,
                    suppressed: false,
                    status: feature.ok ? .ok : .failed(feature.detail),
                    operationID: nil
                )
            )
        }
        return nodes
    }

    private func nodeKind(for operation: True3DHistoryOperation) -> True3DTreeNode.Kind {
        switch operation.kind {
        case .fillet: return .fillet
        case .chamfer: return .chamfer
        case .translate: return .feature
        case .multiFillet: return .fillet
        case .multiChamfer: return .chamfer
        case .variableFillet: return .fillet
        case .moveFace: return .feature
        case .rotate: return .feature
        case .merge: return .feature
        case .booleanCut: return .feature
        case .booleanCommon: return .feature
        case .bodyArray: return .feature
        case .bodyMirror: return .feature
        }
    }

    private func apply(_ operation: True3DHistoryOperation, to shape: Shape) throws -> Shape {
        switch operation.kind {
        case .fillet(let edgeRef, let radius):
            guard radius > 0 else {
                throw True3DModelError.invalidParameter("圆角半径必须大于 0")
            }
            guard let edge = resolve(edgeRef, in: shape) else {
                throw True3DModelError.edgeFailed("找不到要圆角的边，可能已被上一步修改")
            }
            guard let builder = FilletBuilder(shape: shape) else {
                throw True3DModelError.edgeFailed("无法创建圆角构建器")
            }
            guard builder.addEdge(edge, radius: radius), builder.contour(for: edge) > 0 else {
                throw True3DModelError.edgeFailed("这条边不能加 R\(fmt(radius)) 圆角")
            }
            guard builder.faultyContourCount == 0, builder.faultyVertexCount == 0,
                  let result = builder.build(), result.isValid else {
                throw True3DModelError.edgeFailed(
                    "R\(fmt(radius)) 圆角失败：半径可能超过实体允许范围"
                )
            }
            return result

        case .chamfer(let edgeRef, let distance):
            guard distance > 0 else {
                throw True3DModelError.invalidParameter("倒角距离必须大于 0")
            }
            guard let edge = resolve(edgeRef, in: shape) else {
                throw True3DModelError.edgeFailed("找不到要倒角的边，可能已被上一步修改")
            }
            guard let builder = ChamferBuilder(shape: shape) else {
                throw True3DModelError.edgeFailed("无法创建倒角构建器")
            }
            guard builder.addEdge(edge, distance: distance), builder.contour(for: edge) > 0 else {
                throw True3DModelError.edgeFailed("这条边不能加 C\(fmt(distance)) 倒角")
            }
            guard let result = builder.build(), result.isValid else {
                throw True3DModelError.edgeFailed(
                    "C\(fmt(distance)) 倒角失败：距离可能超过实体允许范围"
                )
            }
            return result

        case .rotate(let axis, let angle, let copy):
            guard abs(angle) > 1e-6 else {
                throw True3DModelError.invalidParameter("旋转角度不能为 0")
            }
            let axisVector: SIMD3<Double>
            switch axis.uppercased() {
            case "X": axisVector = SIMD3<Double>(1, 0, 0)
            case "Y": axisVector = SIMD3<Double>(0, 1, 0)
            case "Z": axisVector = SIMD3<Double>(0, 0, 1)
            default:
                throw True3DModelError.invalidParameter("旋转轴必须是 X/Y/Z")
            }
            guard let bounds = shape.bounds else {
                throw True3DModelError.featureFailed("旋转体：无法取得实体包围盒")
            }
            let center = SIMD3<Double>(
                (bounds.min.x + bounds.max.x) / 2,
                (bounds.min.y + bounds.max.y) / 2,
                (bounds.min.z + bounds.max.z) / 2
            )
            guard let local = shape.translated(by: SIMD3<Double>(-center.x, -center.y, -center.z)),
                  let rotated = local.rotated(axis: axisVector, angle: angle * Double.pi / 180),
                  let placed = rotated.translated(by: center) else {
                throw True3DModelError.featureFailed("旋转体失败")
            }
            if copy {
                guard let combined = shape + placed else {
                    throw True3DModelError.featureFailed("旋转拷贝布尔合并失败")
                }
                return combined
            }
            return placed

        case .merge:
            let solids = shape.solids
            guard !solids.isEmpty else {
                throw True3DModelError.invalidParameter("当前模型没有可合并的实体")
            }
            guard solids.count > 1 else { return shape }
            // 和 Android 保持一致：只做 fuseAll，不再 unified/simplified。
            // unified 会把接缝附近的同域面合并，在楔形/斜接处看起来像多出一个倒角。
            guard let fused = Shape.fuseAll(solids), fused.isValid else {
                throw True3DModelError.featureFailed("合并失败：实体可能没有接触或存在无效面")
            }
            return fused

        case .moveFace(let points, let normal, let distance):
            guard points.count >= 3 else {
                throw True3DModelError.invalidParameter("移动面缺少面轮廓")
            }
            guard abs(distance) > 1e-6 else {
                throw True3DModelError.invalidParameter("移动面距离不能为 0")
            }
            let nx = normal.x, ny = normal.y, nz = normal.z
            let nl = (nx * nx + ny * ny + nz * nz).squareRoot()
            guard nl > 1e-9 else {
                throw True3DModelError.invalidParameter("所选面没有有效法向")
            }
            let unit = SIMD3<Double>(nx / nl, ny / nl, nz / nl)
            let eps = min(0.05, max(0.01, abs(distance) * 0.05))
            let dir: SIMD3<Double>
            let startPoints: [SIMD3<Double>]
            let length: Double
            if distance > 0 {
                dir = unit
                length = distance + eps
                startPoints = points.map {
                    SIMD3<Double>($0.x - unit.x * eps, $0.y - unit.y * eps, $0.z - unit.z * eps)
                }
            } else {
                dir = SIMD3<Double>(-unit.x, -unit.y, -unit.z)
                length = abs(distance) + eps
                startPoints = points.map {
                    SIMD3<Double>($0.x + unit.x * eps, $0.y + unit.y * eps, $0.z + unit.z * eps)
                }
            }
            guard let wire = Wire.polygon3D(startPoints, closed: true),
                  let tool = Shape.extrude(profile: wire, direction: dir, length: length) else {
                throw True3DModelError.featureFailed("移动面：无法从面轮廓生成拉伸体")
            }
            if distance > 0 {
                guard let fused = shape + tool else {
                    throw True3DModelError.featureFailed("移动面：邻面延伸合并失败")
                }
                return fused
            }
            guard let cut = shape - tool else {
                throw True3DModelError.featureFailed("移动面：向内移动切除失败")
            }
            return cut

        case .variableFillet(let edgeRef, let radius1, let radius2):
            guard radius1 > 0, radius2 > 0 else {
                throw True3DModelError.invalidParameter("变半径圆角两端半径必须大于 0")
            }
            guard let edge = resolve(edgeRef, in: shape) else {
                throw True3DModelError.edgeFailed("找不到要圆角的边，可能已被上一步修改")
            }
            guard let builder = FilletBuilder(shape: shape) else {
                throw True3DModelError.edgeFailed("无法创建圆角构建器")
            }
            guard builder.addEdge(edge, radius1: radius1, radius2: radius2),
                  builder.contour(for: edge) > 0 else {
                throw True3DModelError.edgeFailed(
                    "这条边不能加变半径 R\(fmt(radius1))→R\(fmt(radius2))"
                )
            }
            guard builder.faultyContourCount == 0, builder.faultyVertexCount == 0,
                  let result = builder.build(), result.isValid else {
                throw True3DModelError.edgeFailed(
                    "变半径圆角失败：半径可能超过实体允许范围"
                )
            }
            return result

        case .multiFillet(let edges, let radius):
            guard radius > 0 else {
                throw True3DModelError.invalidParameter("圆角半径必须大于 0")
            }
            guard !edges.isEmpty else {
                throw True3DModelError.edgeFailed("没有要圆角的边")
            }
            guard let builder = FilletBuilder(shape: shape) else {
                throw True3DModelError.edgeFailed("无法创建圆角构建器")
            }
            for ref in edges {
                guard let edge = resolve(ref, in: shape) else {
                    throw True3DModelError.edgeFailed("找不到要圆角的边，可能已被上一步修改")
                }
                guard builder.addEdge(edge, radius: radius), builder.contour(for: edge) > 0 else {
                    throw True3DModelError.edgeFailed("边 #\(edge.index) 不能加 R\(fmt(radius)) 圆角")
                }
            }
            guard builder.faultyContourCount == 0, builder.faultyVertexCount == 0,
                  let result = builder.build(), result.isValid else {
                throw True3DModelError.edgeFailed(
                    "R\(fmt(radius)) 多边圆角失败：半径可能超过实体允许范围"
                )
            }
            return result

        case .multiChamfer(let edges, let distance):
            guard distance > 0 else {
                throw True3DModelError.invalidParameter("倒角距离必须大于 0")
            }
            guard !edges.isEmpty else {
                throw True3DModelError.edgeFailed("没有要倒角的边")
            }
            guard let builder = ChamferBuilder(shape: shape) else {
                throw True3DModelError.edgeFailed("无法创建倒角构建器")
            }
            for ref in edges {
                guard let edge = resolve(ref, in: shape) else {
                    throw True3DModelError.edgeFailed("找不到要倒角的边，可能已被上一步修改")
                }
                guard builder.addEdge(edge, distance: distance), builder.contour(for: edge) > 0 else {
                    throw True3DModelError.edgeFailed("边 #\(edge.index) 不能加 C\(fmt(distance)) 倒角")
                }
            }
            guard let result = builder.build(), result.isValid else {
                throw True3DModelError.edgeFailed(
                    "C\(fmt(distance)) 多边倒角失败：距离可能超过实体允许范围"
                )
            }
            return result

        case .translate(let dx, let dy, let dz, let copy):
            guard abs(dx) + abs(dy) + abs(dz) > 1e-6 else {
                throw True3DModelError.invalidParameter("移动距离不能全为 0")
            }
            guard let moved = shape.translated(by: SIMD3<Double>(dx, dy, dz)) else {
                throw True3DModelError.featureFailed("移动体失败")
            }
            if copy {
                guard let combined = shape + moved else {
                    throw True3DModelError.featureFailed("移动拷贝布尔合并失败")
                }
                return combined
            }
            return moved

        case .booleanCut(let base, let tool):
            let solids = shape.solids
            guard base >= 0, base < solids.count, tool >= 0, tool < solids.count, base != tool else {
                throw True3DModelError.invalidParameter("布尔减的基准/工具实体序号无效")
            }
            guard let result = solids[base].subtracting(solids[tool]), result.isValid else {
                throw True3DModelError.featureFailed("布尔减失败：两实体可能没有交集或存在无效面")
            }
            let others = solids.enumerated().filter { $0.offset != base && $0.offset != tool }.map { $0.element }
            if others.isEmpty { return result }
            guard let compound = Shape.compound([result] + others) else {
                throw True3DModelError.featureFailed("布尔减结果组合失败")
            }
            return compound

        case .booleanCommon(let base, let tool):
            let solids = shape.solids
            guard base >= 0, base < solids.count, tool >= 0, tool < solids.count, base != tool else {
                throw True3DModelError.invalidParameter("布尔交的基准/工具实体序号无效")
            }
            guard let result = solids[base].intersection(solids[tool]), result.isValid else {
                throw True3DModelError.featureFailed("布尔交失败：两实体可能没有公共体积")
            }
            let others = solids.enumerated().filter { $0.offset != base && $0.offset != tool }.map { $0.element }
            if others.isEmpty { return result }
            guard let compound = Shape.compound([result] + others) else {
                throw True3DModelError.featureFailed("布尔交结果组合失败")
            }
            return compound

        case .bodyArray(let rows, let cols, let pitchX, let pitchY):
            let solids = shape.solids
            guard !solids.isEmpty else {
                throw True3DModelError.invalidParameter("当前模型没有可阵列的实体")
            }
            let r = max(1, min(8, rows))
            let c = max(1, min(8, cols))
            guard r * c * solids.count <= 48 else {
                throw True3DModelError.invalidParameter("实体副本最多 48 个，请减小行/列数")
            }
            guard pitchX > 0.01 || pitchY > 0.01 else {
                throw True3DModelError.invalidParameter("阵列间距必须大于 0")
            }
            var copies: [Shape] = []
            for solid in solids {
                for row in 0..<r {
                    for col in 0..<c {
                        if row == 0 && col == 0 { continue }
                        guard let moved = solid.translated(
                            by: SIMD3<Double>(Double(col) * pitchX, Double(row) * pitchY, 0)
                        ) else {
                            throw True3DModelError.featureFailed("体阵列平移失败")
                        }
                        copies.append(moved)
                    }
                }
            }
            if copies.isEmpty { return shape }
            guard let compound = Shape.compound(solids + copies) else {
                throw True3DModelError.featureFailed("体阵列组合失败")
            }
            return compound

        case .bodyMirror(let axis):
            let solids = shape.solids
            guard !solids.isEmpty else {
                throw True3DModelError.invalidParameter("当前模型没有可镜像的实体")
            }
            let normal: SIMD3<Double>
            switch axis.uppercased() {
            case "X": normal = SIMD3<Double>(1, 0, 0)
            case "Y": normal = SIMD3<Double>(0, 1, 0)
            default:
                throw True3DModelError.invalidParameter("体镜像轴必须是 X/Y")
            }
            var copies: [Shape] = []
            for solid in solids {
                guard let mirrored = solid.mirrored(planeNormal: normal) else {
                    throw True3DModelError.featureFailed("体镜像失败")
                }
                copies.append(mirrored)
            }
            guard let compound = Shape.compound(solids + copies) else {
                throw True3DModelError.featureFailed("体镜像组合失败")
            }
            return compound
        }
    }

    private func resolve(_ ref: True3DEdgeRef, in shape: Shape) -> Edge? {
        if let exact = shape.edge(at: ref.edgeIndex), matches(ref, exact) {
            return exact
        }

        let candidates = shape.edges()
        let target = ref.midpoint.simd
        let tolerance = max(ref.length * 0.02, 0.05)
        return candidates
            .map { edge -> (Edge, Double) in
                let points = edge.points(count: 5)
                let midpoint: SIMD3<Double>
                if points.isEmpty {
                    midpoint = SIMD3(0, 0, 0)
                } else {
                    midpoint = points.reduce(SIMD3<Double>(0, 0, 0)) { $0 + $1 } / Double(points.count)
                }
                let distance = simd_distance(midpoint, target)
                let lengthDelta = abs(edge.length - ref.length)
                return (edge, distance + lengthDelta * 0.5)
            }
            .filter { $0.1 <= tolerance }
            .min { $0.1 < $1.1 }?
            .0
    }

    private func matches(_ ref: True3DEdgeRef, _ edge: Edge) -> Bool {
        guard abs(edge.length - ref.length) <= max(ref.length * 0.02, 0.05) else {
            return false
        }
        let points = edge.points(count: 5)
        guard !points.isEmpty else { return false }
        let midpoint = points.reduce(SIMD3<Double>(0, 0, 0)) { $0 + $1 } / Double(points.count)
        return simd_distance(midpoint, ref.midpoint.simd) <= max(ref.length * 0.02, 0.05)
    }

    private func fmt(_ value: Double) -> String {
        String(format: "%.2f", value).replacingOccurrences(of: ".00", with: "")
    }
}

// MARK: - Stats

extension True3DStats {
    static func measure(shape: Shape, mesh: Mesh, fallback: True3DParams? = nil) -> True3DStats {
        let size: (Double, Double, Double)
        if let bounds = shape.bounds {
            size = (
                bounds.max.x - bounds.min.x,
                bounds.max.y - bounds.min.y,
                bounds.max.z - bounds.min.z
            )
        } else if let fallback {
            size = (fallback.width, fallback.depth, fallback.height)
        } else {
            size = (0, 0, 0)
        }

        return True3DStats(
            volume: shape.volume ?? 0,
            faces: shape.faceCount,
            edges: shape.edgeCount,
            triangles: mesh.triangleCount,
            valid: shape.isValid,
            sizeX: size.0,
            sizeY: size.1,
            sizeZ: size.2
        )
    }
}
