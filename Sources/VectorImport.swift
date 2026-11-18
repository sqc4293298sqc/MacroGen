import Foundation
import CoreGraphics

struct VectorCircle { var c: CGPoint; var r: Double }
struct VectorSegment { var a: CGPoint; var b: CGPoint }

enum VectorImportError: LocalizedError {
    case empty
    case badText
    case noGeometry

    var errorDescription: String? {
        switch self {
        case .empty: return "文件是空的"
        case .badText: return "读不出矢量文本"
        case .noGeometry: return "没有读到可用的轮廓/圆"
        }
    }
}

// MARK: - SVG

enum SVGImporter {
    static func parse(_ text: String, name: String) throws -> DXFImportResult {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VectorImportError.empty
        }
        let delegate = SVGDelegate()
        let parser = XMLParser(data: Data(text.utf8))
        parser.delegate = delegate
        guard parser.parse() else {
            throw VectorImportError.badText
        }
        var warnings = delegate.warnings
        warnings.append("SVG 的 Y 轴已翻成机床上方向 +Y；曲线按折线近似")
        return try VectorSpecBuilder.build(loops: delegate.loops,
                                           circles: delegate.circles,
                                           segments: delegate.segments,
                                           name: name,
                                           notePrefix: "SVG",
                                           warnings: warnings)
    }
}

private final class SVGDelegate: NSObject, XMLParserDelegate {
    var loops: [[CGPoint]] = []
    var circles: [VectorCircle] = []
    var segments: [VectorSegment] = []
    var warnings: [String] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        let tag = elementName.split(separator: ":").last.map(String.init)?.lowercased() ?? elementName.lowercased()
        switch tag {
        case "polygon", "polyline":
            let pts = parsePoints(attributeDict["points"] ?? "")
            guard pts.count >= 2 else { return }
            if tag == "polygon" || isClosed(pts) {
                loops.append(closeIfNeeded(pts))
            } else {
                appendSegments(pts)
            }
        case "circle":
            if let x = d(attributeDict["cx"]), let y = d(attributeDict["cy"]),
               let r = d(attributeDict["r"]), r > 0.01 {
                circles.append(VectorCircle(c: CGPoint(x: CGFloat(x), y: CGFloat(-y)), r: r))
            }
        case "rect":
            if let x = d(attributeDict["x"]), let y = d(attributeDict["y"]),
               let w = d(attributeDict["width"]), let h = d(attributeDict["height"]), w > 0, h > 0 {
                let x0 = CGFloat(x), x1 = CGFloat(x + w)
                let y0 = CGFloat(-y), y1 = CGFloat(-(y + h))
                let pts = [CGPoint(x: x0, y: y0), CGPoint(x: x1, y: y0),
                           CGPoint(x: x1, y: y1), CGPoint(x: x0, y: y1), CGPoint(x: x0, y: y0)]
                loops.append(pts)
            }
        case "line":
            if let x1 = d(attributeDict["x1"]), let y1 = d(attributeDict["y1"]),
               let x2 = d(attributeDict["x2"]), let y2 = d(attributeDict["y2"]) {
                segments.append(VectorSegment(a: CGPoint(x: CGFloat(x1), y: CGFloat(-y1)),
                                              b: CGPoint(x: CGFloat(x2), y: CGFloat(-y2))))
            }
        case "path":
            let result = parsePath(attributeDict["d"] ?? "")
            loops.append(contentsOf: result.loops)
            segments.append(contentsOf: result.segments)
            warnings.append(contentsOf: result.warnings)
        default:
            break
        }
    }

    private func d(_ s: String?) -> Double? { s.flatMap(Double.init) }

    private func parsePoints(_ text: String) -> [CGPoint] {
        let nums = numbers(text)
        guard nums.count >= 4 else { return [] }
        var pts: [CGPoint] = []
        var i = 0
        while i + 1 < nums.count {
            pts.append(CGPoint(x: CGFloat(nums[i]), y: CGFloat(-nums[i + 1])))
            i += 2
        }
        return pts
    }

    private func isClosed(_ pts: [CGPoint]) -> Bool {
        guard let a = pts.first, let b = pts.last else { return false }
        return hypot(a.x - b.x, a.y - b.y) < 0.02
    }

    private func closeIfNeeded(_ pts: [CGPoint]) -> [CGPoint] {
        guard let first = pts.first else { return pts }
        if let last = pts.last, hypot(first.x - last.x, first.y - last.y) < 0.02 { return pts }
        return pts + [first]
    }

    private func appendSegments(_ pts: [CGPoint]) {
        guard pts.count > 1 else { return }
        for i in 1..<pts.count {
            segments.append(VectorSegment(a: pts[i - 1], b: pts[i]))
        }
    }

    private func numbers(_ text: String) -> [Double] {
        var out: [Double] = []
        var cur = ""
        for ch in text {
            if ch.isNumber || ch == "." || ch == "-" || ch == "+" || ch == "e" || ch == "E" {
                if ch == "-" || ch == "+" {
                    if !cur.isEmpty, cur.last != "e", cur.last != "E" {
                        if let v = Double(cur) { out.append(v) }
                        cur = ""
                    }
                }
                cur.append(ch)
            } else {
                if !cur.isEmpty, let v = Double(cur) { out.append(v); cur = "" }
            }
        }
        if !cur.isEmpty, let v = Double(cur) { out.append(v) }
        return out
    }

    private func parsePath(_ d: String) -> (loops: [[CGPoint]], segments: [VectorSegment], warnings: [String]) {
        var tokens: [String] = []
        var cur = ""
        for ch in d {
            if ch.isLetter {
                if !cur.isEmpty { tokens.append(cur); cur = "" }
                tokens.append(String(ch))
            } else if ch == "-" || ch == "+" {
                if !cur.isEmpty, cur.last != "e", cur.last != "E" {
                    tokens.append(cur); cur = ""
                }
                cur.append(ch)
            } else if ch.isNumber || ch == "." || ch == "e" || ch == "E" {
                cur.append(ch)
            } else {
                if !cur.isEmpty { tokens.append(cur); cur = "" }
            }
        }
        if !cur.isEmpty { tokens.append(cur) }

        var loops: [[CGPoint]] = []
        var segments: [VectorSegment] = []
        var warnings: [String] = []
        var points: [CGPoint] = []
        var cursor = CGPoint.zero
        var subStart = CGPoint.zero
        var cmd: Character? = nil
        var i = 0

        func flush() {
            guard points.count >= 2 else { points = []; return }
            if let a = points.first, let b = points.last, hypot(a.x - b.x, a.y - b.y) < 0.02 {
                if points.count >= 4 { loops.append(points) }
            } else {
                for k in 1..<points.count { segments.append(VectorSegment(a: points[k - 1], b: points[k])) }
            }
            points = []
        }

        func take(_ n: Int) -> [Double]? {
            guard i + n <= tokens.count else { return nil }
            var vals: [Double] = []
            for k in 0..<n {
                guard let v = Double(tokens[i + k]) else { return nil }
                vals.append(v)
            }
            i += n
            return vals
        }

        while i < tokens.count {
            if tokens[i].count == 1, let c = tokens[i].first, c.isLetter {
                cmd = c
                i += 1
                if c == "Z" || c == "z" {
                    if !points.isEmpty {
                        points.append(subStart)
                        flush()
                        cursor = subStart
                    }
                }
                continue
            }
            guard let c = cmd else { i += 1; continue }
            let lower = Character(String(c).lowercased())
            let rel = c.isLowercase
            switch lower {
            case "m", "l":
                guard let v = take(2) else { i = tokens.count; break }
                let p = rel ? CGPoint(x: cursor.x + CGFloat(v[0]), y: cursor.y + CGFloat(v[1]))
                            : CGPoint(x: CGFloat(v[0]), y: CGFloat(v[1]))
                if lower == "m" {
                    flush()
                    subStart = p
                    points = [p]
                    cmd = rel ? Character("l") : Character("L")
                } else {
                    points.append(p)
                }
                cursor = p
            case "c":
                guard let v = take(6) else { i = tokens.count; break }
                let p1 = rel ? CGPoint(x: cursor.x + CGFloat(v[0]), y: cursor.y + CGFloat(v[1])) : CGPoint(x: CGFloat(v[0]), y: CGFloat(v[1]))
                let p2 = rel ? CGPoint(x: cursor.x + CGFloat(v[2]), y: cursor.y + CGFloat(v[3])) : CGPoint(x: CGFloat(v[2]), y: CGFloat(v[3]))
                let p3 = rel ? CGPoint(x: cursor.x + CGFloat(v[4]), y: cursor.y + CGFloat(v[5])) : CGPoint(x: CGFloat(v[4]), y: CGFloat(v[5]))
                let start = cursor
                for step in 1...10 {
                    let t = CGFloat(step) / 10
                    let u = 1 - t
                    let p = CGPoint(x: u*u*u*start.x + 3*u*u*t*p1.x + 3*u*t*t*p2.x + t*t*t*p3.x,
                                    y: u*u*u*start.y + 3*u*u*t*p1.y + 3*u*t*t*p2.y + t*t*t*p3.y)
                    points.append(p)
                }
                cursor = p3
            case "q":
                guard let v = take(4) else { i = tokens.count; break }
                let p1 = rel ? CGPoint(x: cursor.x + CGFloat(v[0]), y: cursor.y + CGFloat(v[1])) : CGPoint(x: CGFloat(v[0]), y: CGFloat(v[1]))
                let p2 = rel ? CGPoint(x: cursor.x + CGFloat(v[2]), y: cursor.y + CGFloat(v[3])) : CGPoint(x: CGFloat(v[2]), y: CGFloat(v[3]))
                let start = cursor
                for step in 1...8 {
                    let t = CGFloat(step) / 8
                    let u = 1 - t
                    points.append(CGPoint(x: u*u*start.x + 2*u*t*p1.x + t*t*p2.x,
                                          y: u*u*start.y + 2*u*t*p1.y + t*t*p2.y))
                }
                cursor = p2
            case "a":
                if let v = take(7) {
                    let p = rel ? CGPoint(x: cursor.x + CGFloat(v[5]), y: cursor.y + CGFloat(v[6]))
                                : CGPoint(x: CGFloat(v[5]), y: CGFloat(v[6]))
                    points.append(p)
                    cursor = p
                    warnings.append("SVG 圆弧 A 按直线近似")
                } else { i = tokens.count }
            case "h", "v":
                guard let v = take(1) else { i = tokens.count; break }
                let p = lower == "h"
                    ? (rel ? CGPoint(x: cursor.x + CGFloat(v[0]), y: cursor.y) : CGPoint(x: CGFloat(v[0]), y: cursor.y))
                    : (rel ? CGPoint(x: cursor.x, y: cursor.y + CGFloat(v[0])) : CGPoint(x: cursor.x, y: CGFloat(v[0])))
                points.append(p)
                cursor = p
            default:
                i += 1
            }
        }
        flush()
        return (loops, segments, warnings)
    }
}

// PLT / HPGL
enum PLTImporter {
    static func parse(_ text: String, name: String) throws -> DXFImportResult {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VectorImportError.empty
        }
        var warnings: [String] = []
        var loops: [[CGPoint]] = []
        var circles: [VectorCircle] = []
        var segments: [VectorSegment] = []
        var current = CGPoint.zero
        var rubberBand = false
        var relative = false
        var chain: [CGPoint] = []

        func flushChain(_ autoClose: Bool) {
            guard chain.count >= 2 else { chain = []; return }
            if autoClose, chain.count >= 3 {
                if let a = chain.first, let b = chain.last, hypot(a.x - b.x, a.y - b.y) > 0.02 {
                    chain.append(a)
                }
                loops.append(chain)
            } else {
                for i in 1..<chain.count { segments.append(VectorSegment(a: chain[i - 1], b: chain[i])) }
            }
            chain = []
        }

        for raw in text.split(separator: ";") {
            let cmd = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cmd.isEmpty else { continue }
            let upper = cmd.uppercased()
            if upper.hasPrefix("PA") { relative = false; continue }
            if upper.hasPrefix("PR") { relative = true; continue }
            if upper.hasPrefix("PU") || upper.hasPrefix("PD") {
                let down = upper.hasPrefix("PD")
                let nums = numbers(cmd)
                if down, rubberBand, !chain.isEmpty { flushChain(false) }
                if !down { flushChain(true) }
                var i = 0
                while i + 1 < nums.count {
                    let p = relative ? CGPoint(x: current.x + CGFloat(nums[i]), y: current.y + CGFloat(nums[i + 1]))
                                     : CGPoint(x: CGFloat(nums[i]), y: CGFloat(nums[i + 1]))
                    current = p
                    if down {
                        if chain.isEmpty { chain = [p] } else { chain.append(p) }
                    }
                    i += 2
                }
                if down { rubberBand = true }
                continue
            }
            if upper.hasPrefix("CI") {
                let nums = numbers(cmd)
                if let r = nums.first, r > 0.01 {
                    circles.append(VectorCircle(c: current, r: r))
                }
                continue
            }
            if upper.hasPrefix("AA") { warnings.append("PLT 圆弧 AA 未展开"); continue }
            if upper.hasPrefix("EA") {
                let nums = numbers(cmd)
                if nums.count >= 4 {
                    let x0 = CGFloat(nums[0]), y0 = CGFloat(nums[1])
                    let x1 = CGFloat(nums[2]), y1 = CGFloat(nums[3])
                    let pts = [CGPoint(x: x0, y: y0), CGPoint(x: x1, y: y0),
                               CGPoint(x: x1, y: y1), CGPoint(x: x0, y: y1), CGPoint(x: x0, y: y0)]
                    loops.append(pts)
                }
                continue
            }
        }
        flushChain(true)

        // HPGL 常见单位是 0.025 mm；坐标很大时自动按该单位换算。
        var maxSpan = 0.0
        for loop in loops { for p in loop { maxSpan = max(maxSpan, max(abs(Double(p.x)), abs(Double(p.y)))) } }
        for s in segments {
            maxSpan = max(maxSpan, max(max(abs(Double(s.a.x)), abs(Double(s.a.y))), max(abs(Double(s.b.x)), abs(Double(s.b.y)))))
        }
        for c in circles { maxSpan = max(maxSpan, max(abs(Double(c.c.x)), abs(Double(c.c.y)))) }
        let scale = maxSpan > 1000 ? 0.025 : 1.0
        if scale != 1 { warnings.append("PLT 坐标按 HPGL 0.025 mm/单位换算") }
        func scaled(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * CGFloat(scale), y: p.y * CGFloat(scale)) }
        loops = loops.map { $0.map(scaled) }
        segments = segments.map { VectorSegment(a: scaled($0.a), b: scaled($0.b)) }
        circles = circles.map { VectorCircle(c: scaled($0.c), r: $0.r * scale) }
        warnings.append("PLT 的连续笔画按闭合轮廓处理")
        return try VectorSpecBuilder.build(loops: loops, circles: circles, segments: segments,
                                           name: name, notePrefix: "PLT", warnings: warnings)
    }

    private static func numbers(_ text: String) -> [Double] {
        var out: [Double] = []
        var cur = ""
        for ch in text {
            if ch.isNumber || ch == "." || ch == "-" || ch == "+" {
                if ch == "-" || ch == "+" {
                    if !cur.isEmpty, let v = Double(cur) { out.append(v); cur = "" }
                }
                cur.append(ch)
            } else {
                if !cur.isEmpty, let v = Double(cur) { out.append(v); cur = "" }
            }
        }
        if !cur.isEmpty, let v = Double(cur) { out.append(v) }
        return out
    }
}

// MARK: - 统一成 PartSpec

private enum VectorSpecBuilder {
    static func build(loops: [[CGPoint]], circles: [VectorCircle], segments: [VectorSegment],
                      name: String, notePrefix: String, warnings: [String]) throws -> DXFImportResult {
        var warnings = warnings
        func area(_ pts: [CGPoint]) -> Double {
            guard pts.count >= 3 else { return 0 }
            var s = 0.0
            for i in pts.indices {
                let a = pts[i], b = pts[(i + 1) % pts.count]
                s += Double(a.x * b.y - b.x * a.y)
            }
            return abs(s) / 2
        }
        let closed = loops.filter { $0.count >= 3 && area($0) > 0.01 }
        let outerLoop = closed.max { area($0) < area($1) }
        let outerCircle = circles.max { $0.r < $1.r }

        var spec = PartSpec()
        spec.projectName = name.isEmpty ? "\(notePrefix) 导入" : name
        var center = CGPoint.zero
        var outerLoopIndex: Int? = nil
        var usedCircleIndex: Int? = nil

        if let outerLoop, let oi = closed.firstIndex(where: { $0.count == outerLoop.count && area($0) == area(outerLoop) }) {
            outerLoopIndex = oi
            center = bboxCenter(outerLoop)
            var pts = outerLoop
            if pts.count > 1, hypot(pts.last!.x - pts.first!.x, pts.last!.y - pts.first!.y) < 0.02 {
                pts.removeLast()
            }
            spec.nodes = pts.map { ContourNode(x: Double($0.x - center.x), y: Double($0.y - center.y)) }
            spec.template = .free
        } else if let outerCircle {
            center = outerCircle.c
            usedCircleIndex = circles.firstIndex { abs($0.c.x - outerCircle.c.x) < 0.001 && abs($0.c.y - outerCircle.c.y) < 0.001 }
            spec.template = .circle
            spec.circleD = outerCircle.r * 2
        } else if !segments.isEmpty {
            var pts: [CGPoint] = []
            for s in segments { pts.append(s.a); pts.append(s.b) }
            let bb = bbox(pts)
            center = CGPoint(x: (bb.minX + bb.maxX) / 2, y: (bb.minY + bb.maxY) / 2)
            let corners = [CGPoint(x: bb.minX, y: bb.minY), CGPoint(x: bb.maxX, y: bb.minY),
                           CGPoint(x: bb.maxX, y: bb.maxY), CGPoint(x: bb.minX, y: bb.maxY)]
            spec.nodes = corners.map { ContourNode(x: Double($0.x - center.x), y: Double($0.y - center.y)) }
            spec.template = .free
            warnings.append("没有闭合轮廓，按所有线段外接矩形作为外形")
        } else {
            throw VectorImportError.noGeometry
        }

        for (i, c) in circles.enumerated() where i != (usedCircleIndex ?? -1) {
            let x = Double(c.c.x - center.x)
            let y = Double(c.c.y - center.y)
            var f = PartFeat(kind: .hole, x: x, y: y, dia: c.r * 2, depth: spec.height)
            f.name = "导入圆孔 Ø\(String(format: "%.2f", c.r * 2))"
            f.holeKind = .through
            f.holeDepth = spec.height
            spec.feats.append(f)
        }
        // 较小的闭合环作为内轮廓（可当孔/腔继续加工）
        for (i, loop) in closed.enumerated() where i != (outerLoopIndex ?? -1) {
            var l = SketchLoop()
            l.name = "导入内轮廓 \(i + 1)"
            l.template = .free
            let c = bboxCenter(loop)
            l.cx = Double(c.x - center.x)
            l.cy = Double(c.y - center.y)
            l.nodes = loop.map { ContourNode(x: Double($0.x - c.x), y: Double($0.y - c.y)) }
            l.through = true
            l.depth = spec.height
            spec.innerLoops.append(l)
        }

        let note = "\(notePrefix)：轮廓 \(spec.template == .free ? "\(spec.nodes.count) 点" : "Ø\(String(format: "%.2f", spec.circleD))")，圆孔 \(spec.feats.count) 个，内轮廓 \(spec.innerLoops.count) 个；单位 mm"
        return DXFImportResult(spec: spec, note: note, warnings: warnings)
    }

    private static func bboxCenter(_ pts: [CGPoint]) -> CGPoint {
        let b = bbox(pts)
        return CGPoint(x: (b.minX + b.maxX) / 2, y: (b.minY + b.maxY) / 2)
    }

    private static func bbox(_ pts: [CGPoint]) -> (minX: CGFloat, minY: CGFloat, maxX: CGFloat, maxY: CGFloat) {
        guard let f = pts.first else { return (0, 0, 0, 0) }
        var minX = f.x, maxX = f.x, minY = f.y, maxY = f.y
        for p in pts {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return (minX, minY, maxX, maxY)
    }
}
