import Foundation
import CoreGraphics
import OCCTSwift

// MARK: - 3D 加工参数

struct True3DCAMParams: Equatable, Codable {
    var toolDia: Double = 6
    var toolNo: Int = 1
    var hNo: Int = 1

    var spindle: Int = 2000
    var feed: Int = 400
    var plungeFeed: Int = 120
    var stepDown: Double = 3
    var stepOver: Double = 4
    var safeZ: Double = 100

    var stockMarginXY: Double = 8
    var stockExtraBottom: Double = 1
    /// 粗加工侧壁余量；单项工序未单独设置时使用该默认值。
    var stockLeft: Double = 0

    var coord: Int = 54
    var originX: Double = 0
    var originY: Double = 0
    /// 输出 G 代码时把模型中心平移到 G54 X0Y0；仿真仍保留模型坐标。
    var stockCenterOrigin: Bool = true
    /// 3D 工序输出：普通 G 代码 / 宏变量程序。
    var programFormat: ProgramFormat = .gcode
    var programNo: Int = 1010
    var coolant: True3DCoolant = .flood

    var doRoughing: Bool = true
    var doFinishing: Bool = true
    var doClearInner: Bool = true
    var doFaceBaseTop: Bool = true
    var doFaceBossTop: Bool = true
    var doFacePocketBottom: Bool = true

    var toolRadius: Double { max(toolDia, 0.1) / 2 }

    /// 非空时按工序树逐道生成，忽略上面的 doXxx 开关和单刀具字段。
    var operations: [True3DOperation] = []
}

// MARK: - 工序树

enum True3DOperationKind: String, CaseIterable, Identifiable, Codable {
    case faceBase = "基础顶面飞面"
    case rough = "外形分层粗铣"
    case finish = "外形精铣"
    case chamfer = "45°倒角铣"
    case compFinish = "刀补精修"
    case clearInner = "孔 / 腔清残"
    case hole = "孔 / 孔阵列"
    case holeRect = "矩形孔阵列"
    case holeCircle = "圆周孔阵列"
    case pocket = "矩形型腔"
    case pocketRound = "圆型腔"
    case slot = "腰槽"
    case slotHalf = "半腰槽"
    case slotOpen = "开放槽"
    case slotArc = "圆弧槽"
    case profileCut = "轮廓切除"
    case faceBoss = "凸台顶面飞面"
    case facePocket = "型腔底面飞面"

    var id: String { rawValue }

    /// 这些工序按模型里的孔/腔/槽/草图切除直接生成局部刀路。
    var isFeatureInner: Bool {
        switch self {
        case .hole, .holeRect, .holeCircle, .pocket, .pocketRound,
             .slot, .slotHalf, .slotOpen, .slotArc, .profileCut:
            return true
        default:
            return false
        }
    }

    var featureButtonKind: True3DFeatureKind? {
        switch self {
        case .hole, .holeRect, .holeCircle: return .hole
        case .pocketRound: return .circularPocket
        case .pocket: return .rectPocket
        case .slot, .slotHalf, .slotOpen, .slotArc: return .slot
        case .profileCut: return .profileCut
        default: return nil
        }
    }

    var needsArray: Bool { self == .holeRect || self == .holeCircle }
    var needsSlot: Bool { self == .slotHalf || self == .slotOpen || self == .slotArc }

    var detail: String {
        switch self {
        case .faceBase: return "顶面行切，避开凸台和孔"
        case .rough: return "沿真实截面等高偏置，按层下切"
        case .finish: return "最后一层沿侧壁精修，可选 G41/G42"
        case .chamfer: return "按 45°/可调角度逐层向内缩，沿外轮廓倒角"
        case .compFinish: return "沿真实外轮廓输出 G41/G42 D 刀补精修"
        case .clearInner: return "孔、圆腔、方腔、腰槽、草图切除逐层清残"
        case .hole: return "按模型孔逐孔螺旋下刀清孔"
        case .holeRect: return "种子孔按矩形阵列复制清孔"
        case .holeCircle: return "种子孔按圆周均布复制清孔"
        case .pocket: return "矩形型腔逐层向内偏置清残"
        case .pocketRound: return "圆腔逐层环形清残"
        case .slot: return "腰槽沿中心线分层往复走刀"
        case .slotHalf: return "开放端到圆端的半腰槽"
        case .slotOpen: return "从槽端外起刀的开放槽"
        case .slotArc: return "沿圆弧中心线分层铣槽"
        case .profileCut: return "沿草图切除轮廓分层精修"
        case .faceBoss: return "每个凸台顶面单独行切"
        case .facePocket: return "腔底和孔底清根"
        }
    }
}

enum True3DCoolant: String, CaseIterable, Identifiable, Codable {
    case off = "关闭"
    case flood = "M8  flood"
    case mist = "M7  mist"
    var id: String { rawValue }
    var code: String? {
        switch self {
        case .off: return nil
        case .flood: return "M08"
        case .mist: return "M07"
        }
    }
}

struct True3DOperation: Identifiable, Equatable, Codable {
    var id = UUID()
    var kind: True3DOperationKind = .rough
    var enabled = true
    var toolDia: Double = 6
    var toolNo: Int = 1
    var hNo: Int = 1
    var dNo: Int = 1
    var spindle: Int = 2000
    var feed: Int = 400
    var plungeFeed: Int = 120
    var stepDown: Double = 3
    var stepOver: Double = 4
    /// "off" / "G41" / "G42"
    var comp: String = "off"
    var chamferDepth: Double = 1
    var chamferAngle: Double = 45
    /// 粗加工侧壁余量（mm）；精修工序按 0 处理。
    var stockLeft: Double = 0
    /// true = 顺铣，false = 逆铣。仅改变刀路方向，不改轮廓。
    var climb: Bool = true
    var coolant: True3DCoolant = .flood

    /// 加工对象在 model.features 中的下标；-1 表示所有同类特征。
    var targetFeatureIndex: Int = -1
    /// 孔阵列参数。
    var arrayX: Double = 0
    var arrayY: Double = 0
    var arrayDia: Double = 6
    var arrayDepth: Double = 6
    var arrayNx: Int = 2
    var arrayNy: Int = 2
    var arrayDx: Double = 20
    var arrayDy: Double = 15
    var arrayR: Double = 30
    var arrayN: Int = 6
    var arrayStart: Double = 0
    /// 槽参数；没有选中模型槽时使用。
    var slotCx: Double = 0
    var slotCy: Double = 0
    var slotLength: Double = 30
    var slotWidth: Double = 10
    var slotDepth: Double = 5
    var slotAngle: Double = 0
    var slotArcR: Double = 30
    var slotArcStart: Double = -60
    var slotArcEnd: Double = 60
}

/// 刀补轮廓：G 代码按真实轮廓 + G41/G42 D 输出，仿真显示刀心轨迹。
struct True3DCompPass {
    let side: String
    let dNo: Int
    let z: Double
    let lead: CGPoint
    let contour: [CGPoint]
}

struct True3DCAMRun {
    let operation: True3DOperation
    let segments: [TPSeg]
    let stats: True3DCAMStats
    var comp: True3DCompPass? = nil
}

struct True3DCAMStats {
    var cutLength: Double = 0
    var rapidLength: Double = 0
    var pathCount: Int = 0
    var layerCount: Int = 0
    var zMin: Double = 0
    var zMax: Double = 0
    var sectionCount: Int = 0
}

struct True3DCAMResult {
    let segments: [TPSeg]
    let gcode: String
    let stats: True3DCAMStats
    let warnings: [String]
    var runs: [True3DCAMRun] = []
    /// 每道工序单独成程序的 G 代码；runCodes[i] 对应 runs[i]。
    var runCodes: [String] = []
}

enum True3DCAMError: LocalizedError {
    case invalidTool
    case invalidStep
    case invalidModel
    case emptyToolpath

    var errorDescription: String? {
        switch self {
        case .invalidTool: return "刀具直径/转速/进给不合理"
        case .invalidStep: return "每层切深和行距必须大于 0"
        case .invalidModel: return "当前 3D 实体无效，不能生成刀路"
        case .emptyToolpath: return "没有生成有效刀路，请检查模型、刀具和余量"
        }
    }
}

// MARK: - B-Rep 截面刀路

enum True3DCAM {
    private struct CamLoop {
        let wire: Wire
        let points: [CGPoint]
        let area: Double
        let isHole: Bool
    }

    static func generate(
        result: True3DResult,
        model: True3DParams,
        cam: True3DCAMParams
    ) throws -> True3DCAMResult {
        let enabledOperations = cam.operations.filter(\.enabled)
        if !enabledOperations.isEmpty {
            return try generateOperations(result: result, model: model, cam: cam, operations: enabledOperations)
        }
        guard cam.toolDia > 0.2, cam.spindle > 0, cam.feed > 0, cam.plungeFeed > 0 else {
            throw True3DCAMError.invalidTool
        }
        guard cam.stepDown > 0.05, cam.stepOver > 0.05 else {
            throw True3DCAMError.invalidStep
        }
        guard result.stats.valid, let bounds = result.shape.bounds else {
            throw True3DCAMError.invalidModel
        }

        let radius = cam.toolRadius
        let allowance = max(0, cam.stockLeft)
        let bottom = bounds.min.z - max(0, cam.stockExtraBottom)
        let top = bounds.max.z
        let baseTop = max(0, model.height)
        let effectiveSafeZ = max(cam.safeZ, top + 2)

        var segments: [TPSeg] = []
        var warnings: [String] = []
        var sectionCount = 0

        // 1. 顶面 / 底面：用真实截面轮廓做面铣，不再靠 2.5D 外形推。
        if cam.doFaceBaseTop {
            if let loops = loopsAt(result.shape, z: baseTop - 0.02),
               let outer = loops.filter({ !$0.isHole }).max(by: { $0.area < $1.area }) {
                var obstacles = loops.filter(\.isHole).map(\.points)
                for boss in model.bossFeatures {
                    obstacles.append(circlePoints(
                        cx: boss.x,
                        cy: boss.y,
                        r: boss.dia / 2 + radius + 0.4
                    ))
                }
                let faceSegs = faceSegments(
                    outer: outer.points,
                    obstacles: obstacles,
                    z: baseTop,
                    radius: radius,
                    stepOver: cam.stepOver
                )
                segments.append(contentsOf: faceSegs)
            } else {
                warnings.append("基础顶面截面为空，跳过飞面")
            }
        }

        if cam.doFaceBossTop {
            for boss in model.bossFeatures {
                let zTop = model.bossTop(boss)
                if let loops = loopsAt(result.shape, z: zTop - 0.02),
                   let outer = loops.filter({ !$0.isHole }).max(by: { $0.area < $1.area }) {
                    let faceSegs = faceSegments(
                        outer: outer.points,
                        obstacles: [],
                        z: zTop,
                        radius: radius,
                        stepOver: cam.stepOver
                    )
                    segments.append(contentsOf: faceSegs)
                } else {
                    warnings.append("\(boss.name) 顶面截面为空，跳过飞面")
                }
            }
        }

        if cam.doFacePocketBottom {
            for pocket in model.pocketFeatures {
                let zBottom = model.pocketBottom(pocket)
                if let loops = loopsAt(result.shape, z: zBottom + 0.02),
                   let inner = loops.filter(\.isHole).first(where: {
                       pointInPolygon(CGPoint(x: pocket.x, y: pocket.y), $0.points)
                   }) ?? loops.filter(\.isHole).max(by: { $0.area < $1.area }) {
                    let faceSegs = faceSegments(
                        outer: inner.points,
                        obstacles: [],
                        z: zBottom,
                        radius: radius,
                        stepOver: cam.stepOver
                    )
                    segments.append(contentsOf: faceSegs)
                }
            }
        }

        // 2. 截面等高线：每个 Z 层由 OCCT 截出真实轮廓，再按刀半径偏置。
        var levels = Set<Double>()
        levels.insert(top - 0.01)
        levels.insert(bottom + 0.01)
        if baseTop > bottom + 0.02 { levels.insert(baseTop - 0.01) }
        for boss in model.bossFeatures {
            let zTop = model.bossTop(boss)
            if zTop > baseTop + 0.02 { levels.insert(zTop - 0.01) }
        }
        for pocket in model.pocketFeatures {
            let zBottom = model.pocketBottom(pocket)
            if zBottom > bottom + 0.02 { levels.insert(zBottom + 0.01) }
        }

        var z = top - 0.01
        var guardCount = 0
        while z > bottom + 0.02, guardCount < 400 {
            levels.insert(z)
            z -= cam.stepDown
            guardCount += 1
        }

        let sortedLevels = levels.sorted(by: >)
        for level in sortedLevels {
            guard level > bottom, level < top + 0.5 else { continue }
            guard let loops = loopsAt(result.shape, z: level) else { continue }
            sectionCount += 1
            let outerLoops = loops.filter { !$0.isHole }
            let holeLoops = loops.filter(\.isHole)

            for outer in outerLoops {
                let maxRing = max(
                    0,
                    Int(floor((max(0, cam.stockMarginXY) - radius - allowance) / max(cam.stepOver, 0.1)))
                )
                if cam.doRoughing, maxRing > 0 {
                    for k in stride(from: maxRing, through: 1, by: -1) {
                        let distance = radius + allowance + Double(k) * cam.stepOver
                        if let poly = offset(outer, by: distance, expand: true) {
                            appendPath(poly, z: level, into: &segments)
                        }
                    }
                }
                if cam.doFinishing || (cam.doRoughing && maxRing == 0) {
                    if let poly = offset(outer, by: radius + allowance, expand: true) {
                        appendPath(poly, z: level, into: &segments)
                    } else {
                        warnings.append("Z\(fmt(level)) 外轮廓偏置失败，已跳过")
                    }
                }
            }

            for hole in holeLoops {
                if cam.doClearInner {
                    var k = 0
                    while k < 60 {
                        let distance = radius + Double(k) * cam.stepOver
                        guard let poly = offset(hole, by: distance, expand: false) else { break }
                        appendPath(poly, z: level, into: &segments)
                        if polygonArea(poly) < 0.5 { break }
                        k += 1
                    }
                } else if cam.doFinishing {
                    if let poly = offset(hole, by: radius, expand: false) {
                        appendPath(poly, z: level, into: &segments)
                    }
                }
            }
        }

        guard !segments.isEmpty else { throw True3DCAMError.emptyToolpath }

        // 3. 统计与 G 代码
        var stats = True3DCAMStats()
        stats.pathCount = segments.count
        stats.cutLength = segments.reduce(0) { $0 + $1.len }
        stats.layerCount = Set(segments.map { Int(($0.z * 1000).rounded()) }).count
        stats.zMin = segments.map(\.z).min() ?? 0
        stats.zMax = segments.map(\.z).max() ?? 0
        stats.sectionCount = sectionCount

        var previousEnd: CGPoint?
        var previousZ: Double?
        var rapid = 0.0
        for seg in segments {
            guard let first = seg.pts.first, let last = seg.pts.last else { continue }
            if let pe = previousEnd, let pz = previousZ {
                if distance(pe, first) > 0.01 {
                    rapid += sqrt(pow(Double(first.x - pe.x), 2) + pow(Double(first.y - pe.y), 2))
                }
                rapid += abs(seg.z - pz) * 2
            }
            previousEnd = last
            previousZ = seg.z
        }
        stats.rapidLength = rapid

        if radius * 2 >= min(model.width, model.depth) {
            warnings.append("刀具直径接近工件最小边，外形可能被过切")
        }
        for hole in model.holeFeatures where radius * 2 >= hole.dia {
            warnings.append("刀具直径不小于孔 \(hole.name) 的直径，孔内清残无法完整加工")
        }
        for pocket in model.pocketFeatures {
            let minSize = pocket.kind == .circularPocket ? pocket.dia : min(pocket.width, pocket.depthY)
            if radius * 2 >= minSize {
                warnings.append("刀具直径不小于 \(pocket.name) 的最小边，型腔内部无法完整清残")
            }
        }
        warnings.append("当前为三轴等高线刀路；陡壁用截面偏置，顶面用行切，深腔/孔为逐层清残。上机前请先仿真并确认下刀方式。")

        let gcode = makeGCode(
            segments: segments,
            cam: cam,
            safeZ: effectiveSafeZ,
            bounds: bounds,
            stats: stats,
            warnings: warnings
        )

        return True3DCAMResult(
            segments: segments,
            gcode: gcode,
            stats: stats,
            warnings: warnings,
            runCodes: [gcode]
        )
    }

    // MARK: 多工序

    private static func generateOperations(
        result: True3DResult,
        model: True3DParams,
        cam: True3DCAMParams,
        operations: [True3DOperation]
    ) throws -> True3DCAMResult {
        var allSegments: [TPSeg] = []
        var runs: [True3DCAMRun] = []
        var warnings: [String] = []
        var stats = True3DCAMStats()
        var layerKeys = Set<Int>()

        func appendRun(_ run: True3DCAMRun, runWarnings: [String] = []) {
            let directed = (!run.operation.climb && run.comp == nil) ? reverseRun(run) : run
            allSegments.append(contentsOf: directed.segments)
            for warning in runWarnings {
                let tagged = "[\(directed.operation.kind.rawValue)] \(warning)"
                if !warnings.contains(tagged) { warnings.append(tagged) }
            }
            stats.cutLength += directed.stats.cutLength
            stats.rapidLength += directed.stats.rapidLength
            stats.pathCount += directed.stats.pathCount
            stats.sectionCount += directed.stats.sectionCount
            stats.zMin = runs.isEmpty ? directed.stats.zMin : min(stats.zMin, directed.stats.zMin)
            stats.zMax = runs.isEmpty ? directed.stats.zMax : max(stats.zMax, directed.stats.zMax)
            for seg in directed.segments { layerKeys.insert(Int((seg.z * 1000).rounded())) }
            stats.layerCount = layerKeys.count
            runs.append(directed)
        }

        for operation in operations {
            if let special = try makeSpecialRun(operation: operation, result: result, model: model, cam: cam) {
                appendRun(special.run, runWarnings: special.warnings)
                continue
            }

            var single = cam
            single.operations = []
            single.doRoughing = false
            single.doFinishing = false
            single.doClearInner = false
            single.doFaceBaseTop = false
            single.doFaceBossTop = false
            single.doFacePocketBottom = false
            switch operation.kind {
            case .faceBase: single.doFaceBaseTop = true
            case .rough: single.doRoughing = true
            case .finish: single.doFinishing = true
            case .compFinish: single.doFinishing = true
            case .chamfer: throw True3DCAMError.emptyToolpath
            case .clearInner: single.doClearInner = true
            case .hole, .holeRect, .holeCircle, .pocket, .pocketRound,
                 .slot, .slotHalf, .slotOpen, .slotArc, .profileCut:
                single.doClearInner = true
            case .faceBoss: single.doFaceBossTop = true
            case .facePocket: single.doFacePocketBottom = true
            }
            single.toolDia = operation.toolDia
            single.toolNo = operation.toolNo
            single.hNo = operation.hNo
            single.spindle = operation.spindle
            single.feed = operation.feed
            single.plungeFeed = operation.plungeFeed
            single.stepDown = operation.stepDown
            single.stepOver = operation.stepOver
            single.stockLeft = operation.kind == .rough ? operation.stockLeft : 0

            let runResult: True3DCAMResult
            do {
                runResult = try generate(result: result, model: model, cam: single)
            } catch let error as True3DCAMError {
                if case .emptyToolpath = error {
                    warnings.append("[\(operation.kind.rawValue)] 没有可用刀路，已跳过")
                    continue
                }
                throw error
            }

            let run = True3DCAMRun(
                operation: operation,
                segments: runResult.segments,
                stats: runResult.stats
            )
            appendRun(run, runWarnings: runResult.warnings)
        }

        guard !allSegments.isEmpty else { throw True3DCAMError.emptyToolpath }
        guard let bounds = result.shape.bounds else { throw True3DCAMError.invalidModel }
        let safeZ = max(cam.safeZ, bounds.max.z + 2)
        warnings.append("共 \(runs.count) 道工序 / \(Set(runs.map { $0.operation.toolNo }).count) 把刀；换刀和 Z 轴回零请按机床实际配置确认。")
        let gcode = makeMultiGCode(
            runs: runs,
            cam: cam,
            safeZ: safeZ,
            bounds: bounds,
            stats: stats,
            warnings: warnings
        )
        let runCodes = runs.enumerated().map { offset, run -> String in
            var oneCam = cam
            oneCam.programNo = cam.programNo + offset + 1
            return makeMultiGCode(
                runs: [run],
                cam: oneCam,
                safeZ: safeZ,
                bounds: bounds,
                stats: run.stats,
                warnings: []
            )
        }
        return True3DCAMResult(
            segments: allSegments,
            gcode: gcode,
            stats: stats,
            warnings: warnings,
            runs: runs,
            runCodes: runCodes
        )
    }

    /// 倒角 / 刀补精修：直接用真实截面外轮廓，不走普通分层偏置。
    private static func makeSpecialRun(
        operation: True3DOperation,
        result: True3DResult,
        model: True3DParams,
        cam: True3DCAMParams
    ) throws -> (run: True3DCAMRun, warnings: [String])? {
        let kind = operation.kind
        if kind.isFeatureInner {
            return try makeFeatureRun(operation: operation, result: result, model: model, cam: cam)
        }
        let compKind = (kind == .finish || kind == .compFinish) && operation.comp != "off"
        guard kind == .chamfer || compKind else { return nil }
        guard let bounds = result.shape.bounds else { throw True3DCAMError.invalidModel }
        let radius = max(operation.toolDia, 0.1) / 2
        var warnings: [String] = []
        var segments: [TPSeg] = []
        var comp: True3DCompPass?
        var sectionCount = 0

        if kind == .chamfer {
            let top = bounds.max.z
            guard let loops = loopsAt(result.shape, z: top - 0.02),
                  let outer = loops.filter({ !$0.isHole }).max(by: { $0.area < $1.area }) else {
                throw True3DCAMError.emptyToolpath
            }
            let depth = max(0.1, min(operation.chamferDepth, max(0.2, top - bounds.min.z - 0.1)))
            let angle = max(1, min(80, operation.chamferAngle))
            let levels = max(1, Int(ceil(depth / max(operation.stepDown, 0.05))))
            let step = depth / Double(levels)
            let radialPerDepth = tan(angle * .pi / 180)
            for level in 1...levels {
                let d = min(step * Double(level), depth)
                if let inset = offset(outer, by: d * radialPerDepth, expand: false) {
                    appendPath(inset, z: top - d, into: &segments)
                    sectionCount += 1
                } else {
                    warnings.append("倒角第 \(level) 层偏置失败，已跳过该层")
                }
            }
            if segments.isEmpty { throw True3DCAMError.emptyToolpath }
        } else {
            let z = bounds.min.z
            guard let loops = loopsAt(result.shape, z: z + 0.02),
                  let outer = loops.filter({ !$0.isHole }).max(by: { $0.area < $1.area }) else {
                throw True3DCAMError.emptyToolpath
            }
            let side = operation.comp == "G41" ? "G41" : "G42"
            let display = offset(outer, by: radius, expand: side == "G42")
            if display == nil {
                warnings.append("刀补显示轮廓未能偏置，按真实轮廓显示；上机前请仿真确认")
            }
            appendPath(display ?? outer.points, z: z, into: &segments)
            sectionCount = 1

            let contour = outer.points
            guard let first = contour.first else { throw True3DCAMError.emptyToolpath }
            let center = centroid(contour)
            var vx = Double(first.x - center.x)
            var vy = Double(first.y - center.y)
            let length = max(sqrt(vx * vx + vy * vy), 0.001)
            vx /= length; vy /= length
            let lead = CGPoint(x: first.x + CGFloat(vx) * CGFloat(radius + 2),
                               y: first.y + CGFloat(vy) * CGFloat(radius + 2))
            comp = True3DCompPass(
                side: side,
                dNo: operation.dNo,
                z: z,
                lead: lead,
                contour: contour
            )
        }

        guard !segments.isEmpty else { throw True3DCAMError.emptyToolpath }
        let stats = makeStats(segments: segments, sectionCount: sectionCount)
        let run = True3DCAMRun(
            operation: operation,
            segments: segments,
            stats: stats,
            comp: comp
        )
        return (run, warnings)
    }

    /// 按模型里的孔/腔/槽/草图切除生成独立工序刀路。
    private static func makeFeatureRun(
        operation: True3DOperation,
        result: True3DResult,
        model: True3DParams,
        cam: True3DCAMParams
    ) throws -> (run: True3DCAMRun, warnings: [String]) {
        let kind = operation.kind
        let radius = max(operation.toolDia, 0.1) / 2
        let step = max(operation.stepDown, 0.05)
        let stepOver = max(operation.stepOver, 0.1)
        let stockBottom = max(0, cam.stockExtraBottom)
        var warnings: [String] = []
        var segments: [TPSeg] = []
        var sectionCount = 0

        func layers(top: Double, depth: Double) -> [Double] {
            let bottom = top - max(0.1, depth)
            var zs: [Double] = []
            var z = top - min(step, max(0.1, depth))
            while z >= bottom - 1e-6 {
                zs.append(max(z, bottom))
                z -= step
            }
            if zs.isEmpty { zs = [bottom] }
            return zs
        }

        func appendLoop(_ pts: [CGPoint], z: Double) {
            guard pts.count >= 3 else { return }
            var closed = pts
            if let first = closed.first, let last = closed.last, distance(first, last) > 0.001 {
                closed.append(first)
            }
            appendPath(closed, z: z, into: &segments)
        }

        func appendOpen(_ pts: [CGPoint], z: Double) {
            guard pts.count >= 2 else { return }
            appendPath(pts, z: z, into: &segments)
        }

        func holePasses(cx: Double, cy: Double, holeR: Double, top: Double, depth: Double, label: String) {
            guard holeR >= radius - 0.01 else {
                warnings.append("\(label) Ø\(fmt(holeR * 2)) 小于刀径 Ø\(fmt(operation.toolDia))，已跳过")
                return
            }
            let maxR = max(radius, holeR - radius)
            let ringStep = max(stepOver, 0.5)
            for z in layers(top: top, depth: depth) {
                var ringR = min(radius, maxR)
                repeat {
                    appendLoop(circlePoints(cx: cx, cy: cy, r: ringR), z: z)
                    ringR += ringStep
                } while ringR <= maxR + 0.01
                sectionCount += 1
            }
        }

        func rectPocketPasses(_ f: True3DFeatureSpec, top: Double, depth: Double) {
            let w = max(operation.toolDia + 0.5, f.width)
            let h = max(operation.toolDia + 0.5, f.depthY)
            let maxInset = min(w, h) / 2 - radius - 0.05
            guard maxInset >= radius - 0.01 else {
                warnings.append("\(f.name) 尺寸太小，无法用 Ø\(fmt(operation.toolDia)) 清腔")
                return
            }
            for z in layers(top: top, depth: depth) {
                var inset = radius
                while inset <= maxInset + 0.01 {
                    let hw = w / 2 - inset, hh = h / 2 - inset
                    guard hw > 0.1, hh > 0.1 else { break }
                    appendLoop([
                        CGPoint(x: f.x - hw, y: f.y - hh),
                        CGPoint(x: f.x + hw, y: f.y - hh),
                        CGPoint(x: f.x + hw, y: f.y + hh),
                        CGPoint(x: f.x - hw, y: f.y + hh)
                    ], z: z)
                    inset += stepOver
                }
                sectionCount += 1
            }
        }

        func slotPasses(start: CGPoint, end: CGPoint, width: Double, top: Double, depth: Double) {
            let dx = Double(end.x - start.x), dy = Double(end.y - start.y)
            let len = max(sqrt(dx * dx + dy * dy), 0.001)
            let ux = dx / len, uy = dy / len
            let nx = -uy, ny = ux
            let across = max(0, width - operation.toolDia)
            let nPass = max(1, Int(ceil(across / stepOver)) + 1)
            for z in layers(top: top, depth: depth) {
                for k in 0..<nPass {
                    let off = nPass == 1 ? 0 : -across / 2 + Double(k) * across / Double(nPass - 1)
                    appendOpen([
                        CGPoint(x: Double(start.x) + nx * off, y: Double(start.y) + ny * off),
                        CGPoint(x: Double(end.x) + nx * off, y: Double(end.y) + ny * off)
                    ], z: z)
                }
                sectionCount += 1
            }
        }

        func matchingFeature(_ kinds: [True3DFeatureKind]) -> [(Int, True3DFeatureSpec)] {
            let all = model.features.enumerated().filter { !$0.element.suppressed && kinds.contains($0.element.kind) }
            if operation.targetFeatureIndex >= 0 {
                return all.filter { $0.offset == operation.targetFeatureIndex }
            }
            return all
        }

        switch kind {
        case .hole:
            let holes = matchingFeature([.hole])
            if holes.isEmpty { warnings.append("模型里没有可加工的孔") }
            for (_, f) in holes {
                let top = f.topZ ?? model.height
                let depth = f.holeKind == .through ? top + stockBottom : max(f.depth, f.holeDepth)
                holePasses(cx: f.x, cy: f.y, holeR: f.dia / 2, top: top, depth: depth, label: f.name)
            }

        case .holeRect, .holeCircle:
            let seed = matchingFeature([.hole]).first?.element
            let sx = seed?.x ?? operation.arrayX
            let sy = seed?.y ?? operation.arrayY
            let sr = (seed?.dia ?? operation.arrayDia) / 2
            let top = seed?.topZ ?? model.height
            let depth = max(operation.arrayDepth, 0.1)
            if seed == nil { warnings.append("没有种子孔，阵列中心按 (0,0) / 参数生成") }
            if kind == .holeRect {
                let nx = max(1, min(30, operation.arrayNx))
                let ny = max(1, min(30, operation.arrayNy))
                for j in 0..<ny {
                    for i in 0..<nx {
                        let x = sx + (Double(i) - Double(nx - 1) / 2) * operation.arrayDx
                        let y = sy + (Double(j) - Double(ny - 1) / 2) * operation.arrayDy
                        holePasses(cx: x, cy: y, holeR: sr, top: top, depth: depth, label: "矩形阵列孔")
                    }
                }
            } else {
                let n = max(2, min(90, operation.arrayN))
                for i in 0..<n {
                    let a = operation.arrayStart * .pi / 180 + Double(i) / Double(n) * 2 * .pi
                    holePasses(cx: sx + cos(a) * operation.arrayR, cy: sy + sin(a) * operation.arrayR,
                               holeR: sr, top: top, depth: depth, label: "圆周阵列孔")
                }
            }

        case .pocket:
            let pockets = matchingFeature([.rectPocket])
            if pockets.isEmpty { warnings.append("模型里没有矩形型腔") }
            for (_, f) in pockets {
                rectPocketPasses(f, top: f.topZ ?? model.height, depth: max(f.depth, 0.1))
            }

        case .pocketRound:
            let pockets = matchingFeature([.circularPocket, .hole])
            if pockets.isEmpty { warnings.append("模型里没有圆腔/孔") }
            for (_, f) in pockets {
                let top = f.topZ ?? model.height
                let depth = f.kind == .hole
                    ? (f.holeKind == .through ? top + stockBottom : max(f.depth, f.holeDepth))
                    : max(f.depth, 0.1)
                holePasses(cx: f.x, cy: f.y, holeR: f.dia / 2, top: top, depth: depth, label: f.name)
            }

        case .slot, .slotHalf, .slotOpen:
            let slots = matchingFeature([.slot])
            if kind == .slot {
                if slots.isEmpty { warnings.append("模型里没有腰槽") }
                for (_, f) in slots {
                    let top = f.topZ ?? model.height
                    let half = max(0, (f.width - f.depthY) / 2)
                    slotPasses(
                        start: CGPoint(x: f.x - half, y: f.y),
                        end: CGPoint(x: f.x + half, y: f.y),
                        width: f.depthY,
                        top: top,
                        depth: max(f.depth, 0.1)
                    )
                }
            } else {
                let f = slots.first?.element
                let cx = f?.x ?? operation.slotCx
                let cy = f?.y ?? operation.slotCy
                let length = f?.width ?? operation.slotLength
                let width = f?.depthY ?? operation.slotWidth
                let angle = operation.slotAngle * .pi / 180
                let half = max(0, (length - width) / 2)
                let ux = cos(angle), uy = sin(angle)
                let top = f?.topZ ?? model.height
                let depth = max(f?.depth ?? operation.slotDepth, 0.1)
                let start: CGPoint
                if kind == .slotOpen {
                    let ext = half + max(8, width)
                    start = CGPoint(x: cx - ux * ext, y: cy - uy * ext)
                } else {
                    start = CGPoint(x: cx - ux * half, y: cy - uy * half)
                }
                let end = kind == .slotHalf
                    ? CGPoint(x: cx, y: cy)
                    : CGPoint(x: cx + ux * half, y: cy + uy * half)
                slotPasses(start: start, end: end, width: width, top: top, depth: depth)
                warnings.append(kind == .slotOpen ? "开放槽从槽端外起刀，边缘请对刀确认" : "半腰槽按中心到一端生成，开放端请按图纸确认")
            }

        case .slotArc:
            let seed = matchingFeature([.slot]).first?.element
            let cx = seed?.x ?? operation.slotCx
            let cy = seed?.y ?? operation.slotCy
            let R = max(operation.toolDia, operation.slotArcR)
            let a0 = operation.slotArcStart * .pi / 180
            let a1 = operation.slotArcEnd * .pi / 180
            let width = max(operation.toolDia, operation.slotWidth)
            let across = max(0, width - operation.toolDia)
            let nPass = max(1, Int(ceil(across / stepOver)) + 1)
            let n = max(12, min(90, Int(abs(a1 - a0) * R / 2)))
            let top = seed?.topZ ?? model.height
            for z in layers(top: top, depth: max(operation.slotDepth, 0.1)) {
                for k in 0..<nPass {
                    let off = nPass == 1 ? 0 : -across / 2 + Double(k) * across / Double(nPass - 1)
                    var pts: [CGPoint] = []
                    for i in 0...n {
                        let a = a0 + (a1 - a0) * Double(i) / Double(n)
                        let rr = R + off
                        pts.append(CGPoint(x: cx + cos(a) * rr, y: cy + sin(a) * rr))
                    }
                    appendOpen(pts, z: z)
                }
                sectionCount += 1
            }

        case .profileCut:
            let profiles = matchingFeature([.profileCut])
            if profiles.isEmpty { warnings.append("模型里没有草图切除轮廓") }
            for (_, f) in profiles {
                let raw = f.profile.map { CGPoint(x: $0.x, y: $0.y) }
                guard raw.count >= 3 else {
                    warnings.append("\(f.name) 轮廓点不足，已跳过")
                    continue
                }
                let inset = offsetPolygon(raw, by: -radius) ?? raw
                let top = f.topZ ?? model.height
                for z in layers(top: top, depth: max(f.depth, 0.1)) {
                    appendLoop(inset, z: z)
                    sectionCount += 1
                }
            }

        default:
            throw True3DCAMError.emptyToolpath
        }

        guard !segments.isEmpty else { throw True3DCAMError.emptyToolpath }
        let stats = makeStats(segments: segments, sectionCount: sectionCount)
        let run = True3DCAMRun(operation: operation, segments: segments, stats: stats)
        return (run, warnings)
    }

    private static func reverseRun(_ run: True3DCAMRun) -> True3DCAMRun {
        let segments = run.segments.map { seg in
            TPSeg(cut: seg.cut, z: seg.z, pts: Array(seg.pts.reversed()), len: seg.len)
        }
        let stats = makeStats(segments: segments, sectionCount: run.stats.sectionCount)
        return True3DCAMRun(operation: run.operation, segments: segments, stats: stats, comp: run.comp)
    }

    private static func makeStats(segments: [TPSeg], sectionCount: Int) -> True3DCAMStats {
        var stats = True3DCAMStats()
        stats.pathCount = segments.count
        stats.cutLength = segments.reduce(0) { $0 + $1.len }
        stats.layerCount = Set(segments.map { Int(($0.z * 1000).rounded()) }).count
        stats.zMin = segments.map(\.z).min() ?? 0
        stats.zMax = segments.map(\.z).max() ?? 0
        stats.sectionCount = sectionCount
        var previousEnd: CGPoint?
        var previousZ: Double?
        var rapid = 0.0
        for seg in segments {
            guard let first = seg.pts.first, let last = seg.pts.last else { continue }
            if let pe = previousEnd, let pz = previousZ {
                if distance(pe, first) > 0.01 {
                    rapid += sqrt(pow(Double(first.x - pe.x), 2) + pow(Double(first.y - pe.y), 2))
                }
                rapid += abs(seg.z - pz) * 2
            }
            previousEnd = last
            previousZ = seg.z
        }
        stats.rapidLength = rapid
        return stats
    }

    private static func centroid(_ points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        let x = points.reduce(0.0) { $0 + Double($1.x) } / Double(points.count)
        let y = points.reduce(0.0) { $0 + Double($1.y) } / Double(points.count)
        return CGPoint(x: x, y: y)
    }

    // MARK: 截面 / 偏置

    private static func loopsAt(_ shape: Shape, z: Double) -> [CamLoop]? {
        let wires = shape.sectionWiresAtZ(z, tolerance: 1e-5)
        guard !wires.isEmpty else { return nil }
        if ProcessInfo.processInfo.environment["CAM_DEBUG"] == "1", abs(z - 9.99) < 0.02 {
            for (i, wire) in wires.enumerated() {
                let pieces = wire.allEdgePolylines(deflection: 0.05)
                let all = pieces.flatMap { $0 }
                let b = all.isEmpty ? (minX: 0.0, maxX: 0.0, minY: 0.0, maxY: 0.0) : polygonBounds(all.map { CGPoint(x: $0.x, y: $0.y) })
                print("RAW i=\(i) edges=\(wire.orderedEdgeCount) polylines=\(pieces.count) pts=\(all.count) x[\(String(format: "%.1f", b.minX))..\(String(format: "%.1f", b.maxX))] y[\(String(format: "%.1f", b.minY))..\(String(format: "%.1f", b.maxY))]")
            }
        }

        var raw: [(wire: Wire, points: [CGPoint], area: Double)] = []
        for wire in wires {
            for p in polygons(of: wire) {
                guard p.count >= 3 else { continue }
                let a = abs(polygonArea(p))
                guard a > 0.01 else { continue }
                raw.append((wire, p, a))
            }
        }
        guard !raw.isEmpty else { return nil }

        var result: [CamLoop] = []
        for item in raw {
            var isHole = false
            for other in raw where other.area > item.area + 0.01 {
                if pointInPolygon(item.points[0], other.points) {
                    isHole = true
                    break
                }
            }
            result.append(CamLoop(
                wire: item.wire,
                points: item.points,
                area: item.area,
                isHole: isHole
            ))
        }
        if ProcessInfo.processInfo.environment["CAM_DEBUG"] == "1" {
            let desc = result.map { loop -> String in
                let b = polygonBounds(loop.points)
                return "\(loop.isHole ? "H" : "O") a=\(String(format: "%.1f", loop.area)) n=\(loop.points.count) x[\(String(format: "%.1f", b.minX))..\(String(format: "%.1f", b.maxX))] y[\(String(format: "%.1f", b.minY))..\(String(format: "%.1f", b.maxY))]"
            }.joined(separator: " | ")
            print("SECTION z=\(String(format: "%.2f", z)) wires=\(wires.count) \(desc)")
        }
        return result
    }

    private static func offset(_ loop: CamLoop, by distance: Double, expand: Bool) -> [CGPoint]? {
        let d = abs(distance)
        guard d > 0.01 else { return loop.points }
        // 用面做多环偏置：Wire.offset 只返回结果里的第一条 wire，
        // 当 OCCT 同时产生正确轮廓和包围盒边界线时会直接丢掉正确环。
        let offsetFace = Shape.face(from: loop.wire, planar: true)
        var plusWires = offsetFace?.multiOffsetWires(offsets: [d]) ?? []
        var minusWires = offsetFace?.multiOffsetWires(offsets: [-d]) ?? []
        if plusWires.isEmpty { plusWires = loop.wire.offset(by: d).map { [$0] } ?? [] }
        if minusWires.isEmpty { minusWires = loop.wire.offset(by: -d).map { [$0] } ?? [] }
        let plusLoops = plusWires.flatMap { polygons(of: $0) }
        let minusLoops = minusWires.flatMap { polygons(of: $0) }
        let baseArea = max(loop.area, 0.01)
        if ProcessInfo.processInfo.environment["CAM_DEBUG"] == "1", d < 10 {
            func b(_ loops: [[CGPoint]]) -> String {
                loops.map { p in
                    let x = polygonBounds(p)
                    return "n=\(p.count) a=\(String(format: "%.1f", abs(polygonArea(p)))) x[\(String(format: "%.1f", x.minX))..\(String(format: "%.1f", x.maxX))] y[\(String(format: "%.1f", x.minY))..\(String(format: "%.1f", x.maxY))]"
                }.joined(separator: "; ")
            }
            print("OFFSET baseA=\(String(format: "%.1f", loop.area)) d=\(String(format: "%.1f", d)) expand=\(expand) plus=\(b(plusLoops)) minus=\(b(minusLoops))")
        }

        let basePerimeter = polylineLength(loop.points)
        // 用面积增量挑选正确的偏置闭环，而不是简单取最大/最小。
        // OCCT 的 MakeOffset 偶尔会在结果里附带一条包围盒级别的平面边界线，
        // 若按“最大面积”取环，就会误选成一条几百毫米的空走圆。
        func pick(_ loops: [[CGPoint]], expanding: Bool) -> [CGPoint]? {
            let candidates = loops.filter { $0.count >= 3 && abs(polygonArea($0)) > 0.01 }
            guard !candidates.isEmpty else { return nil }
            let expected = expanding
                ? baseArea + basePerimeter * d + .pi * d * d
                : max(0.01, baseArea - basePerimeter * d + .pi * d * d)
            let side = candidates.filter {
                let a = abs(polygonArea($0))
                return expanding ? a > baseArea + 0.01 : (a < baseArea - 0.01)
            }
            let pool = side.isEmpty ? candidates : side
            return pool.min { abs(abs(polygonArea($0)) - expected) < abs(abs(polygonArea($1)) - expected) }
        }

        if expand {
            if let p = pick(plusLoops, expanding: true) { return p }
            if let p = pick(minusLoops, expanding: true) { return p }
        } else {
            if let p = pick(minusLoops, expanding: false) { return p }
            if let p = pick(plusLoops, expanding: false) { return p }
        }
        return nil
    }

    /// 将截面 wire 拆成若干条有序闭环/开环折线。
    ///
    /// `BRepTools_WireExplorer` 在部分 OCCT 偏移结果上返回 0 条边，旧实现退化为
    /// 逐边拼接，点序会乱跳，导致 G 代码里出现横穿工件的长直线。这里统一取
    /// 每条边的离散折线，再按端点最近邻串接，既能保留边序，也能处理反向边。
    private static func polygons(of wire: Wire) -> [[CGPoint]] {
        var pieces: [[CGPoint]] = []
        for polyline in wire.allEdgePolylines(deflection: 0.05) {
            var pts: [CGPoint] = []
            for p in polyline {
                let cg = CGPoint(x: p.x, y: p.y)
                if let last = pts.last, distance(last, cg) < 0.0005 { continue }
                pts.append(cg)
            }
            if pts.count >= 2 { pieces.append(pts) }
        }

        // 极少数 wire 无法转成 shape 时，退回 orderedEdge API。
        if pieces.isEmpty, wire.orderedEdgeCount > 0 {
            for i in 0..<wire.orderedEdgeCount {
                guard let raw = wire.orderedEdgePoints(at: i), raw.count >= 2 else { continue }
                pieces.append(raw.map { CGPoint(x: $0.x, y: $0.y) })
            }
        }

        var unused = pieces
        var loops: [[CGPoint]] = []
        while !unused.isEmpty {
            var chain = unused.removeFirst()
            var isClosed = chain.count > 2
                && distance(chain[0], chain[chain.count - 1]) < 0.05
            while !isClosed {
                guard let end = chain.last else { break }
                var best: (index: Int, distance: Double, reverse: Bool)?
                for (index, piece) in unused.enumerated() {
                    let dStart = distance(end, piece[0])
                    let dEnd = distance(end, piece[piece.count - 1])
                    let d = min(dStart, dEnd)
                    if best == nil || d < best!.distance {
                        best = (index, d, dEnd < dStart)
                    }
                }
                guard let best, best.distance < 0.5 else { break }
                let next = unused.remove(at: best.index)
                var ordered = best.reverse ? Array(next.reversed()) : next
                if let last = chain.last, !ordered.isEmpty, distance(last, ordered[0]) < 0.0005 {
                    ordered.removeFirst()
                }
                chain.append(contentsOf: ordered)
                isClosed = chain.count > 2
                    && distance(chain[0], chain[chain.count - 1]) < 0.05
            }

            // 首尾已经重合的闭环保留首点作为收刀点，让 G 代码真正闭合。
            if chain.count > 3, distance(chain[0], chain[chain.count - 1]) < 0.05 {
                chain[chain.count - 1] = chain[0]
            }
            let cleaned = dedupe(chain)
            if cleaned.count >= 3, abs(polygonArea(cleaned)) > 0.01 {
                loops.append(cleaned)
            }
        }
        return loops
    }

    private static func polygon(of wire: Wire) -> [CGPoint] {
        let loops = polygons(of: wire)
        return loops.max { abs(polygonArea($0)) < abs(polygonArea($1)) } ?? []
    }

    private static func appendPath(_ points: [CGPoint], z: Double, into segments: inout [TPSeg]) {
        let cleaned = dedupe(points)
        guard cleaned.count >= 2 else { return }
        let len = polylineLength(cleaned)
        guard len > 0.05 else { return }
        segments.append(TPSeg(cut: true, z: z, pts: cleaned, len: len))
    }

    // MARK: 顶面行切

    private static func faceSegments(
        outer: [CGPoint],
        obstacles: [[CGPoint]],
        z: Double,
        radius: Double,
        stepOver: Double
    ) -> [TPSeg] {
        guard outer.count >= 3 else { return [] }
        let inset = offsetPolygon(outer, by: -radius) ?? outer
        guard inset.count >= 3 else { return [] }
        let expandedObstacles = obstacles.map { offsetPolygon($0, by: radius) ?? $0 }
        let bounds = polygonBounds(inset)
        let step = max(stepOver, 0.5)
        var result: [TPSeg] = []
        var y = bounds.minY + step / 2
        var row = 0

        while y <= bounds.maxY {
            var intervals = scanlineIntervals(inset, y: y)
            for obstacle in expandedObstacles {
                let cut = scanlineIntervals(obstacle, y: y)
                if !cut.isEmpty { intervals = subtractIntervals(intervals, cut) }
            }
            for interval in intervals {
                let width = interval.1 - interval.0
                guard width > 0.4 else { continue }
                var pts = [CGPoint(x: interval.0, y: y), CGPoint(x: interval.1, y: y)]
                if row % 2 == 1 { pts.reverse() }
                let len = width
                result.append(TPSeg(cut: true, z: z, pts: pts, len: len))
            }
            y += step
            row += 1
        }
        return result
    }

    private static func offsetPolygon(_ points: [CGPoint], by offset: Double) -> [CGPoint]? {
        guard points.count >= 3 else { return nil }
        let d = abs(offset)
        guard d > 0.01 else { return points }
        let ring = points.count > 1 && hypot(points[0].x - points[points.count - 1].x, points[0].y - points[points.count - 1].y) < 0.01
            ? Array(points.dropLast())
            : points
        let wire = Wire.polygon(ring.map { SIMD2<Double>(Double($0.x), Double($0.y)) }, closed: true)
        guard let wire else { return nil }
        let face = Shape.face(from: wire, planar: true)
        var plusWires = face?.multiOffsetWires(offsets: [d]) ?? []
        var minusWires = face?.multiOffsetWires(offsets: [-d]) ?? []
        if plusWires.isEmpty { plusWires = wire.offset(by: d).map { [$0] } ?? [] }
        if minusWires.isEmpty { minusWires = wire.offset(by: -d).map { [$0] } ?? [] }
        let plusLoops = plusWires.flatMap { polygons(of: $0) }
        let minusLoops = minusWires.flatMap { polygons(of: $0) }
        let baseArea = max(abs(polygonArea(points)), 0.01)
        let basePerimeter = polylineLength(points)
        let expected = offset > 0
            ? baseArea + basePerimeter * d + .pi * d * d
            : max(0.01, baseArea - basePerimeter * d + .pi * d * d)
        let candidates = (offset > 0 ? plusLoops + minusLoops : minusLoops + plusLoops)
            .filter { $0.count >= 3 && abs(polygonArea($0)) > 0.01 }
        let side = candidates.filter {
            let a = abs(polygonArea($0))
            return offset > 0 ? a > baseArea + 0.01 : a < baseArea - 0.01
        }
        let pool = side.isEmpty ? candidates : side
        return pool.min { abs(abs(polygonArea($0)) - expected) < abs(abs(polygonArea($1)) - expected) }
    }

    // MARK: 多工序 G 代码

    private static func makeMultiGCode(
        runs: [True3DCAMRun],
        cam: True3DCAMParams,
        safeZ: Double,
        bounds: (min: SIMD3<Double>, max: SIMD3<Double>),
        stats: True3DCAMStats,
        warnings: [String]
    ) -> String {
        let macro = cam.programFormat == .macro
        var lines: [String] = []
        lines.append("%")
        if macro {
            lines.append("O\(cam.programNo) (MACROGEN TRUE3D MULTI-OP MACRO)")
            lines.append("( 由 MacroGen 真3D 工序树生成 · 宏变量版 )")
            lines.append("( 每序从 #100 起，+0/+1/+2 = 转速/切削进给/下刀进给；#1 = 安全高度 )")
            lines.append("( 改对应变量即可调该序参数，坐标仍按生成刀路固定输出 )")
        } else {
            lines.append("O\(cam.programNo) (MACROGEN TRUE3D MULTI-OP)")
            lines.append("( 由 MacroGen 真3D B-Rep 工序树生成 )")
        }
        lines.append("( 共 \(runs.count) 道工序，总刀路 \(fmt(stats.cutLength, 1))mm，层数 \(stats.layerCount) )")
        lines.append("( 毛坯范围 X\(fmt(bounds.min.x, 2))~\(fmt(bounds.max.x, 2)) Y\(fmt(bounds.min.y, 2))~\(fmt(bounds.max.y, 2)) Z\(fmt(bounds.min.z, 2))~\(fmt(bounds.max.z, 2)) )")
        if cam.stockCenterOrigin {
            lines.append("( 工件零点：毛坯中心 X0Y0 )")
        }
        if !warnings.isEmpty {
            lines.append("( 注意: \(warnings[0]) )")
        }
        if macro {
            lines.append("#1=\(fmt(safeZ, 1)) (安全高度)")
        }
        lines.append("G17 G21 G40 G49 G80 G90 G\(cam.coord)")
        if abs(cam.originX) > 1e-9 || abs(cam.originY) > 1e-9 {
            lines.append("G52 X\(fmt(cam.originX)) Y\(fmt(cam.originY)) (零点偏移)")
        }
        let programOffset = cam.stockCenterOrigin
            ? CGPoint(x: CGFloat((bounds.min.x + bounds.max.x) / 2), y: CGFloat((bounds.min.y + bounds.max.y) / 2))
            : CGPoint.zero

        for (index, run) in runs.enumerated() {
            let op = run.operation
            let macroBase = 100 + index * 10
            let zText = macro ? "#1" : fmt(safeZ, 1)
            let spindleText = macro ? "#\(macroBase)" : "\(op.spindle)"
            lines.append("( ---- 工序 \(index + 1): \(op.kind.rawValue) ---- )")
            lines.append("( 刀Ø\(fmt(op.toolDia, 2)) T\(op.toolNo) H\(op.hNo) D\(op.dNo) 每层\(fmt(op.stepDown, 2)) 行距\(fmt(op.stepOver, 2)) 转速\(op.spindle) 进给\(op.feed) )")
            if macro {
                lines.append("#\(macroBase)=\(op.spindle) (第\(index + 1)序 转速 S)")
                lines.append("#\(macroBase + 1)=\(op.feed) (第\(index + 1)序 切削 F)")
                lines.append("#\(macroBase + 2)=\(op.plungeFeed) (第\(index + 1)序 下刀 F)")
            }
            if let comp = run.comp {
                lines.append("( 刀补\(comp.side) D\(String(format: "%02d", comp.dNo)) · 真实轮廓精修 )")
            }
            lines.append("T\(op.toolNo) M06")
            lines.append("G43 H\(op.hNo) Z\(zText)")
            lines.append("M3 S\(spindleText)")
            if let coolant = op.coolant.code { lines.append(coolant) }
            if let comp = run.comp {
                appendCompLines(
                    comp,
                    feed: op.feed,
                    plungeFeed: op.plungeFeed,
                    safeZ: safeZ,
                    programOffset: programOffset,
                    macroStyle: macro,
                    macroBase: macroBase,
                    lines: &lines
                )
            } else {
                appendSegmentLines(
                    run.segments,
                    feed: op.feed,
                    plungeFeed: op.plungeFeed,
                    safeZ: safeZ,
                    programOffset: programOffset,
                    macroStyle: macro,
                    macroBase: macroBase,
                    lines: &lines
                )
            }
            lines.append(macro ? "G0 Z#1" : "G0 Z\(fmt(safeZ, 1))")
            lines.append("M5")
            lines.append("M9")
        }

        if abs(cam.originX) > 1e-9 || abs(cam.originY) > 1e-9 {
            lines.append("G52 X0 Y0")
        }
        lines.append("G28 G91 Z0")
        lines.append("G28 G91 Y0")
        lines.append("G90")
        lines.append("M30")
        lines.append("%")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func appendSegmentLines(
        _ segments: [TPSeg],
        feed: Int,
        plungeFeed: Int,
        safeZ: Double,
        programOffset: CGPoint = .zero,
        macroStyle: Bool = false,
        macroBase: Int = 100,
        lines: inout [String]
    ) {
        func gx(_ x: CGFloat) -> Double { Double(x) - Double(programOffset.x) }
        func gy(_ y: CGFloat) -> Double { Double(y) - Double(programOffset.y) }
        let safeText = macroStyle ? "#1" : fmt(safeZ, 1)
        let feedText = macroStyle ? "F#\(macroBase + 1)" : "F\(feed)"
        let plungeText = macroStyle ? "F#\(macroBase + 2)" : "F\(plungeFeed)"
        var lastPoint: CGPoint?
        var lastZ: Double?
        for seg in segments {
            guard let first = seg.pts.first, let last = seg.pts.last else { continue }
            let firstProgram = CGPoint(x: first.x - programOffset.x, y: first.y - programOffset.y)
            let lastProgram = CGPoint(x: last.x - programOffset.x, y: last.y - programOffset.y)
            let needsRapid: Bool
            if let lp = lastPoint, let lz = lastZ {
                needsRapid = distance(lp, firstProgram) > 0.01 || abs(lz - seg.z) > 0.001
            } else {
                needsRapid = true
            }
            if needsRapid {
                lines.append("G0 Z\(safeText)")
                lines.append("G0 X\(fmt(gx(first.x))) Y\(fmt(gy(first.y)))")
                lines.append("G1 Z\(fmt(seg.z)) \(plungeText)")
            }
            if let arc = fullCircleCommand(seg.pts, feedText: feedText, programOffset: programOffset) {
                lines.append(arc)
            } else {
                for p in seg.pts.dropFirst() {
                    lines.append("G1 X\(fmt(gx(p.x))) Y\(fmt(gy(p.y))) \(feedText)")
                }
            }
            lastPoint = lastProgram
            lastZ = seg.z
        }
    }

    /// 整圆识别：点列首尾闭合且所有点落在同一圆上时，输出 G2/G3 整圆。
    private static func fullCircleCommand(
        _ points: [CGPoint],
        feedText: String,
        programOffset: CGPoint
    ) -> String? {
        guard points.count >= 8, let first = points.first, let last = points.last else { return nil }
        guard distance(first, last) < 0.01 else { return nil }
        var unique = Array(points.dropLast())
        guard unique.count >= 6 else { return nil }
        let p0 = unique[0]
        let p1 = unique[unique.count / 3]
        let p2 = unique[unique.count * 2 / 3]
        let ax = Double(p0.x), ay = Double(p0.y)
        let bx = Double(p1.x), by = Double(p1.y)
        let cx = Double(p2.x), cy = Double(p2.y)
        let d = 2 * (ax * (by - cy) + bx * (cy - ay) + cx * (ay - by))
        guard abs(d) > 0.1 else { return nil }
        let ux = ((ax * ax + ay * ay) * (by - cy) + (bx * bx + by * by) * (cy - ay) + (cx * cx + cy * cy) * (ay - by)) / d
        let uy = ((ax * ax + ay * ay) * (cx - bx) + (bx * bx + by * by) * (ax - cx) + (cx * cx + cy * cy) * (bx - ax)) / d
        let r = hypot(ax - ux, ay - uy)
        guard r > 0.2 else { return nil }
        let tolerance = max(0.015, r * 0.004)
        for p in unique {
            if abs(hypot(Double(p.x) - ux, Double(p.y) - uy) - r) > tolerance { return nil }
        }
        var signedArea = 0.0
        for i in 0..<unique.count {
            let a = unique[i], b = unique[(i + 1) % unique.count]
            signedArea += Double(a.x) * Double(b.y) - Double(b.x) * Double(a.y)
        }
        let ccw = signedArea >= 0
        let cmd = ccw ? "G3" : "G2"
        let sx = Double(first.x) - Double(programOffset.x)
        let sy = Double(first.y) - Double(programOffset.y)
        let ix = ux - Double(first.x)
        let iy = uy - Double(first.y)
        return "\(cmd) X\(fmt(sx)) Y\(fmt(sy)) I\(fmt(ix)) J\(fmt(iy)) \(feedText)"
    }

    private static func appendCompLines(
        _ comp: True3DCompPass,
        feed: Int,
        plungeFeed: Int,
        safeZ: Double,
        programOffset: CGPoint,
        macroStyle: Bool = false,
        macroBase: Int = 100,
        lines: inout [String]
    ) {
        func gx(_ x: CGFloat) -> Double { Double(x) - Double(programOffset.x) }
        func gy(_ y: CGFloat) -> Double { Double(y) - Double(programOffset.y) }
        let side = comp.side == "G41" ? "G41" : "G42"
        let dText = String(format: "%02d", comp.dNo)
        let safeText = macroStyle ? "#1" : fmt(safeZ, 1)
        let feedText = macroStyle ? "F#\(macroBase + 1)" : "F\(feed)"
        let plungeText = macroStyle ? "F#\(macroBase + 2)" : "F\(plungeFeed)"
        lines.append("( \(side) D\(dText) · 刀补轮廓 · \(comp.contour.count) 点 )")
        lines.append("G0 Z\(safeText)")
        lines.append("G0 X\(fmt(gx(comp.lead.x))) Y\(fmt(gy(comp.lead.y)))")
        lines.append("G1 Z\(fmt(comp.z)) \(plungeText)")
        if let first = comp.contour.first {
            lines.append("\(side) D\(dText)")
            lines.append("G1 X\(fmt(gx(first.x))) Y\(fmt(gy(first.y))) \(feedText)")
            for p in comp.contour.dropFirst() {
                lines.append("G1 X\(fmt(gx(p.x))) Y\(fmt(gy(p.y))) \(feedText)")
            }
            if let last = comp.contour.last, distance(last, first) > 0.001 {
                lines.append("G1 X\(fmt(gx(first.x))) Y\(fmt(gy(first.y))) \(feedText)")
            }
        }
        lines.append("G40")
    }

    // MARK: G 代码

    private static func makeGCode(
        segments: [TPSeg],
        cam: True3DCAMParams,
        safeZ: Double,
        bounds: (min: SIMD3<Double>, max: SIMD3<Double>),
        stats: True3DCAMStats,
        warnings: [String]
    ) -> String {
        let macro = cam.programFormat == .macro
        var lines: [String] = []
        lines.append("%")
        if macro {
            lines.append("O\(cam.programNo) (MACROGEN TRUE3D MACRO)")
            lines.append("( 由 MacroGen 真3D 截面生成 · 宏变量版 )")
            lines.append("( #1=安全高度 #2=转速 #3=切削进给 #4=下刀进给 )")
        } else {
            lines.append("O\(cam.programNo) (MACROGEN TRUE3D)")
            lines.append("( 由 MacroGen 真3D B-Rep 截面生成 )")
        }
        lines.append("( 刀Ø\(fmt(cam.toolDia, 2))  每层\(fmt(cam.stepDown, 2))  行距\(fmt(cam.stepOver, 2)) )")
        lines.append("( 毛坯范围 X\(fmt(bounds.min.x, 2))~\(fmt(bounds.max.x, 2)) Y\(fmt(bounds.min.y, 2))~\(fmt(bounds.max.y, 2)) Z\(fmt(bounds.min.z, 2))~\(fmt(bounds.max.z, 2)) )")
        if cam.stockCenterOrigin {
            lines.append("( 工件零点：毛坯中心 X0Y0 )")
        }
        lines.append("( 刀路长度\(fmt(stats.cutLength, 1))mm  层数\(stats.layerCount)  上机前请仿真 )")
        if !warnings.isEmpty {
            lines.append("( 注意: \(warnings[0]) )")
        }
        if macro {
            lines.append("#1=\(fmt(safeZ, 1)) (安全高度)")
            lines.append("#2=\(cam.spindle) (转速 S)")
            lines.append("#3=\(cam.feed) (切削进给 F)")
            lines.append("#4=\(cam.plungeFeed) (下刀进给 F)")
        }
        lines.append("G17 G21 G40 G49 G80 G90 G\(cam.coord)")
        if abs(cam.originX) > 1e-9 || abs(cam.originY) > 1e-9 {
            lines.append("G52 X\(fmt(cam.originX)) Y\(fmt(cam.originY)) (零点偏移)")
        }
        let initialZ = macro ? "#1" : fmt(safeZ, 1)
        let initialS = macro ? "#2" : "\(cam.spindle)"
        lines.append("T\(cam.toolNo) M06")
        lines.append("G43 H\(cam.hNo) Z\(initialZ)")
        lines.append("M3 S\(initialS)")
        if let coolant = cam.coolant.code { lines.append(coolant) }

        let programOffset = cam.stockCenterOrigin
            ? CGPoint(x: CGFloat((bounds.min.x + bounds.max.x) / 2), y: CGFloat((bounds.min.y + bounds.max.y) / 2))
            : CGPoint.zero
        func gx(_ x: CGFloat) -> Double { Double(x) - Double(programOffset.x) }
        func gy(_ y: CGFloat) -> Double { Double(y) - Double(programOffset.y) }
        let safeText = macro ? "#1" : fmt(safeZ, 1)
        let feedText = macro ? "F#3" : "F\(cam.feed)"
        let plungeText = macro ? "F#4" : "F\(cam.plungeFeed)"

        var lastPoint: CGPoint?
        var lastZ: Double?
        for seg in segments {
            guard let first = seg.pts.first, let last = seg.pts.last else { continue }
            let firstProgram = CGPoint(x: first.x - programOffset.x, y: first.y - programOffset.y)
            let lastProgram = CGPoint(x: last.x - programOffset.x, y: last.y - programOffset.y)
            let needsRapid: Bool
            if let lp = lastPoint, let lz = lastZ {
                needsRapid = distance(lp, firstProgram) > 0.01 || abs(lz - seg.z) > 0.001
            } else {
                needsRapid = true
            }
            if needsRapid {
                lines.append("G0 Z\(safeText)")
                lines.append("G0 X\(fmt(gx(first.x))) Y\(fmt(gy(first.y)))")
                lines.append("G1 Z\(fmt(seg.z)) \(plungeText)")
            }
            for p in seg.pts.dropFirst() {
                lines.append("G1 X\(fmt(gx(p.x))) Y\(fmt(gy(p.y))) \(feedText)")
            }
            lastPoint = lastProgram
            lastZ = seg.z
        }

        lines.append(macro ? "G0 Z#1" : "G0 Z\(fmt(safeZ, 1))")
        if abs(cam.originX) > 1e-9 || abs(cam.originY) > 1e-9 {
            lines.append("G52 X0 Y0")
        }
        lines.append("M5")
        lines.append("M9")
        lines.append("G28 G91 Z0")
        lines.append("G28 G91 Y0")
        lines.append("G90")
        lines.append("M30")
        lines.append("%")
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: 几何工具

    private static func dedupe(_ points: [CGPoint]) -> [CGPoint] {
        var out: [CGPoint] = []
        for p in points {
            if let last = out.last, distance(last, p) < 0.0005 { continue }
            out.append(p)
        }
        // 不删除首尾重合点：闭环刀路需要最后一个点回到起点，G 代码才会闭合。
        return out
    }

    private static func polylineLength(_ points: [CGPoint]) -> Double {
        var total = 0.0
        for i in 1..<points.count { total += distance(points[i - 1], points[i]) }
        return total
    }

    private static func polygonArea(_ points: [CGPoint]) -> Double {
        guard points.count >= 3 else { return 0 }
        var sum = 0.0
        var j = points.count - 1
        for i in 0..<points.count {
            sum += (Double(points[j].x) * Double(points[i].y) - Double(points[i].x) * Double(points[j].y))
            j = i
        }
        return sum / 2
    }

    private static func pointInPolygon(_ p: CGPoint, _ polygon: [CGPoint]) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let a = polygon[i]
            let b = polygon[j]
            if ((Double(a.y) > Double(p.y)) != (Double(b.y) > Double(p.y))) {
                let x = (Double(b.x) - Double(a.x)) * (Double(p.y) - Double(a.y)) / (Double(b.y) - Double(a.y)) + Double(a.x)
                if Double(p.x) < x { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    private static func polygonBounds(_ points: [CGPoint]) -> (minX: Double, maxX: Double, minY: Double, maxY: Double) {
        var minX = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        for p in points {
            minX = min(minX, Double(p.x)); maxX = max(maxX, Double(p.x))
            minY = min(minY, Double(p.y)); maxY = max(maxY, Double(p.y))
        }
        return (minX, maxX, minY, maxY)
    }

    private static func scanlineIntervals(_ polygon: [CGPoint], y: Double) -> [(Double, Double)] {
        guard polygon.count >= 3 else { return [] }
        var xs: [Double] = []
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let a = polygon[i]
            let b = polygon[j]
            let ay = Double(a.y)
            let by = Double(b.y)
            if (ay > y) != (by > y) {
                let x = (Double(b.x) - Double(a.x)) * (y - ay) / (by - ay) + Double(a.x)
                xs.append(x)
            }
            j = i
        }
        xs.sort()
        var out: [(Double, Double)] = []
        var k = 0
        while k + 1 < xs.count {
            if xs[k + 1] - xs[k] > 0.01 { out.append((xs[k], xs[k + 1])) }
            k += 2
        }
        return out
    }

    private static func subtractIntervals(
        _ base: [(Double, Double)],
        _ cut: [(Double, Double)]
    ) -> [(Double, Double)] {
        var result: [(Double, Double)] = []
        for interval in base {
            var pieces = [interval]
            for c in cut {
                var next: [(Double, Double)] = []
                for piece in pieces {
                    if c.1 <= piece.0 || c.0 >= piece.1 {
                        next.append(piece)
                    } else {
                        if c.0 > piece.0 { next.append((piece.0, c.0)) }
                        if c.1 < piece.1 { next.append((c.1, piece.1)) }
                    }
                }
                pieces = next
            }
            result.append(contentsOf: pieces.filter { $0.1 - $0.0 > 0.01 })
        }
        return result
    }

    private static func circlePoints(cx: Double, cy: Double, r: Double) -> [CGPoint] {
        let n = max(24, Int(r * 8))
        return (0..<n).map { i in
            let a = Double(i) / Double(n) * 2 * .pi
            return CGPoint(x: cx + cos(a) * r, y: cy + sin(a) * r)
        }
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = Double(a.x - b.x)
        let dy = Double(a.y - b.y)
        return sqrt(dx * dx + dy * dy)
    }

    private static func fmt(_ v: Double, _ digits: Int = 3) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        f.minimumFractionDigits = digits
        f.maximumFractionDigits = digits
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }
}
