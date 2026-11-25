import Foundation

/// 本地文字 → True3D 参数的结果。解析完全在设备上完成，不联网。
struct TextTo3DParseResult {
    var params: True3DParams
    var summary: [String]
    var warnings: [String]
}

enum TextTo3DParseError: LocalizedError {
    case empty
    case missingBaseDimensions
    case unsupported(String)
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .empty:
            return "请输入零件描述"
        case .missingBaseDimensions:
            return "没有识别到毛坯尺寸。请写成 120×80×30 或 长120 宽80 高30"
        case .unsupported(let detail):
            return "暂不支持：\(detail)"
        case .invalid(let detail):
            return "参数不合理：\(detail)"
        }
    }
}

/// 轻量规则解析器：只支持常用 CNC 特征，不做通用自然语言理解。
/// 目标是离线、可重复、出错可解释；不依赖任何模型或网络。
enum LocalTextTo3DParser {
    private struct BaseDimensions {
        var width: Double
        var depth: Double
        var height: Double
        var shape: True3DBaseShape
    }

    static func parse(_ raw: String) -> Result<TextTo3DParseResult, TextTo3DParseError> {
        let text = normalized(raw)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.empty)
        }
        guard let base = parseBaseDimensions(text) else {
            return .failure(.missingBaseDimensions)
        }

        var params = True3DParams()
        params.projectName = "文字生成"
        params.width = base.width
        params.depth = base.depth
        params.height = base.height
        params.baseShape = base.shape
        params.edgeMode = .none
        params.edgeSize = 0
        params.features = []

        var summary = ["毛坯：\(f(base.width))×\(f(base.depth))×\(f(base.height)) mm"]
        var warnings: [String] = []
        let radius = firstNumber(#"r\s*(\d+(?:\.\d+)?)"#, in: text)
        let hasSteppedSlot = text.contains("阶梯槽") || text.contains("阶梯")
        let hasFlange = text.contains("法兰")
        let hasRectPocket = text.contains("方腔") || text.contains("矩形腔")
        let hasCircularPocket = text.contains("圆腔")
        let hasBoss = text.contains("凸台")
        let hasHole = text.contains("孔")

        var usedSpecificFeature = false

        if hasSteppedSlot {
            do {
                try addSteppedSlot(
                    to: &params,
                    text: text,
                    base: base,
                    radius: radius,
                    summary: &summary,
                    warnings: &warnings
                )
                usedSpecificFeature = true
            } catch let error as TextTo3DParseError {
                return .failure(error)
            } catch {
                return .failure(.invalid(error.localizedDescription))
            }
        }

        if hasFlange {
            do {
                try addFlange(
                    to: &params,
                    text: text,
                    base: base,
                    radius: radius,
                    summary: &summary,
                    warnings: &warnings
                )
                usedSpecificFeature = true
            } catch let error as TextTo3DParseError {
                return .failure(error)
            } catch {
                return .failure(.invalid(error.localizedDescription))
            }
        }

        if hasRectPocket {
            do {
                try addRectPocket(
                    to: &params,
                    text: text,
                    base: base,
                    radius: radius,
                    summary: &summary,
                    warnings: &warnings
                )
                usedSpecificFeature = true
            } catch let error as TextTo3DParseError {
                return .failure(error)
            } catch {
                return .failure(.invalid(error.localizedDescription))
            }
        }

        if hasCircularPocket {
            do {
                try addCircularPocket(
                    to: &params,
                    text: text,
                    base: base,
                    summary: &summary,
                    warnings: &warnings
                )
                usedSpecificFeature = true
            } catch let error as TextTo3DParseError {
                return .failure(error)
            } catch {
                return .failure(.invalid(error.localizedDescription))
            }
        }

        if hasBoss && !hasFlange {
            do {
                try addBoss(
                    to: &params,
                    text: text,
                    base: base,
                    summary: &summary,
                    warnings: &warnings
                )
                usedSpecificFeature = true
            } catch let error as TextTo3DParseError {
                return .failure(error)
            } catch {
                return .failure(.invalid(error.localizedDescription))
            }
        }

        if hasHole && !hasFlange && !hasSteppedSlot {
            do {
                try addHoles(
                    to: &params,
                    text: text,
                    base: base,
                    summary: &summary,
                    warnings: &warnings
                )
                usedSpecificFeature = true
            } catch let error as TextTo3DParseError {
                return .failure(error)
            } catch {
                return .failure(.invalid(error.localizedDescription))
            }
        }

        // 单独写 R 但没有特征：按外轮廓圆角处理。
        if let radius, radius > 0, !usedSpecificFeature || params.features.isEmpty {
            guard radius < min(base.width, base.depth, base.height) / 2 - 0.001 else {
                return .failure(.invalid("圆角 R\(f(radius)) 大于最小外形的一半"))
            }
            params.edgeMode = .fillet
            params.edgeSize = radius
            summary.append("外轮廓圆角：R\(f(radius))")
        }

        if params.features.isEmpty && !usedSpecificFeature {
            warnings.append("没有识别到特征，只生成了毛坯；可以继续在 3D 工作台里加草图/孔/腔。")
        }

        summary.append("解析方式：本地规则，不联网")
        return .success(TextTo3DParseResult(params: params, summary: summary, warnings: warnings))
    }

    // MARK: - Base

    private static func parseBaseDimensions(_ text: String) -> BaseDimensions? {
        if let m = firstMatch(#"(\d+(?:\.\d+)?)\s*x\s*(\d+(?:\.\d+)?)\s*x\s*(\d+(?:\.\d+)?)"#, in: text),
           m.count >= 4,
           let w = Double(m[1]), let d = Double(m[2]), let h = Double(m[3]) {
            return BaseDimensions(width: w, depth: d, height: h, shape: .box)
        }

        if let m = firstMatch(#"长\s*(\d+(?:\.\d+)?)\s*(?:mm)?\s*宽\s*(\d+(?:\.\d+)?)\s*(?:mm)?\s*高\s*(\d+(?:\.\d+)?)"#, in: text),
           m.count >= 4,
           let w = Double(m[1]), let d = Double(m[2]), let h = Double(m[3]) {
            return BaseDimensions(width: w, depth: d, height: h, shape: .box)
        }

        if let m = firstMatch(#"(?:d|直径)\s*(\d+(?:\.\d+)?)\s*x\s*(\d+(?:\.\d+)?)"#, in: text),
           m.count >= 3,
           let dia = Double(m[1]), let h = Double(m[2]) {
            return BaseDimensions(width: dia, depth: dia, height: h, shape: .circle)
        }

        if let m = firstMatch(#"(?:d|直径)\s*(\d+(?:\.\d+)?).*?(?:高|厚度)\s*(\d+(?:\.\d+)?)"#, in: text),
           m.count >= 3,
           let dia = Double(m[1]), let h = Double(m[2]) {
            return BaseDimensions(width: dia, depth: dia, height: h, shape: .circle)
        }

        return nil
    }

    // MARK: - Stepped slot

    private static func addSteppedSlot(
        to params: inout True3DParams,
        text: String,
        base: BaseDimensions,
        radius: Double?,
        summary: inout [String],
        warnings: inout [String]
    ) throws {
        let width = firstNumber(#"槽宽\s*(?:为)?\s*(\d+(?:\.\d+)?)"#, in: text)
            ?? firstNumber(#"(\d+(?:\.\d+)?)\s*(?:mm)?\s*宽"#, in: text)
        guard let slotWidth = width, slotWidth > 0.1 else {
            throw TextTo3DParseError.invalid("阶梯槽缺少槽宽，请写成“18宽”或“槽宽18”")
        }
        guard slotWidth < base.depth - 0.1 else {
            throw TextTo3DParseError.invalid("槽宽 \(f(slotWidth)) 必须小于毛坯宽度 \(f(base.depth))")
        }

        let depths = numbers(after: "深", in: text)
        guard depths.count >= 2 else {
            throw TextTo3DParseError.invalid("阶梯槽至少需要两级深度，请写成“深6/12/18”")
        }
        guard depths.count <= 8 else {
            throw TextTo3DParseError.unsupported("阶梯槽级数 \(depths.count) 太多，当前最多 8 级")
        }
        guard depths.allSatisfy({ $0 > 0.1 && $0 < base.height - 0.1 }) else {
            throw TextTo3DParseError.invalid("每级槽深必须大于 0.1 且小于毛坯高度 \(f(base.height))")
        }

        let requestedLength = firstNumber(#"槽长(?:度)?\s*(?:为)?\s*(\d+(?:\.\d+)?)"#, in: text)
            ?? firstNumber(#"阶梯槽长(?:度)?\s*(?:为)?\s*(\d+(?:\.\d+)?)"#, in: text)
        let slotLength: Double
        if let requestedLength {
            slotLength = requestedLength
        } else {
            slotLength = min(base.width * 0.75, base.width - 2)
            warnings.append("未写槽长，按毛坯长度的 75% 取 \(f(slotLength)) mm，并居中放置。")
        }
        guard slotLength > 1, slotLength <= base.width - 0.2 else {
            throw TextTo3DParseError.invalid("槽长 \(f(slotLength)) 必须大于 1 且不超过毛坯长度 \(f(base.width))")
        }

        let count = depths.count
        let segmentLength = slotLength / Double(count)
        guard segmentLength > 0.5 else {
            throw TextTo3DParseError.invalid("每级槽长太小，请增大槽长或减少级数")
        }

        for index in 0..<count {
            var feature = True3DFeatureSpec(kind: .rectPocket, x: 0, y: 0)
            feature.name = "阶梯槽 \(index + 1)"
            feature.x = -slotLength / 2 + segmentLength * (Double(index) + 0.5)
            feature.y = 0
            feature.width = segmentLength
            feature.depthY = slotWidth
            feature.depth = depths[index]
            feature.cornerRadius = 0
            params.features.append(feature)
        }

        summary.append("阶梯槽：\(count) 级 · 槽宽 \(f(slotWidth)) · 深 \(depths.map(f).joined(separator: "/")) · 长 \(f(slotLength))")

        if let radius, radius > 0 {
            guard radius < min(base.width, base.depth, base.height) / 2 - 0.001 else {
                throw TextTo3DParseError.invalid("槽内圆角 R\(f(radius)) 过大")
            }
            var fillet = True3DFeatureSpec(kind: .edgeFillet)
            fillet.name = "槽内圆角"
            fillet.edgeSelection = .concaveVertical
            fillet.depth = radius
            params.features.append(fillet)
            summary.append("槽内凹边圆角：R\(f(radius))")
        }
    }

    // MARK: - Flange

    private static func addFlange(
        to params: inout True3DParams,
        text: String,
        base: BaseDimensions,
        radius: Double?,
        summary: inout [String],
        warnings: inout [String]
    ) throws {
        let centerDia = firstNumber(#"中心孔\s*(?:d|直径)?\s*(\d+(?:\.\d+)?)"#, in: text)
            ?? firstNumber(#"中心\s*(?:d|直径)\s*(\d+(?:\.\d+)?)"#, in: text)
            ?? min(base.width, base.depth) * 0.375
        guard centerDia > 0.1, centerDia < min(base.width, base.depth) else {
            throw TextTo3DParseError.invalid("中心孔直径 \(f(centerDia)) 不合理")
        }

        let boltMatch = firstMatch(#"(\d+)\s*个\s*(?:孔)?\s*(?:d|m|直径)?\s*(\d+(?:\.\d+)?)"#, in: text)
        let boltCount = boltMatch.flatMap { $0.count >= 3 ? Int($0[1]) : nil } ?? 6
        let boltDia = boltMatch.flatMap { $0.count >= 3 ? Double($0[2]) : nil } ?? 6
        guard boltCount > 0, boltCount <= 24 else {
            throw TextTo3DParseError.invalid("螺栓孔数量必须在 1～24 之间")
        }
        guard boltDia > 0.1, boltDia < min(base.width, base.depth) else {
            throw TextTo3DParseError.invalid("螺栓孔直径 \(f(boltDia)) 不合理")
        }

        let pcd = firstNumber(#"(?:分布圆|pcd)\s*(?:d|直径)?\s*(\d+(?:\.\d+)?)"#, in: text)
            ?? min(base.width, base.depth) * 0.75
        guard pcd > boltDia + 0.1 else {
            throw TextTo3DParseError.invalid("分布圆直径 \(f(pcd)) 必须大于螺栓孔直径")
        }
        let ringRadius = pcd / 2
        guard ringRadius + boltDia / 2 < min(base.width, base.depth) / 2 - 0.1 else {
            throw TextTo3DParseError.invalid("螺栓孔超出毛坯范围，请减小分布圆或孔径")
        }

        var center = True3DFeatureSpec(kind: .hole, x: 0, y: 0)
        center.name = "中心孔"
        center.dia = centerDia
        center.holeKind = .through
        params.features.append(center)

        for index in 0..<boltCount {
            let angle = -Double.pi / 2 + Double(index) * 2 * Double.pi / Double(boltCount)
            var hole = True3DFeatureSpec(
                kind: .hole,
                x: cos(angle) * ringRadius,
                y: sin(angle) * ringRadius
            )
            hole.name = "螺栓孔 \(index + 1)"
            hole.dia = boltDia
            hole.holeKind = .through
            params.features.append(hole)
        }

        if let radius, radius > 0 {
            guard radius < min(base.width, base.depth, base.height) / 2 - 0.001 else {
                throw TextTo3DParseError.invalid("法兰外圆角 R\(f(radius)) 过大")
            }
            params.edgeMode = .fillet
            params.edgeSize = radius
        }

        summary.append("法兰：中心孔 Ø\(f(centerDia)) · \(boltCount) 个 Ø\(f(boltDia)) 螺栓孔 · 分布圆 Ø\(f(pcd))")

        if firstMatch(#"中心孔"#, in: text) == nil {
            warnings.append("未写中心孔直径，按毛坯短边的 37.5% 取 Ø\(f(centerDia)) mm。")
        }
        if boltMatch == nil {
            warnings.append("未写螺栓孔，默认 6 个 Ø6 孔。")
        }
        if firstMatch(#"(?:分布圆|pcd)"#, in: text) == nil {
            warnings.append("未写分布圆，按毛坯短边的 75% 取 Ø\(f(pcd)) mm。")
        }
    }

    // MARK: - Pockets

    private static func addRectPocket(
        to params: inout True3DParams,
        text: String,
        base: BaseDimensions,
        radius: Double?,
        summary: inout [String],
        warnings: inout [String]
    ) throws {
        let dims = firstMatch(#"(\d+(?:\.\d+)?)\s*x\s*(\d+(?:\.\d+)?)\s*(?:mm)?\s*(?:的)?\s*(?:方腔|矩形腔)"#, in: text)
            ?? firstMatch(#"(?:方腔|矩形腔)\s*(?:尺寸)?\s*(?:为)?\s*(\d+(?:\.\d+)?)\s*x\s*(\d+(?:\.\d+)?)"#, in: text)
        guard let dims, dims.count >= 3,
              let width = Double(dims[1]), let depthY = Double(dims[2]) else {
            throw TextTo3DParseError.invalid("方腔缺少尺寸，请写成“40×30方腔深10”")
        }
        let depth = firstNumber(#"深(?:度)?\s*(\d+(?:\.\d+)?)"#, in: text)
        guard let depth, depth > 0.1, depth < base.height - 0.1 else {
            throw TextTo3DParseError.invalid("方腔深度必须大于 0.1 且小于毛坯高度 \(f(base.height))")
        }
        guard width > 0.1, depthY > 0.1, width < base.width - 0.2, depthY < base.depth - 0.2 else {
            throw TextTo3DParseError.invalid("方腔尺寸超出毛坯范围")
        }

        var feature = True3DFeatureSpec(kind: .rectPocket, x: 0, y: 0)
        feature.name = "方腔"
        feature.width = width
        feature.depthY = depthY
        feature.depth = depth
        feature.cornerRadius = max(radius ?? 0, 0)
        guard feature.cornerRadius < min(width, depthY) / 2 else {
            throw TextTo3DParseError.invalid("方腔圆角 R\(f(feature.cornerRadius)) 过大")
        }
        params.features.append(feature)
        summary.append("方腔：\(f(width))×\(f(depthY)) · 深 \(f(depth)) · R\(f(feature.cornerRadius))")
        warnings.append("方腔默认放在毛坯中心，可在 3D 工作台里移动。")
    }

    private static func addCircularPocket(
        to params: inout True3DParams,
        text: String,
        base: BaseDimensions,
        summary: inout [String],
        warnings: inout [String]
    ) throws {
        let dia = firstNumber(#"圆腔\s*(?:直径|d)?\s*(?:为)?\s*(\d+(?:\.\d+)?)"#, in: text)
            ?? firstNumber(#"(?:直径|d)\s*(\d+(?:\.\d+)?).*?圆腔"#, in: text)
        guard let dia, dia > 0.1, dia < min(base.width, base.depth) - 0.2 else {
            throw TextTo3DParseError.invalid("圆腔直径不合理，或超出毛坯范围")
        }
        let depth = firstNumber(#"深(?:度)?\s*(\d+(?:\.\d+)?)"#, in: text)
        guard let depth, depth > 0.1, depth < base.height - 0.1 else {
            throw TextTo3DParseError.invalid("圆腔深度必须大于 0.1 且小于毛坯高度 \(f(base.height))")
        }
        var feature = True3DFeatureSpec(kind: .circularPocket, x: 0, y: 0)
        feature.name = "圆腔"
        feature.dia = dia
        feature.depth = depth
        params.features.append(feature)
        summary.append("圆腔：Ø\(f(dia)) · 深 \(f(depth))")
        warnings.append("圆腔默认放在毛坯中心，可在 3D 工作台里移动。")
    }

    // MARK: - Boss / holes

    private static func addBoss(
        to params: inout True3DParams,
        text: String,
        base: BaseDimensions,
        summary: inout [String],
        warnings: inout [String]
    ) throws {
        let dia = firstNumber(#"凸台\s*(?:直径|d)?\s*(?:为)?\s*(\d+(?:\.\d+)?)"#, in: text)
            ?? firstNumber(#"(?:直径|d)\s*(\d+(?:\.\d+)?).*?凸台"#, in: text)
        let height = firstNumber(#"凸台.*?高(?:度)?\s*(?:为)?\s*(\d+(?:\.\d+)?)"#, in: text)
            ?? firstNumber(#"高(?:度)?\s*(?:为)?\s*(\d+(?:\.\d+)?).*?凸台"#, in: text)
        guard let dia, let height, dia > 0.1, height > 0.1 else {
            throw TextTo3DParseError.invalid("凸台缺少直径或高度，请写成“Ø24凸台高6”")
        }
        guard dia < min(base.width, base.depth) - 0.2 else {
            throw TextTo3DParseError.invalid("凸台直径超出毛坯范围")
        }
        var feature = True3DFeatureSpec(kind: .boss, x: 0, y: 0)
        feature.name = "凸台"
        feature.dia = dia
        feature.bossHeight = height
        params.features.append(feature)
        summary.append("凸台：Ø\(f(dia)) · 高 \(f(height))")
        warnings.append("凸台默认放在毛坯中心，可在 3D 工作台里移动。")
    }

    private static func addHoles(
        to params: inout True3DParams,
        text: String,
        base: BaseDimensions,
        summary: inout [String],
        warnings: inout [String]
    ) throws {
        let pattern = firstMatch(#"(\d+)\s*个\s*(?:孔)?\s*(?:d|m|直径)?\s*(\d+(?:\.\d+)?)"#, in: text)
        let count = pattern.flatMap { $0.count >= 3 ? Int($0[1]) : nil } ?? 1
        let dia = pattern.flatMap { $0.count >= 3 ? Double($0[2]) : nil }
            ?? firstNumber(#"(?:d|直径)\s*(\d+(?:\.\d+)?)"#, in: text)
            ?? 10
        guard count > 0, count <= 24 else {
            throw TextTo3DParseError.invalid("孔数量必须在 1～24 之间")
        }
        guard dia > 0.1, dia < min(base.width, base.depth) - 0.2 else {
            throw TextTo3DParseError.invalid("孔径 \(f(dia)) 不合理或超出毛坯范围")
        }

        let spacing = min(base.width / Double(count + 1), 30)
        for index in 0..<count {
            var hole = True3DFeatureSpec(kind: .hole, x: 0, y: 0)
            hole.name = count == 1 ? "通孔" : "通孔 \(index + 1)"
            hole.x = count == 1 ? 0 : -Double(count - 1) * spacing / 2 + Double(index) * spacing
            hole.y = 0
            hole.dia = dia
            hole.holeKind = .through
            params.features.append(hole)
        }
        summary.append("通孔：\(count) 个 Ø\(f(dia))")
        if count > 1 {
            warnings.append("多孔默认沿 X 轴等距排列，间距 \(f(spacing)) mm，可在 3D 工作台里移动。")
        }
        if pattern == nil {
            warnings.append("未写孔数量和孔径，默认 1 个 Ø\(f(dia)) 通孔。")
        }
    }

    // MARK: - Text helpers

    private static func normalized(_ raw: String) -> String {
        var text = raw
            .replacingOccurrences(of: "×", with: "x")
            .replacingOccurrences(of: "＊", with: "x")
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: "；", with: ";")
            .replacingOccurrences(of: "：", with: ":")
            .replacingOccurrences(of: "Ø", with: "d")
            .replacingOccurrences(of: "ø", with: "d")
            .replacingOccurrences(of: "Φ", with: "d")
            .replacingOccurrences(of: "φ", with: "d")
            .replacingOccurrences(of: "毫米", with: "mm")
            .replacingOccurrences(of: "ＭＭ", with: "mm")
        text = text.replacingOccurrences(of: "  ", with: " ")
        return text
    }

    private static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else {
            return nil
        }
        return (0..<match.numberOfRanges).map { index in
            let nsRange = match.range(at: index)
            guard nsRange.location != NSNotFound,
                  let range = Range(nsRange, in: text) else { return "" }
            return String(text[range])
        }
    }

    private static func firstNumber(_ pattern: String, in text: String) -> Double? {
        guard let groups = firstMatch(pattern, in: text), groups.count >= 2 else { return nil }
        return Double(groups[1])
    }

    private static func numbers(after keyword: String, in text: String) -> [Double] {
        let escaped = NSRegularExpression.escapedPattern(for: keyword)
        let pattern = "\(escaped)(?:度)?\\s*([0-9]+(?:\\s*[/、,;和]\\s*[0-9]+)+)"
        guard let groups = firstMatch(pattern, in: text), groups.count >= 2 else { return [] }
        let numberPattern = #"(\d+(?:\.\d+)?)"#
        guard let regex = try? NSRegularExpression(pattern: numberPattern) else { return [] }
        let range = NSRange(groups[1].startIndex..<groups[1].endIndex, in: groups[1])
        return regex.matches(in: groups[1], options: [], range: range).compactMap { match in
            guard let range = Range(match.range(at: 1), in: groups[1]) else { return nil }
            return Double(groups[1][range])
        }
    }

    private static func f(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.001 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }
}
