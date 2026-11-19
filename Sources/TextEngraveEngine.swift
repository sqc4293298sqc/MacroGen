import Foundation
import CoreText
import CoreGraphics
import UIKit

/// 汉字刻字参数。尺寸单位都是 mm，Z0 是工件顶面。
struct TextEngraveParams {
    var text: String = "汉字刻字"
    var fontIndex: Int = 0
    var bold: Bool = false
    var fontName: String = "黑体"
    var charW: CGFloat = 12
    var charH: CGFloat = 12
    /// 逐字宽，按可见字顺序；空数组表示都用 charW
    var charWidths: [CGFloat] = []
    /// 逐字高，按可见字顺序；空数组表示都用 charH
    var charHeights: [CGFloat] = []
    var spacing: CGFloat = 2
    var totalW: CGFloat = 0
    var totalH: CGFloat = 0
    var depth: CGFloat = 1.5
    var stepDown: CGFloat = 0.5
    var toolDia: CGFloat = 3
    var feed: Int = 300
    var rpm: Int = 8000
    var safeZ: CGFloat = 10
    var hNo: Int = 1
    var coord: Int = 54
    var originX: CGFloat = 0
    var originY: CGFloat = 0
    var sampleStep: CGFloat = 0.3
}

struct TextEngravePoint {
    var x: CGFloat
    var y: CGFloat
}

struct TextEngraveContour {
    var pts: [TextEngravePoint] = []
}

struct TextEngravePlan {
    var contours: [TextEngraveContour] = []
    var width: CGFloat = 0
    var height: CGFloat = 0
    var minX: CGFloat = 0
    var maxX: CGFloat = 0
    var minY: CGFloat = 0
    var maxY: CGFloat = 0
    var pointCount: Int = 0
    var charCount: Int = 0
    var fontName: String = ""
    var error: String? = nil
}

/// CoreText 取字形轮廓，再转成折线和分层刻字 G 代码。
/// 注意：Core Text 的路径是左下角原点、Y 向上的；这里按机床坐标保留 Y 向上。
enum TextEngraveEngine {

    static let fonts = ["黑体", "宋体", "等线", "楷体", "仿宋", "圆体"]

    private static let fontNames = [
        "PingFangSC-Regular",
        "STSongti-SC-Regular",
        "PingFangSC-Light",
        "STKaitiSC-Regular",
        "STFangsong",
        "STYuanti-SC-Regular"
    ]

    static func typeface(index: Int, bold: Bool, size: CGFloat = 100) -> CTFont {
        let i = max(0, min(index, fontNames.count - 1))
        var font = CTFontCreateWithName(fontNames[i] as CFString, size, nil)
        if fontNameLooksMissing(font) {
            if let fallback = CTFontCreateUIFontForLanguage(.system, size, "zh-Hans" as CFString) {
                font = fallback
            }
        }
        if bold {
            let traits = CTFontSymbolicTraits.traitBold
            if let boldFont = CTFontCreateCopyWithSymbolicTraits(font, size, nil, traits, traits) {
                font = boldFont
            }
        }
        return font
    }

    private static func fontNameLooksMissing(_ font: CTFont) -> Bool {
        let name = CTFontCopyPostScriptName(font) as String
        return name.isEmpty || name == "LastResort"
    }

    static func build(params: TextEngraveParams) -> TextEngravePlan {
        var plan = TextEngravePlan()
        plan.fontName = params.fontName.isEmpty ? "系统字体" : params.fontName
        let text = params.text.replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: " ")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            plan.error = "请输入要刻的文字"
            return plan
        }

        let font = typeface(index: params.fontIndex, bold: params.bold, size: 100)
        let defaultW = max(0.5, params.charW)
        let defaultH = max(0.5, params.charH)
        let spacing = max(0, params.spacing)

        var glyphs: [CGPath] = []
        var cursor: CGFloat = 0
        var maxH = defaultH
        var chars = 0

        for ch in Array(text) {
            if ch == " " || ch == "\t" {
                cursor += defaultW + spacing
                continue
            }
            let utf16 = Array(String(ch).utf16)
            var glyphsForChar = [CGGlyph](repeating: 0, count: max(1, utf16.count))
            let ok = utf16.withUnsafeBufferPointer { cp in
                glyphsForChar.withUnsafeMutableBufferPointer { gp in
                    CTFontGetGlyphsForCharacters(font,
                                                 cp.baseAddress!,
                                                 gp.baseAddress!,
                                                 utf16.count)
                }
            }
            guard ok, let glyph = glyphsForChar.first, glyph != 0,
                  let raw = CTFontCreatePathForGlyph(font, glyph, nil) else { continue }
            let box = raw.boundingBoxOfPath
            guard box.width > 0.01, box.height > 0.01 else { continue }

            let cw = (params.charWidths.count > chars && params.charWidths[chars] > 0)
                ? params.charWidths[chars] : defaultW
            let chh = (params.charHeights.count > chars && params.charHeights[chars] > 0)
                ? params.charHeights[chars] : defaultH
            maxH = max(maxH, chh)

            let sx = cw / box.width
            let sy = chh / box.height
            var transform = CGAffineTransform(scaleX: sx, y: sy)
            transform = transform.concatenating(
                CGAffineTransform(translationX: cursor - box.minX * sx,
                                  y: -(box.minY + box.maxY) / 2 * sy)
            )
            if let transformed = raw.copy(using: &transform) {
                glyphs.append(transformed)
                chars += 1
                cursor += cw + spacing
            }
        }

        guard !glyphs.isEmpty else {
            plan.error = "文字没有可刻轮廓"
            return plan
        }

        let baseW = max(0.5, cursor - spacing)
        let baseH = max(0.5, maxH)
        let fitX = params.totalW > 0 ? params.totalW / baseW : 1
        let fitY = params.totalH > 0 ? params.totalH / baseH : 1

        var fit = CGAffineTransform(scaleX: fitX, y: fitY)
        fit = fit.concatenating(
            CGAffineTransform(translationX: params.originX - baseW * fitX / 2,
                              y: params.originY)
        )

        plan.width = params.totalW > 0 ? params.totalW : baseW * fitX
        plan.height = params.totalH > 0 ? params.totalH : baseH * fitY
        plan.charCount = chars
        plan.minX = .greatestFiniteMagnitude
        plan.minY = .greatestFiniteMagnitude
        plan.maxX = -.greatestFiniteMagnitude
        plan.maxY = -.greatestFiniteMagnitude

        let step = max(0.08, params.sampleStep)
        for glyph in glyphs {
            var transformed = glyph.copy(using: &fit) ?? glyph
            var contours: [TextEngraveContour] = []
            transformPath(transformed, step: step, into: &contours)
            for contour in contours where contour.pts.count >= 3 {
                plan.contours.append(contour)
                for point in contour.pts {
                    plan.pointCount += 1
                    plan.minX = min(plan.minX, point.x)
                    plan.maxX = max(plan.maxX, point.x)
                    plan.minY = min(plan.minY, point.y)
                    plan.maxY = max(plan.maxY, point.y)
                }
                if plan.pointCount > 60000 {
                    plan.error = "笔画太密，请减少文字或增大采样步距"
                    return plan
                }
            }
        }

        if plan.contours.isEmpty {
            plan.error = "没有生成有效轮廓"
        }
        return plan
    }

    // MARK: - CGPath 转折线

    private static func transformPath(_ path: CGPath, step: CGFloat,
                                      into contours: inout [TextEngraveContour]) {
        var current: TextEngraveContour? = nil
        var start = CGPoint.zero
        var last = CGPoint.zero

        func begin(_ p: CGPoint) {
            if let c = current, c.pts.count >= 3 { contours.append(c) }
            current = TextEngraveContour()
            start = p
            last = p
            add(p)
        }

        func add(_ p: CGPoint) {
            current?.pts.append(TextEngravePoint(x: p.x, y: p.y))
        }

        func line(_ p: CGPoint) {
            let dx = p.x - last.x
            let dy = p.y - last.y
            let distance = hypot(dx, dy)
            let steps = max(1, Int(ceil(distance / step)))
            if steps > 1 {
                for i in 1...steps {
                    let t = CGFloat(i) / CGFloat(steps)
                    add(CGPoint(x: last.x + dx * t, y: last.y + dy * t))
                }
            } else {
                add(p)
            }
            last = p
        }

        func quad(_ p: CGPoint, control c: CGPoint) {
            let approx = max(8, Int(ceil((hypot(c.x - last.x, c.y - last.y)
                + hypot(p.x - c.x, p.y - c.y)) / step))
            for i in 1...max(1, approx) {
                let t = CGFloat(i) / CGFloat(max(1, approx))
                let x = (1 - t) * (1 - t) * last.x + 2 * (1 - t) * t * c.x + t * t * p.x
                let y = (1 - t) * (1 - t) * last.y + 2 * (1 - t) * t * c.y + t * t * p.y
                add(CGPoint(x: x, y: y))
            }
            last = p
        }

        func curve(_ p: CGPoint, c1: CGPoint, c2: CGPoint) {
            let approx = max(10, Int(ceil((hypot(c1.x - last.x, c1.y - last.y)
                + hypot(c2.x - c1.x, c2.y - c1.y)
                + hypot(p.x - c2.x, p.y - c2.y)) / step))
            for i in 1...max(1, approx) {
                let t = CGFloat(i) / CGFloat(max(1, approx))
                let mt = 1 - t
                let x = mt * mt * mt * last.x + 3 * mt * mt * t * c1.x
                    + 3 * mt * t * t * c2.x + t * t * t * p.x
                let y = mt * mt * mt * last.y + 3 * mt * mt * t * c1.y
                    + 3 * mt * t * t * c2.y + t * t * t * p.y
                add(CGPoint(x: x, y: y))
            }
            last = p
        }

        func close() {
            if last != start { line(start) }
            if let c = current, c.pts.count >= 3 { contours.append(c) }
            current = nil
        }

        path.applyWithBlock { elementPtr in
            let e = elementPtr.pointee
            switch e.type {
            case .moveToPoint:
                begin(e.points[0])
            case .addLineToPoint:
                line(e.points[0])
            case .addQuadCurveToPoint:
                quad(e.points[1], control: e.points[0])
            case .addCurveToPoint:
                curve(e.points[2], c1: e.points[0], c2: e.points[1])
            case .closeSubpath:
                close()
            @unknown default:
                break
            }
        }
        if let c = current, c.pts.count >= 3 { contours.append(c) }
    }

    // MARK: - G 代码

    static func code(plan: TextEngravePlan, params: TextEngraveParams) -> String {
        guard plan.error == nil, !plan.contours.isEmpty else {
            return "（没有可生成的刻字轮廓）"
        }
        let depth = max(0, params.depth)
        let stepDown = max(0.02, params.stepDown)
        var b = ""
        b += "%\n"
        b += "O3101 (汉字刻字)\n"
        b += "( 文字：\(clean(params.text)) )\n"
        b += "( 单字 W=\(f(params.charW, 2)) H=\(f(params.charH, 2)) 字距=\(f(params.spacing, 2)) )\n"
        if !params.charWidths.isEmpty || !params.charHeights.isEmpty {
            b += "( 逐字尺寸：W=\(params.charWidths.map { f($0, 2) }.joined(separator: ","))"
            b += " H=\(params.charHeights.map { f($0, 2) }.joined(separator: ",")) )\n"
        }
        b += "( 总尺寸 W=\(f(plan.width, 2)) H=\(f(plan.height, 2)) 深=\(f(depth, 2)) )\n"
        b += "( 轮廓线刻字，不是清腔；刀径 Ø\(f(params.toolDia, 2)) )\n"
        b += "G17 G21 G40 G49 G80 G90 G\(params.coord)\n"
        b += "G0 Z\(f(params.safeZ, 3))\n"
        b += "G43 H\(params.hNo) Z\(f(params.safeZ, 3))\n"
        b += "M3 S\(params.rpm)\nM8\n"
        b += "( ===== 分层刻轮廓 ===== )\n"

        var z: CGFloat = 0
        var layer = 0
        while true {
            z = max(z - stepDown, -depth)
            layer += 1
            b += "( 第 \(layer) 层 Z=\(f(z, 3)) )\n"
            for c in plan.contours where c.pts.count >= 2 {
                guard let first = c.pts.first else { continue }
                b += "G0 Z\(f(params.safeZ, 3))\n"
                b += "G0 X\(f(first.x, 3)) Y\(f(first.y, 3))\n"
                b += "G1 Z\(f(z, 3)) F\(params.feed)\n"
                for p in c.pts.dropFirst() {
                    b += "G1 X\(f(p.x, 3)) Y\(f(p.y, 3))\n"
                }
                b += "G0 Z\(f(params.safeZ, 3))\n"
            }
            if z <= -depth + 0.000000001 { break }
            if layer >= 200 { break }
        }

        b += "G0 Z\(f(params.safeZ, 3))\n"
        b += "M5\nM9\nG28 G91 Z0\nG90\nM30\n%\n"
        return b
    }

    static func summary(plan: TextEngravePlan, params: TextEngraveParams) -> String {
        if let error = plan.error { return error }
        return "\(plan.charCount) 字 · 总 \(f(plan.width, 2)) × \(f(plan.height, 2)) mm"
            + " · \(plan.contours.count) 条轮廓"
    }

    static func manual(params: TextEngraveParams) -> String {
        """
        汉字刻字说明

        1. 输入中文、英文或数字，按每个字的外框排版。
        2. 单字宽 / 单字高：所有字默认使用这个外框；逐字宽/高按可见字顺序用逗号分隔，可单独覆盖某个字。
        3. 字距：相邻两个字外框之间的距离，单位 mm。
        4. 总宽 / 总高：0 表示自动；填大于 0 的值会把整行文字整体缩放到这个总尺寸。
        5. 总深：Z0 为工件顶面，刻到 Z=-总深。
        6. 每层切深：分层下刀，建议 0.2~0.5 mm。
        7. 生成的是文字轮廓线，不是清腔；适合 V 刀或小径平底刀刻字。
        8. 上机前请先空运行或抬高 Z 检查刀路，确认字体、字距和文字中心。

        当前：单字 \(f(params.charW, 2))×\(f(params.charH, 2)) mm，字距 \(f(params.spacing, 2)) mm，深 \(f(params.depth, 2)) mm，文字中心 X\(f(params.originX, 2)) Y\(f(params.originY, 2))。
        """
    }

    private static func clean(_ s: String) -> String {
        s.replacingOccurrences(of: "(", with: "（")
            .replacingOccurrences(of: ")", with: "）")
            .replacingOccurrences(of: "\n", with: " ")
    }

    static func fmt(_ value: CGFloat, _ digits: Int) -> String {
        let fmt = "%." + String(digits) + "f"
        return String(format: fmt, Double(value)).replacingOccurrences(of: ",", with: ".")
    }

    private static func f(_ value: CGFloat, _ digits: Int) -> String {
        fmt(value, digits)
    }
}
