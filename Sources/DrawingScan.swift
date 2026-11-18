import SwiftUI
import UIKit
import Vision
import simd

// MARK: - 图纸识别结果

enum ScanAnnotationKind {
    case outer
    case hole
    case ocr
    case note
}

struct ScanAnnotation: Identifiable {
    let id = UUID()
    var text: String
    /// Vision 归一化坐标：原点在左下角
    var rect: CGRect
    var kind: ScanAnnotationKind
    /// 对应的特征 id，用于预览里删除误识别孔后同步隐藏标注
    var featID: UUID? = nil
}

struct DrawingScanResult: Identifiable {
    let id = UUID()
    var image: UIImage
    var spec: PartSpec
    /// 识别出的外轮廓（归一化坐标，原点左下角）
    var outline: [CGPoint]
    var annotations: [ScanAnnotation]
    var summary: String
    var scaleNote: String
    var warnings: [String]
    var confidence: Double
}

enum DrawingScanError: LocalizedError {
    case badImage
    case visionFailed(String)
    case noGeometry

    var errorDescription: String? {
        switch self {
        case .badImage:
            return "这张图片读不出来，换一张清楚点的"
        case .visionFailed(let s):
            return "图纸识别失败：\(s)"
        case .noGeometry:
            return "没识别到零件外轮廓，尽量正对图纸、线条清楚一点再拍"
        }
    }
}

// MARK: - 识别器

enum DrawingScanner {
    static func scan(_ image: UIImage) async throws -> DrawingScanResult {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<DrawingScanResult, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try scanSync(image)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private struct OcrFacts {
        var pair: (Double, Double)?
        var numbers: [Double] = []
        var holeDias: [Double] = []
        var holeLabels: [(dia: Double, rect: CGRect)] = []
        var thickness: Double?
        var annotations: [ScanAnnotation] = []
    }

    private struct ScanTextLine {
        var text: String
        var rect: CGRect
        var confidence: CGFloat
    }

    private static func scanSync(_ image: UIImage) throws -> DrawingScanResult {
        let prepared = prepare(image, maxDimension: 2000)
        guard let cg = prepared.cgImage else { throw DrawingScanError.badImage }

        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])

        // 尺寸文字很小，整图一次 OCR 容易漏；全图 + 2×2 重叠分块各跑一遍，再把坐标映射回整图。
        let textLines = collectTextLines(image)

        let contourRequest = VNDetectContoursRequest()
        contourRequest.contrastAdjustment = 2.1
        contourRequest.detectsDarkOnLight = true
        contourRequest.maximumImageDimension = 2000

        let rectRequest = VNDetectRectanglesRequest()
        rectRequest.minimumConfidence = 0.55
        rectRequest.minimumSize = 0.12
        rectRequest.minimumAspectRatio = 0.2
        rectRequest.maximumObservations = 5

        do {
            try handler.perform([contourRequest, rectRequest])
        } catch {
            throw DrawingScanError.visionFailed(error.localizedDescription)
        }

        let contours = (contourRequest.results as? [VNContoursObservation]) ?? []
        let rectangles = (rectRequest.results as? [VNRectangleObservation]) ?? []

        let ocr = readOcr(textLines)
        let contourInfo = bestOuterContour(contours)
        let rectInfo = bestOuterRectangle(rectangles)

        let rawOutline: [CGPoint]
        let outerContour: VNContour?
        var geometryFallback = false

        if let contourInfo = contourInfo {
            rawOutline = contourInfo.points
            outerContour = contourInfo.contour
        } else if let rectInfo = rectInfo {
            rawOutline = rectInfo
            outerContour = nil
        } else {
            rawOutline = [
                CGPoint(x: 0.10, y: 0.10),
                CGPoint(x: 0.90, y: 0.10),
                CGPoint(x: 0.90, y: 0.90),
                CGPoint(x: 0.10, y: 0.90)
            ]
            outerContour = nil
            geometryFallback = true
        }

        let rawBox = bounds(rawOutline)
        guard rawBox.width > 0.02, rawBox.height > 0.02 else { throw DrawingScanError.noGeometry }

        let aspect = Double(rawBox.height / rawBox.width)
        let chosen = chooseOuterSize(ocr: ocr, aspect: aspect)
        let length = chosen.0
        let width = chosen.1
        let height = max(1, ocr.thickness ?? 10)

        let outline = simplify(rawOutline, eps: 0.0045)
        let isRect = looksLikeRectangle(outline)

        var spec = PartSpec()
        spec.height = height
        spec.topStock = 1
        spec.rectR = 0
        spec.coord = 54
        spec.originX = 0
        spec.originY = 0

        if isRect {
            spec.template = .rect
            spec.rectL = length
            spec.rectW = width
            spec.nodes = []
        } else {
            spec.template = .free
            spec.rectL = length
            spec.rectW = width
            var nodes = outline.map { p -> ContourNode in
                let x = (Double(p.x) - Double(rawBox.midX)) * (length / Double(rawBox.width))
                let y = (Double(p.y) - Double(rawBox.midY)) * (width / Double(rawBox.height))
                return ContourNode(x: x, y: y, kind: .line, r: 1)
            }
            if nodes.count > 2,
               hypot(nodes[0].x - nodes[nodes.count - 1].x, nodes[0].y - nodes[nodes.count - 1].y) < 0.2 {
                nodes.removeLast()
            }
            if signedArea(outline) < 0 { nodes.reverse() }
            spec.nodes = nodes
        }

        var annotations: [ScanAnnotation] = []
        let outerY = max(0.015, rawBox.minY - 0.035)
        annotations.append(ScanAnnotation(
            text: "长 \(ncf(length)) mm",
            rect: CGRect(x: rawBox.minX, y: outerY, width: rawBox.width, height: 0.04),
            kind: .outer))
        annotations.append(ScanAnnotation(
            text: "宽 \(ncf(width)) mm",
            rect: CGRect(x: max(0.01, rawBox.minX - 0.01), y: rawBox.midY, width: 0.055, height: 0.045),
            kind: .outer))
        annotations.append(ScanAnnotation(
            text: "厚 \(ncf(height)) mm",
            rect: CGRect(x: rawBox.midX, y: max(0.015, rawBox.minY - 0.075), width: 0.24, height: 0.04),
            kind: .note))

        let holes = detectHoles(
            contours: contours, outer: outerContour, outerBox: rawBox,
            length: length, width: width, height: height, ocr: ocr)
        spec.feats = holes.feats
        annotations.append(contentsOf: holes.annotations)
        annotations.append(contentsOf: ocr.annotations)

        let warnings: [String] = {
            var w: [String] = []
            if geometryFallback { w.append("没识别到闭合轮廓，先按矩形生成，请核对外形") }
            let touchesCropEdge = rawBox.minX < 0.015 || rawBox.maxX > 0.985
                || rawBox.minY < 0.015 || rawBox.maxY > 0.985
            if touchesCropEdge { w.append("外轮廓贴着裁剪边，可能把图框/视图边框当成零件；框选时留一点边") }
            if ocr.pair == nil { w.append(ocr.numbers.isEmpty ? "没读到尺寸，按 100 mm 估算，请核对" : "只读到一个尺寸，另一个按图比例推算") }
            if ocr.thickness == nil { w.append("厚度没读到，按 10 mm 生成，请核对") }
            if holes.feats.isEmpty && !ocr.holeDias.isEmpty { w.append("读到孔径标注，但没识别到圆的闭合轮廓，孔请手动加") }
            if holes.feats.contains(where: { $0.kind == .rectPocket }) {
                w.append("识别到槽/方腔，按矩形腔近似；圆角/真实轮廓请在草图核对")
            }
            if holes.feats.count >= 6 { w.append("识别到较多孔，可能是多视图/尺寸文字误判；请逐个核对，错的可在草图里删") }
            if ocr.pair == nil && ocr.numbers.count >= 8 { w.append("图上尺寸很多，自动选的不一定是总尺寸；请直接改长/宽核对") }
            w.append("照片尽量正对图纸拍，斜拍/反光/手写标注会影响精度")
            return w
        }()

        let holeCount = holes.feats.filter { $0.kind == .hole }.count
        let pocketCount = holes.feats.count - holeCount
        let summary = "外形 \(ncf(length)) × \(ncf(width)) mm · 厚 \(ncf(height)) mm · 孔 \(holeCount) 个"
            + (pocketCount > 0 ? " · 槽/腔 \(pocketCount) 个" : "")
        let confidence = min(0.96, 0.42
            + (outerContour == nil ? 0 : 0.25)
            + (ocr.pair == nil ? 0 : 0.16)
            + (holes.feats.isEmpty ? 0 : 0.08)
            + (holes.feats.count >= 6 ? -0.10 : 0)
            + (geometryFallback ? -0.15 : 0))

        return DrawingScanResult(
            image: prepared,
            spec: spec,
            outline: outline,
            annotations: annotations,
            summary: summary,
            scaleNote: chosen.2,
            warnings: warnings,
            confidence: confidence)
    }

    // MARK: - 轮廓

    private static func points(of contour: VNContour) -> [CGPoint] {
        contour.normalizedPoints.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
    }

    private static func bestOuterContour(_ observations: [VNContoursObservation]) -> (contour: VNContour, points: [CGPoint])? {
        guard let observation = observations.first else { return nil }
        var best: (VNContour, [CGPoint], CGFloat)?
        for c in observation.topLevelContours {
            let p = points(of: c)
            guard p.count > 2 else { continue }
            let b = bounds(p)
            let a = abs(signedArea(p))
            guard b.width > 0.12, b.height > 0.12, a > 0.025 else { continue }
            if a > 0.82 { continue }
            // 贴满裁剪框的通常不是零件轮廓，而是图纸边框/视图框
            let touchesEdges = b.minX < 0.015 && b.maxX > 0.985 && b.minY < 0.015 && b.maxY > 0.985
            if touchesEdges && a > 0.65 { continue }
            if best == nil || a > best!.2 {
                best = (c, p, a)
            }
        }
        if best == nil {
            for c in observation.topLevelContours {
                let p = points(of: c)
                let a = abs(signedArea(p))
                if a > 0.02 && a < 0.96 && (best == nil || a > best!.2) {
                    best = (c, p, a)
                }
            }
        }
        guard let found = best else { return nil }
        return (found.0, found.1)
    }

    private static func bestOuterRectangle(_ observations: [VNRectangleObservation]) -> [CGPoint]? {
        var best: (VNRectangleObservation, Double)?
        for r in observations {
            let a = Double(r.boundingBox.width * r.boundingBox.height)
            guard a > 0.05, a < 0.90 else { continue }
            if best == nil || a > best!.1 { best = (r, a) }
        }
        guard let r = best?.0 else { return nil }
        return [
            CGPoint(x: r.topLeft.x, y: r.topLeft.y),
            CGPoint(x: r.topRight.x, y: r.topRight.y),
            CGPoint(x: r.bottomRight.x, y: r.bottomRight.y),
            CGPoint(x: r.bottomLeft.x, y: r.bottomLeft.y)
        ]
    }

    private static func simplify(_ points: [CGPoint], eps: CGFloat) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var list = points
        if let first = list.first, let last = list.last,
           hypot(first.x - last.x, first.y - last.y) < 0.002 {
            list.removeLast()
        }
        // Ramer–Douglas–Peucker，归一化坐标下工作
        func rdp(_ pts: [CGPoint], _ epsilon: CGFloat) -> [CGPoint] {
            guard pts.count > 2 else { return pts }
            var maxD: CGFloat = 0
            var index = 0
            let a = pts[0], b = pts[pts.count - 1]
            let dx = b.x - a.x, dy = b.y - a.y
            let len = max(hypot(dx, dy), 0.000001)
            for i in 1..<(pts.count - 1) {
                let d = abs(dy * (pts[i].x - a.x) - dx * (pts[i].y - a.y)) / len
                if d > maxD { maxD = d; index = i }
            }
            if maxD > epsilon {
                let left = rdp(Array(pts[0...index]), epsilon)
                let right = rdp(Array(pts[index...]), epsilon)
                return Array(left.dropLast()) + right
            }
            return [a, b]
        }
        var out = rdp(list, eps)
        if out.count < 3 { out = list }
        if out.count > 80 { out = Array(out.prefix(80)) }
        return out
    }

    private static func looksLikeRectangle(_ points: [CGPoint]) -> Bool {
        guard points.count == 4 else { return false }
        let b = bounds(points)
        guard b.width > 0.05, b.height > 0.05 else { return false }
        var maxTurn: CGFloat = 0
        for i in points.indices {
            let prev = points[(i + points.count - 1) % points.count]
            let cur = points[i]
            let next = points[(i + 1) % points.count]
            let a = CGPoint(x: prev.x - cur.x, y: prev.y - cur.y)
            let c = CGPoint(x: next.x - cur.x, y: next.y - cur.y)
            let la = max(hypot(a.x, a.y), 0.000001)
            let lc = max(hypot(c.x, c.y), 0.000001)
            let dot = (a.x * c.x + a.y * c.y) / (la * lc)
            let angle = acos(max(-1, min(1, dot))) * 180 / .pi
            maxTurn = max(maxTurn, abs(angle - 90))
        }
        return maxTurn < 18
    }

    private static func signedArea(_ p: [CGPoint]) -> CGFloat {
        guard p.count > 2 else { return 0 }
        var s: CGFloat = 0
        for i in p.indices {
            let a = p[i], b = p[(i + 1) % p.count]
            s += a.x * b.y - b.x * a.y
        }
        return s / 2
    }

    private static func bounds(_ p: [CGPoint]) -> CGRect {
        guard !p.isEmpty else { return .zero }
        let minX = p.reduce(CGFloat.infinity) { min($0, $1.x) }
        let maxX = p.reduce(-CGFloat.infinity) { max($0, $1.x) }
        let minY = p.reduce(CGFloat.infinity) { min($0, $1.y) }
        let maxY = p.reduce(-CGFloat.infinity) { max($0, $1.y) }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // MARK: - OCR

    /// 全图 + 2×2 重叠分块，专门救小尺寸文字。
    private static func collectTextLines(_ image: UIImage) -> [ScanTextLine] {
        let oriented = image.fixedOrientation()
        guard let cg = oriented.cgImage else { return [] }
        let full = prepare(oriented, maxDimension: 2000)
        guard let fullCG = full.cgImage else { return [] }

        var lines = textLines(from: fullCG,
                              in: CGRect(x: 0, y: 0, width: 1, height: 1),
                              minHeight: 0.006)

        // 12% 重叠，避免尺寸文字正好落在切缝上被切掉。
        let tiles: [CGRect] = [
            CGRect(x: 0, y: 0, width: 0.56, height: 0.56),
            CGRect(x: 0.44, y: 0, width: 0.56, height: 0.56),
            CGRect(x: 0, y: 0.44, width: 0.56, height: 0.56),
            CGRect(x: 0.44, y: 0.44, width: 0.56, height: 0.56)
        ]
        let W = CGFloat(cg.width), H = CGFloat(cg.height)
        for tile in tiles {
            let pixel = CGRect(x: tile.minX * W, y: tile.minY * H,
                               width: tile.width * W, height: tile.height * H).integral
            guard pixel.width > 8, pixel.height > 8,
                  let crop = cg.cropping(to: pixel) else { continue }
            let tileImage = prepare(UIImage(cgImage: crop), maxDimension: 1600)
            guard let tileCG = tileImage.cgImage else { continue }
            lines.append(contentsOf: textLines(from: tileCG, in: tile, minHeight: 0.004))
        }
        return dedupeText(lines)
    }

    private static func textLines(from cg: CGImage, in base: CGRect, minHeight: CGFloat) -> [ScanTextLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.minimumTextHeight = Float(minHeight)

        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
        return observations.compactMap { obs -> ScanTextLine? in
            guard let candidate = obs.topCandidates(1).first else { return nil }
            let b = obs.boundingBox
            // 分块坐标（Vision 原点左下）→ 整图归一化坐标（原点左下）
            let rect = CGRect(
                x: base.minX + b.minX * base.width,
                y: (1 - base.maxY) + b.minY * base.height,
                width: b.width * base.width,
                height: b.height * base.height)
            return ScanTextLine(text: candidate.string, rect: rect, confidence: candidate.confidence)
        }
    }

    private static func dedupeText(_ lines: [ScanTextLine]) -> [ScanTextLine] {
        var out: [ScanTextLine] = []
        for line in lines {
            let text = normalizeText(line.text)
            guard !text.isEmpty else { continue }
            if let i = out.firstIndex(where: {
                normalizeText($0.text) == text && iou($0.rect, line.rect) > 0.55
            }) {
                if line.confidence > out[i].confidence { out[i] = line }
            } else {
                out.append(line)
            }
        }
        return out
    }

    private static func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let inter = a.intersection(b)
        guard !inter.isNull, inter.width > 0, inter.height > 0 else { return 0 }
        let union = a.width * a.height + b.width * b.height - inter.width * inter.height
        guard union > 0.000001 else { return 0 }
        return inter.width * inter.height / union
    }

    private static func readOcr(_ lines: [ScanTextLine]) -> OcrFacts {
        var facts = OcrFacts()
        for (index, line) in lines.enumerated() {
            let raw = normalizeText(line.text)
            guard !raw.isEmpty else { continue }

            if let pair = matchPair(raw) {
                if pair.0 > 1, pair.1 > 1, pair.0 < 2000, pair.1 < 2000 {
                    if facts.pair == nil || pair.0 * pair.1 > facts.pair!.0 * facts.pair!.1 {
                        facts.pair = pair
                    }
                }
            }
            if let dia = matchOne(raw, pattern: "[ØøΦφ∅]\\s*([0-9]+(?:\\.[0-9]+)?)") {
                if dia > 0.2 {
                    facts.holeDias.append(dia)
                    facts.holeLabels.append((dia, line.rect))
                }
            }
            if let t = matchOne(raw, pattern: "(?:厚(?:度)?|T|δ)\\s*[=:：]?\\s*([0-9]+(?:\\.[0-9]+)?)") {
                facts.thickness = t
            }
            let onlyFeatureText = (raw.contains("Ø") || raw.contains("厚") || raw.hasPrefix("R"))
                && raw.range(of: "×") == nil && allNumbers(raw).count <= 1
            if !onlyFeatureText {
                for n in allNumbers(raw) {
                    if n > 1 && n < 3000 { facts.numbers.append(n) }
                }
            }

            if index < 80 && (raw.contains("Ø") || raw.contains("厚") || raw.contains("R")
                || raw.range(of: "[0-9]", options: .regularExpression) != nil) {
                facts.annotations.append(ScanAnnotation(
                    text: raw,
                    rect: line.rect,
                    kind: .ocr))
            }
        }
        facts.numbers.sort(by: >)
        return facts
    }

    private static func chooseOuterSize(ocr: OcrFacts, aspect: Double) -> (Double, Double, String) {
        if let p = ocr.pair {
            var l = p.0, w = p.1
            if aspect > 1.15 && l < w { swap(&l, &w) }
            if aspect < 0.87 && l > w { swap(&l, &w) }
            return (l, w, "尺寸取自图纸标注 L×W")
        }
        let nums = ocr.numbers.filter { $0 > 2 && $0 < 3000 }
        if let l = nums.first {
            var w = l * aspect
            if nums.count > 1 {
                let second = nums[1]
                if second > 2 && second < l * 1.05 && second > l * 0.25 {
                    w = second
                }
            }
            if !w.isFinite || w <= 0.1 { w = l * max(0.2, min(5, aspect)) }
            return (l, w, nums.count > 1 ? "尺寸取自图纸数字标注" : "只读到一个尺寸，宽度按图比例推算")
        }
        let l = 100.0
        let w = max(5, l * max(0.2, min(5, aspect)))
        return (l, w, "没读到尺寸，按长 100 mm 估算")
    }

    private static func matchPair(_ s: String) -> (Double, Double)? {
        guard let groups = matchGroups(s, pattern: "([0-9]+(?:\\.[0-9]+)?)\\s*[×xX*]\\s*([0-9]+(?:\\.[0-9]+)?)"),
              groups.count >= 3, let a = Double(groups[1]), let b = Double(groups[2]) else { return nil }
        return (a, b)
    }

    private static func matchOne(_ s: String, pattern: String) -> Double? {
        guard let groups = matchGroups(s, pattern: pattern), groups.count >= 2 else { return nil }
        return Double(groups[1])
    }

    private static func matchGroups(_ s: String, pattern: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = s as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let m = re.firstMatch(in: s, options: [], range: range), m.numberOfRanges >= 2 else { return nil }
        var out: [String] = []
        for i in 0..<m.numberOfRanges {
            let r = m.range(at: i)
            out.append(r.location == NSNotFound ? "" : ns.substring(with: r))
        }
        return out
    }

    private static func allNumbers(_ s: String) -> [Double] {
        guard let re = try? NSRegularExpression(pattern: "[0-9]+(?:\\.[0-9]+)?", options: []) else { return [] }
        let ns = s as NSString
        let range = NSRange(location: 0, length: ns.length)
        return re.matches(in: s, options: [], range: range).compactMap {
            Double(ns.substring(with: $0.range))
        }
    }

    private static func normalizeText(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let map: [(String, String)] = [
            ("０", "0"), ("１", "1"), ("２", "2"), ("３", "3"), ("４", "4"),
            ("５", "5"), ("６", "6"), ("７", "7"), ("８", "8"), ("９", "9"),
            ("，", "."), ("．", "."), ("×", "×"), ("Φ", "Ø"), ("φ", "Ø"), ("∅", "Ø")
        ]
        for (a, b) in map { t = t.replacingOccurrences(of: a, with: b) }
        while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
        return t
    }

    // MARK: - 孔

    private static func detectHoles(contours: [VNContoursObservation],
                                    outer: VNContour?,
                                    outerBox: CGRect,
                                    length: Double,
                                    width: Double,
                                    height: Double,
                                    ocr: OcrFacts) -> (feats: [PartFeat], annotations: [ScanAnnotation]) {
        guard let observation = contours.first else { return ([], []) }
        let outerArea = max(Double(outerBox.width * outerBox.height), 0.0001)
        let scaleX = length / Double(max(outerBox.width, 0.001))
        let scaleY = width / Double(max(outerBox.height, 0.001))

        var candidates: [VNContour] = []
        func collect(_ list: [VNContour]) {
            for c in list {
                candidates.append(c)
                collect(c.childContours)
            }
        }
        collect(observation.topLevelContours)

        var feats: [PartFeat] = []
        var annotations: [ScanAnnotation] = []
        for c in candidates {
            if let outerContour = outer, c === outerContour { continue }
            let p = points(of: c)
            guard p.count > 5 else { continue }
            let b = bounds(p)
            guard b.width > 0.008, b.height > 0.008 else { continue }
            let area = abs(Double(signedArea(p)))
            guard area > 0.0008, area / outerArea < 0.22 else { continue }
            guard b.midX > outerBox.minX, b.midX < outerBox.maxX,
                  b.midY > outerBox.minY, b.midY < outerBox.maxY else { continue }

            let ar = Double(b.width / b.height)
            let perimeter = polygonPerimeter(p)
            let circularity = perimeter > 0.001 ? (4 * .pi * area / (perimeter * perimeter)) : 0
            let x = (Double(b.midX) - Double(outerBox.midX)) * scaleX
            let y = (Double(b.midY) - Double(outerBox.midY)) * scaleY

            // 1) 圆孔：近圆、闭合、面积合理；优先用附近 Ø 标注校正像素估算值。
            if ar > 0.65 && ar < 1.45 && circularity > 0.65 {
                var dia = (Double(b.width) * scaleX + Double(b.height) * scaleY) / 2
                if let label = ocr.holeLabels.min(by: {
                    hypot($0.rect.midX - b.midX, $0.rect.midY - b.midY)
                        < hypot($1.rect.midX - b.midX, $1.rect.midY - b.midY)
                }), hypot(label.rect.midX - b.midX, label.rect.midY - b.midY) < 0.10 {
                    let d = label.dia
                    if d > 2, d < min(length, width) * 0.92,
                       abs(d - dia) / max(dia, 0.1) < 0.35 { dia = d }
                }
                guard dia > 2.0, dia < min(length, width) * 0.92 else { continue }
                var duplicate = false
                for f in feats {
                    if hypot(f.x - x, f.y - y) < 1.5 && abs(f.dia - dia) < 1.2 { duplicate = true; break }
                }
                if duplicate { continue }

                var f = PartFeat(kind: .hole, x: x, y: y, dia: dia,
                                 depth: height + 1, name: "识别孔 \(feats.count + 1)")
                f.depth = height + 1
                feats.append(f)
                var annotation = ScanAnnotation(
                    text: "Ø\(ncf(dia))",
                    rect: b,
                    kind: .hole)
                annotation.featID = f.id
                annotations.append(annotation)
                continue
            }

            // 2) 槽 / 方型腔：非圆形闭合内轮廓，按矩形腔近似。
            // 只收长宽比明显、面积够大的，避免把文字/箭头/图框当成型腔。
            guard ar > 1.22 || ar < 0.82 else { continue }
            guard area / outerArea > 0.004, area / outerArea < 0.20 else { continue }
            guard b.width > 0.025, b.height > 0.018, p.count >= 6 else { continue }
            guard b.midX > outerBox.minX + outerBox.width * 0.02,
                  b.midX < outerBox.maxX - outerBox.width * 0.02,
                  b.midY > outerBox.minY + outerBox.height * 0.02,
                  b.midY < outerBox.maxY - outerBox.height * 0.02 else { continue }

            let w = Double(b.width) * scaleX
            let h = Double(b.height) * scaleY
            guard w > 2.0, h > 1.5, w < length * 0.9, h < width * 0.9 else { continue }
            var duplicate = false
            for f in feats where f.kind == .rectPocket {
                if hypot(f.x - x, f.y - y) < 1.5 && abs(f.w - w) < 1.2 && abs(f.h - h) < 1.2 { duplicate = true; break }
            }
            if duplicate { continue }

            var f = PartFeat(kind: .rectPocket, x: x, y: y, dia: max(w, h),
                             w: w, h: h, depth: height + 1,
                             name: "识别槽/腔 \(feats.count + 1)")
            f.depth = height + 1
            feats.append(f)
            var annotation = ScanAnnotation(
                text: "槽/腔 \(ncf(w))×\(ncf(h))",
                rect: b,
                kind: .hole)
            annotation.featID = f.id
            annotations.append(annotation)
        }
        return (feats, annotations)
    }

    private static func polygonPerimeter(_ p: [CGPoint]) -> Double {
        guard p.count > 2 else { return 0 }
        var sum: Double = 0
        for i in p.indices {
            let a = p[i], b = p[(i + 1) % p.count]
            sum += hypot(Double(b.x - a.x), Double(b.y - a.y))
        }
        return sum
    }

    // MARK: - 图像

    static func prepare(_ image: UIImage, maxDimension: CGFloat = 2000) -> UIImage {
        let oriented = image.fixedOrientation()
        let w = max(oriented.size.width, 1)
        let h = max(oriented.size.height, 1)
        let scale = min(1, maxDimension / max(w, h))
        let size = CGSize(width: w * scale, height: h * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            oriented.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// 按 UI 归一化坐标裁图（原点左上角），裁完再交给识别器缩放。
    static func crop(_ image: UIImage, normalizedRect: CGRect) -> UIImage? {
        let oriented = image.fixedOrientation()
        guard let cg = oriented.cgImage else { return nil }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        var r = CGRect(
            x: normalizedRect.minX * w,
            y: normalizedRect.minY * h,
            width: normalizedRect.width * w,
            height: normalizedRect.height * h
        ).integral
        r = r.intersection(CGRect(x: 0, y: 0, width: w, height: h))
        guard r.width > 2, r.height > 2, let cropped = cg.cropping(to: r) else { return nil }
        return UIImage(cgImage: cropped, scale: 1, orientation: .up)
    }
}

private extension UIImage {
    func fixedOrientation() -> UIImage {
        if imageOrientation == .up { return self }
        UIGraphicsBeginImageContextWithOptions(size, false, 1)
        draw(in: CGRect(origin: .zero, size: size))
        let out = UIGraphicsGetImageFromCurrentImageContext() ?? self
        UIGraphicsEndImageContext()
        return out
    }
}
