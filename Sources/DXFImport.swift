import Foundation
import CoreGraphics

/// 简易 DXF 2D 导入：LINE / LWPOLYLINE / CIRCLE / ARC。
/// 只读 XY 平面几何，不碰 3D 实体、不读 STEP；单位按 DXF 原值当 mm。
struct DXFImportResult {
    var spec: PartSpec
    var note: String
    var warnings: [String]
}

enum DXFImportError: LocalizedError {
    case empty
    case noGeometry
    case badText

    var errorDescription: String? {
        switch self {
        case .empty: return "DXF 文件是空的"
        case .noGeometry: return "没有读到 LINE / LWPOLYLINE / CIRCLE 几何"
        case .badText: return "DXF 不是可读的文本格式"
        }
    }
}

enum DXFImporter {
    private struct Entity {
        var type: String
        var pairs: [(Int, String)]

        func values(_ code: Int) -> [String] {
            pairs.filter { $0.0 == code }.map { $0.1 }
        }
        func first(_ code: Int) -> String? { values(code).first }
        func double(_ code: Int) -> Double? { first(code).flatMap(Double.init) }
        func int(_ code: Int) -> Int? { first(code).flatMap(Int.init) }
    }

    private struct Seg {
        var a: CGPoint
        var b: CGPoint
    }

    private struct Circle {
        var c: CGPoint
        var r: Double
    }

    static func parse(_ text: String, name: String) throws -> DXFImportResult {
        let raw = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DXFImportError.empty
        }
        var pairs: [(Int, String)] = []
        let lines = raw.components(separatedBy: "\n")
        var i = 0
        while i + 1 < lines.count {
            let codeText = lines[i].trimmingCharacters(in: .whitespaces)
            let value = lines[i + 1].trimmingCharacters(in: .whitespaces)
            if let code = Int(codeText) {
                pairs.append((code, value))
            }
            i += 2
        }
        guard !pairs.isEmpty else { throw DXFImportError.badText }

        var entities: [Entity] = []
        var current: Entity? = nil
        for pair in pairs {
            if pair.0 == 0 {
                if let c = current { entities.append(c) }
                current = Entity(type: pair.1.uppercased(), pairs: [])
            } else {
                current?.pairs.append(pair)
            }
        }
        if let c = current { entities.append(c) }

        var polylines: [[CGPoint]] = []
        var segments: [Seg] = []
        var circles: [Circle] = []
        var warnings: [String] = []

        for e in entities {
            switch e.type {
            case "LWPOLYLINE":
                let xs = e.values(10).compactMap(Double.init)
                let ys = e.values(20).compactMap(Double.init)
                var pts: [CGPoint] = []
                let n = min(xs.count, ys.count)
                for k in 0..<n { pts.append(CGPoint(x: CGFloat(xs[k]), y: CGFloat(ys[k]))) }
                if pts.count >= 2 { polylines.append(pts) }
            case "LINE":
                if let x1 = e.double(10), let y1 = e.double(20),
                   let x2 = e.double(11), let y2 = e.double(21) {
                    segments.append(Seg(a: CGPoint(x: CGFloat(x1), y: CGFloat(y1)), b: CGPoint(x: CGFloat(x2), y: CGFloat(y2))))
                }
            case "CIRCLE":
                if let x = e.double(10), let y = e.double(20), let r = e.double(40), r > 0.01 {
                    circles.append(Circle(c: CGPoint(x: CGFloat(x), y: CGFloat(y)), r: r))
                }
            case "ARC":
                if let x = e.double(10), let y = e.double(20), let r = e.double(40),
                   let a0 = e.double(50), let a1 = e.double(51), r > 0.01 {
                    let start = a0 * Double.pi / 180
                    let end = a1 * Double.pi / 180
                    var span = end - start
                    if span <= 0 { span += 2 * Double.pi }
                    let steps = max(6, Int(ceil(span / (Double.pi / 24))))
                    var pts: [CGPoint] = []
                    for k in 0...steps {
                        let a = start + span * Double(k) / Double(steps)
                        pts.append(CGPoint(x: CGFloat(x + r * cos(a)), y: CGFloat(y + r * sin(a))))
                    }
                    if pts.count >= 2 { polylines.append(pts) }
                }
            default:
                break
            }
        }

        // LINE 首尾相接成环；误差用 0.02 mm。
        func loopsFromLines(_ segs: [Seg]) -> [[CGPoint]] {
            var used = Array(repeating: false, count: segs.count)
            var loops: [[CGPoint]] = []
            for start in segs.indices where !used[start] {
                var pts: [CGPoint] = [segs[start].a, segs[start].b]
                used[start] = true
                var end = segs[start].b
                var guardCount = 0
                while guardCount < segs.count {
                    guardCount += 1
                    var found = false
                    for k in segs.indices where !used[k] {
                        let s = segs[k]
                        if hypot(s.a.x - end.x, s.a.y - end.y) <= 0.02 {
                            pts.append(s.b); used[k] = true; end = s.b; found = true; break
                        }
                        if hypot(s.b.x - end.x, s.b.y - end.y) <= 0.02 {
                            pts.append(s.a); used[k] = true; end = s.a; found = true; break
                        }
                    }
                    if !found { break }
                    if hypot(end.x - pts[0].x, end.y - pts[0].y) <= 0.02 { break }
                }
                if pts.count >= 3, hypot(end.x - pts[0].x, end.y - pts[0].y) <= 0.05 {
                    loops.append(pts)
                }
            }
            return loops
        }

        func area(_ pts: [CGPoint]) -> Double {
            guard pts.count >= 3 else { return 0 }
            var s = 0.0
            for i in pts.indices {
                let a = pts[i], b = pts[(i + 1) % pts.count]
                s += Double(a.x * b.y - b.x * a.y)
            }
            return abs(s) / 2
        }

        let lineLoops = loopsFromLines(segments)
        let candidates = polylines + lineLoops
        let closed = candidates.filter { $0.count >= 3 }
        let outer = closed.max { area($0) < area($1) }
        let outerCircle = circles.max { $0.r < $1.r }

        var spec = PartSpec()
        spec.projectName = name.isEmpty ? "DXF 导入" : name
        var usedCenter = CGPoint.zero
        var usedCircleIndex: Int? = nil

        if let outer, area(outer) > 0.01 {
            var pts = outer
            if pts.count > 1, hypot(pts.last!.x - pts.first!.x, pts.last!.y - pts.first!.y) < 0.02 {
                pts.removeLast()
            }
            let c = bboxCenter(pts)
            usedCenter = c
            spec.nodes = pts.map { p in
                ContourNode(x: Double(p.x) - Double(c.x), y: Double(p.y) - Double(c.y))
            }
            spec.template = .free
        } else if let circle = outerCircle {
            usedCenter = circle.c
            spec.template = .circle
            spec.circleD = circle.r * 2
            usedCircleIndex = circles.firstIndex { abs($0.c.x - circle.c.x) < 0.001 && abs($0.c.y - circle.c.y) < 0.001 }
        } else {
            throw DXFImportError.noGeometry
        }

        for (i, c) in circles.enumerated() where i != (usedCircleIndex ?? -1) {
            let x = Double(c.c.x - usedCenter.x)
            let y = Double(c.c.y - usedCenter.y)
            guard x.isFinite, y.isFinite else { continue }
            var f = PartFeat(kind: .hole, x: x, y: y, dia: c.r * 2, depth: spec.height)
            f.name = "DXF 圆孔 Ø\(String(format: "%.2f", c.r * 2))"
            f.holeKind = .through
            f.holeDepth = spec.height
            spec.feats.append(f)
        }

        if outer == nil, !circles.isEmpty {
            warnings.append("没有闭合多段线，使用最大圆作为外轮廓")
        }
        if candidates.isEmpty, circles.isEmpty {
            throw DXFImportError.noGeometry
        }
        if !segments.isEmpty, lineLoops.isEmpty {
            warnings.append("LINE 没有首尾闭合成环，只按最大闭合多段线/圆导入")
        }

        let note = "DXF：轮廓 \(spec.template == .free ? "\(spec.nodes.count) 点" : "Ø\(String(format: "%.2f", spec.circleD))")，圆孔 \(spec.feats.count) 个；单位按原值 mm"
        return DXFImportResult(spec: spec, note: note, warnings: warnings)
    }

    private static func bboxCenter(_ pts: [CGPoint]) -> CGPoint {
        guard let f = pts.first else { return .zero }
        var minX = f.x, maxX = f.x, minY = f.y, maxY = f.y
        for p in pts {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
    }
}
