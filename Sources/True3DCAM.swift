import Foundation
import CoreGraphics
import OCCTSwift

// MARK: - 3D 加工参数

struct True3DCAMParams: Equatable {
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

    var coord: Int = 54
    var originX: Double = 0
    var originY: Double = 0
    var programNo: Int = 1010

    var doRoughing: Bool = true
    var doFinishing: Bool = true
    var doClearInner: Bool = true
    var doFaceBaseTop: Bool = true
    var doFaceBossTop: Bool = true
    var doFacePocketBottom: Bool = true

    var toolRadius: Double { max(toolDia, 0.1) / 2 }
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
        let bottom = bounds.min.z - max(0, cam.stockExtraBottom)
        let top = bounds.max.z
        let baseTop = max(0, model.height)
        let bossTop = baseTop + (model.bossEnabled ? max(0, model.bossHeight) : 0)
        let pocketBottom = baseTop - (model.pocketEnabled ? max(0, model.pocketZ) : 0)
        let effectiveSafeZ = max(cam.safeZ, top + 2)

        var segments: [TPSeg] = []
        var warnings: [String] = []
        var sectionCount = 0

        // 1. 顶面 / 底面：用真实截面轮廓做面铣，不再靠 2.5D 外形推。
        if cam.doFaceBaseTop {
            if let loops = loopsAt(result.shape, z: baseTop - 0.02),
               let outer = loops.filter({ !$0.isHole }).max(by: { $0.area < $1.area }) {
                var obstacles = loops.filter(\.isHole).map(\.points)
                if model.bossEnabled {
                    obstacles.append(circlePoints(
                        cx: model.bossX,
                        cy: model.bossY,
                        r: model.bossDiameter / 2 + radius + 0.4
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

        if cam.doFaceBossTop, model.bossEnabled {
            if let loops = loopsAt(result.shape, z: bossTop - 0.02),
               let outer = loops.filter({ !$0.isHole }).max(by: { $0.area < $1.area }) {
                let faceSegs = faceSegments(
                    outer: outer.points,
                    obstacles: [],
                    z: bossTop,
                    radius: radius,
                    stepOver: cam.stepOver
                )
                segments.append(contentsOf: faceSegs)
            } else {
                warnings.append("凸台顶面截面为空，跳过凸台飞面")
            }
        }

        if cam.doFacePocketBottom, model.pocketEnabled {
            if let loops = loopsAt(result.shape, z: pocketBottom + 0.02),
               let inner = loops.filter(\.isHole).first(where: {
                   pointInPolygon(CGPoint(x: model.pocketX, y: model.pocketY), $0.points)
               }) ?? loops.filter(\.isHole).max(by: { $0.area < $1.area }) {
                let faceSegs = faceSegments(
                    outer: inner.points,
                    obstacles: [],
                    z: pocketBottom,
                    radius: radius,
                    stepOver: cam.stepOver
                )
                segments.append(contentsOf: faceSegs)
            }
        }

        // 2. 截面等高线：每个 Z 层由 OCCT 截出真实轮廓，再按刀半径偏置。
        var levels = Set<Double>()
        levels.insert(top - 0.01)
        levels.insert(bottom + 0.01)
        if baseTop > bottom + 0.02 { levels.insert(baseTop - 0.01) }
        if model.bossEnabled, bossTop > baseTop + 0.02 { levels.insert(bossTop - 0.01) }
        if model.pocketEnabled, pocketBottom > bottom + 0.02 { levels.insert(pocketBottom + 0.01) }

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
                    Int(floor((max(0, cam.stockMarginXY) - radius) / max(cam.stepOver, 0.1)))
                )
                if cam.doRoughing, maxRing > 0 {
                    for k in stride(from: maxRing, through: 1, by: -1) {
                        let distance = radius + Double(k) * cam.stepOver
                        if let poly = offset(outer, by: distance, expand: true) {
                            appendPath(poly, z: level, into: &segments)
                        }
                    }
                }
                if cam.doFinishing || (cam.doRoughing && maxRing == 0) {
                    if let poly = offset(outer, by: radius, expand: true) {
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
        if model.holeEnabled, radius * 2 >= model.holeDiameter {
            warnings.append("刀具直径不小于孔径，孔内清残无法完整加工")
        }
        if model.pocketEnabled, radius * 2 >= min(model.pocketWidth, model.pocketDepthXY) {
            warnings.append("刀具直径不小于方腔最小边，方腔内部无法完整清残")
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
            warnings: warnings
        )
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

    // MARK: G 代码

    private static func makeGCode(
        segments: [TPSeg],
        cam: True3DCAMParams,
        safeZ: Double,
        bounds: (min: SIMD3<Double>, max: SIMD3<Double>),
        stats: True3DCAMStats,
        warnings: [String]
    ) -> String {
        var lines: [String] = []
        lines.append("%")
        lines.append("O\(cam.programNo) (MACROGEN TRUE3D)")
        lines.append("( 由 MacroGen 真3D B-Rep 截面生成 )")
        lines.append("( 刀Ø\(fmt(cam.toolDia, 2))  每层\(fmt(cam.stepDown, 2))  行距\(fmt(cam.stepOver, 2)) )")
        lines.append("( 毛坯范围 X\(fmt(bounds.min.x, 2))~\(fmt(bounds.max.x, 2)) Y\(fmt(bounds.min.y, 2))~\(fmt(bounds.max.y, 2)) Z\(fmt(bounds.min.z, 2))~\(fmt(bounds.max.z, 2)) )")
        lines.append("( 刀路长度\(fmt(stats.cutLength, 1))mm  层数\(stats.layerCount)  上机前请仿真 )")
        if !warnings.isEmpty {
            lines.append("( 注意: \(warnings[0]) )")
        }
        lines.append("G17 G21 G40 G49 G80 G90 G\(cam.coord)")
        if abs(cam.originX) > 1e-9 || abs(cam.originY) > 1e-9 {
            lines.append("G52 X\(fmt(cam.originX)) Y\(fmt(cam.originY)) (零点偏移)")
        }
        lines.append("T\(cam.toolNo) M6")
        lines.append("G43 H\(cam.hNo) Z\(fmt(safeZ, 1))")
        lines.append("M3 S\(cam.spindle)")
        lines.append("M8")

        var lastPoint: CGPoint?
        var lastZ: Double?
        for seg in segments {
            guard let first = seg.pts.first, let last = seg.pts.last else { continue }
            let needsRapid: Bool
            if let lp = lastPoint, let lz = lastZ {
                needsRapid = distance(lp, first) > 0.01 || abs(lz - seg.z) > 0.001
            } else {
                needsRapid = true
            }
            if needsRapid {
                lines.append("G0 Z\(fmt(safeZ, 1))")
                lines.append("G0 X\(fmt(Double(first.x))) Y\(fmt(Double(first.y)))")
                lines.append("G1 Z\(fmt(seg.z)) F\(cam.plungeFeed)")
            }
            for p in seg.pts.dropFirst() {
                lines.append("G1 X\(fmt(Double(p.x))) Y\(fmt(Double(p.y))) F\(cam.feed)")
            }
            lastPoint = last
            lastZ = seg.z
        }

        lines.append("G0 Z\(fmt(safeZ, 1))")
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
