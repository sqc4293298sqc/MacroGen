import Foundation
import CoreGraphics

// MARK: - 零件模型（草图 + 特征）

enum HoleMode: String, CaseIterable, Identifiable {
    case spiral = "螺旋铣"
    case g81 = "钻孔 G81"
    case g83 = "钻孔 G83"
    case tap = "攻丝 G84"
    var id: String { rawValue }
}

enum PartFeatKind: String, CaseIterable, Identifiable {
    case hole = "孔（贯通）"
    case pocket = "圆型腔（盲腔）"
    case rectPocket = "方型腔（盲腔）"
    var id: String { rawValue }
}

struct PartFeat: Identifiable, Equatable {
    var id = UUID()
    var name: String = ""
    var kind: PartFeatKind = .hole
    var x: Double = 0
    var y: Double = 0
    var dia: Double = 10
    var w: Double = 30
    var h: Double = 20
    var depth: Double = 5      // 型腔深度（孔不用）

    init(kind: PartFeatKind = .hole, x: Double = 0, y: Double = 0,
         dia: Double = 10, w: Double = 30, h: Double = 20, depth: Double = 5,
         name: String = "") {
        self.name = name
        self.kind = kind
        self.x = x
        self.y = y
        self.dia = dia
        self.w = w
        self.h = h
        self.depth = depth
    }
}

struct SketchLoop: Identifiable {
    var id = UUID()
    var name: String = "内轮廓"
    var template: ContourTemplate = .circle
    var rectL: Double = 40
    var rectW: Double = 20
    var rectR: Double = 0
    var circleD: Double = 20
    var slotL: Double = 40
    var slotW: Double = 12
    var nodes: [ContourNode] = []
    var cx: Double = 0
    var cy: Double = 0
    var through: Bool = true
    var depth: Double = 5
}

struct PartSpec {
    // 外形草图
    var template: ContourTemplate = .rect
    var rectL: Double = 120
    var rectW: Double = 80
    var rectR: Double = 0
    var circleD: Double = 100
    var slotL: Double = 120
    var slotW: Double = 30
    var nodes: [ContourNode] = []

    var height: Double = 10        // 零件厚度（外形铣到底）
    var topStock: Double = 1       // 顶面余量（平面铣深度）

    var feats: [PartFeat] = []
    /// 同一张草图上的内轮廓：内圆/内方/异形，建模时自动当挖孔或型腔
    var innerLoops: [SketchLoop] = []

    // 切削
    var spindle: Int = 2000
    var feed: Int = 400
    var stepDown: Double = 3
    var stepOver: Double = 6
    var safeZ: Double = 100

    // 刀具（工序列表里的 T 和 D）
    var faceTool: Int = 1
    var faceDia: Double = 6
    var contourTool: Int = 2
    var contourDia: Double = 8
    var holeTool: Int = 3
    var holeDia: Double = 6
    var pocketTool: Int = 4
    var pocketDia: Double = 6

    var doFace = true
    var doContour = true
    var doHole = true
    var doPocket = true

    // 孔加工方式
    var holeMode: HoleMode = .spiral
    var peck: Double = 2          // G83 每次啄钻
    var tapPitch: Double = 1.5    // 攻丝螺距
    var tapRpm: Int = 300
    var tapTool: Int = 5
    var tapDia: Double = 10

    var coord: Int = 54           // G54~G59
    var originX: Double = 0       // G54/G55… 的 X0Y0 落在草图坐标的哪个点
    var originY: Double = 0
}

// MARK: - 多工序程序

enum PartProg {

    /// 外形几何（供画布和程序共用）
    static func outline(_ p: PartSpec) -> DrawSpec {
        asDraw(p, outward: true, dia: p.contourDia, depth: p.height, hNo: p.contourTool)
    }

    static func asDraw(_ p: PartSpec, outward: Bool, template: ContourTemplate? = nil,
                       circleD: Double? = nil, dia: Double, depth: Double, hNo: Int) -> DrawSpec {
        var d = DrawSpec()
        d.template = template ?? p.template
        d.rectL = p.rectL
        d.rectW = p.rectW
        d.rectR = p.rectR
        d.circleD = circleD ?? p.circleD
        d.slotL = p.slotL
        d.slotW = p.slotW
        d.nodes = p.nodes
        d.toolDia = dia
        d.depth = depth
        d.stepDown = p.stepDown
        d.feed = Double(p.feed)
        d.rpm = Double(p.spindle)
        d.safeZ = p.safeZ
        d.hNo = hNo
        d.outward = outward
        return d
    }

    /// 内轮廓转成可以画/出程序的轮廓
    static func drawForLoop(_ l: SketchLoop, _ p: PartSpec, depth: Double,
                            dia: Double, hNo: Int) -> DrawSpec {
        var d = DrawSpec()
        d.template = l.template
        d.rectL = l.rectL
        d.rectW = l.rectW
        d.rectR = l.rectR
        d.circleD = l.circleD
        d.slotL = l.slotL
        d.slotW = l.slotW
        d.nodes = l.nodes
        d.toolDia = dia
        d.depth = depth
        d.stepDown = p.stepDown
        d.feed = Double(p.feed)
        d.rpm = Double(p.spindle)
        d.safeZ = p.safeZ
        d.hNo = hNo
        d.outward = false
        return d
    }

    static func loopPoints(_ l: SketchLoop) -> [CGPoint] {
        ContourGeo.flatten(ContourGeo.segments(ContourGeo.buildNodes(
            drawForLoop(l, PartSpec(), depth: l.depth, dia: 6, hNo: 1)))
        )
    }

    static func pts(_ p: PartSpec) -> [CGPoint] {
        ContourGeo.flatten(ContourGeo.segments(ContourGeo.buildNodes(outline(p)))
        )
    }

    /// 按工件原点平移整件：让设定的 X0Y0 点变成程序里的 0,0
    static func shifted(_ p: PartSpec, dx: Double, dy: Double) -> PartSpec {
        var q = p
        q.nodes = p.nodes.map { n in
            var m = n; m.x += dx; m.y += dy; return m
        }
        q.feats = p.feats.map { f in
            var m = f; m.x += dx; m.y += dy; return m
        }
        q.innerLoops = p.innerLoops.map { l in
            var m = l
            m.cx += dx; m.cy += dy
            m.nodes = l.nodes.map { n in var k = n; k.x += dx; k.y += dy; return k }
            return m
        }
        return q
    }

    static func bbox(_ p: PartSpec) -> CGRect {
        let ps = pts(p)
        guard let f = ps.first else { return CGRect(x: -50, y: -30, width: 100, height: 60) }
        var mnx = f.x, mxx = f.x, mny = f.y, mxy = f.y
        for q in ps {
            mnx = min(mnx, q.x); mxx = max(mxx, q.x)
            mny = min(mny, q.y); mxy = max(mxy, q.y)
        }
        return CGRect(x: mnx, y: mny, width: mxx - mnx, height: mxy - mny)
    }

    /// 工序清单（界面显示用）
    static func opList(_ p: PartSpec) -> [String] {
        var out: [String] = []
        if p.doFace && p.topStock > 0 {
            out.append("顶面 · 平面铣　T\(p.faceTool) D\(ncf(p.faceDia))")
        }
        if p.doContour {
            out.append("外形轮廓 · 轮廓铣　T\(p.contourTool) D\(ncf(p.contourDia))")
        }
        for f in p.feats {
            if f.kind == .hole {
                guard p.doHole else { continue }
                switch p.holeMode {
                case .spiral:
                    out.append("\(f.name.isEmpty ? "孔" : f.name) Ø\(ncf(f.dia)) · 螺旋铣　T\(p.holeTool) D\(ncf(p.holeDia))")
                case .g81:
                    out.append("孔 Ø\(ncf(f.dia)) · 钻孔 G81　T\(p.holeTool) D\(ncf(f.dia))")
                case .g83:
                    out.append("孔 Ø\(ncf(f.dia)) · 钻孔 G83　T\(p.holeTool) D\(ncf(f.dia))")
                case .tap:
                    out.append("孔 Ø\(ncf(f.dia)) · 攻丝 G84　T\(p.tapTool) P\(ncf(p.tapPitch))")
                }
            } else if p.doPocket && f.kind == .rectPocket {
                out.append("方腔 \(ncf(f.w))×\(ncf(f.h)) 深\(ncf(f.depth)) · 型腔铣　T\(p.pocketTool) D\(ncf(p.pocketDia))")
            } else if p.doPocket {
                out.append("沉台 Ø\(ncf(f.dia)) 深\(ncf(f.depth)) · 型腔铣　T\(p.pocketTool) D\(ncf(p.pocketDia))")
            }
        }
        for l in p.innerLoops {
            if l.template == .circle && l.through && !p.doHole { continue }
            if !(l.template == .circle && l.through) && !p.doPocket { continue }
            let depth = l.through ? p.height + 1 : min(l.depth, p.height)
            if l.template == .circle && l.through && p.holeMode != .spiral {
                out.append("\(l.name) Ø\(ncf(l.circleD)) · \(p.holeMode.rawValue)　T\(p.holeTool)")
            } else if l.template == .circle && l.through {
                out.append("\(l.name) Ø\(ncf(l.circleD)) · 螺旋铣　T\(p.holeTool) D\(ncf(p.holeDia))")
            } else {
                out.append("\(l.name) \(l.template.rawValue) 深\(ncf(depth)) · 型腔铣　T\(p.pocketTool) D\(ncf(p.pocketDia))")
            }
        }
        return out
    }

    static func issues(_ p: PartSpec) -> [String] {
        var out: [String] = []
        let base = ContourProg.issues(asDraw(p, outward: true, dia: p.contourDia, depth: p.height, hNo: p.contourTool))
        out.append(contentsOf: base)
        if p.height <= 0 { out.append("零件厚度要大于 0") }
        if p.contourDia <= 0 { out.append("外形刀径要大于 0") }
        let b = bbox(p)
        for (i, f) in p.feats.enumerated() {
            let r = f.dia / 2
            let inside = f.x - r >= b.minX + 0.5 && f.x + r <= b.maxX - 0.5
                && f.y - r >= b.minY + 0.5 && f.y + r <= b.maxY - 0.5
            if !inside {
                out.append("特征 \(i + 1)：Ø\(ncf(f.dia))@X\(ncf(f.x)) Y\(ncf(f.y)) 超出外形范围")
            }
            if f.kind == .hole && p.holeMode == .spiral && p.holeDia >= f.dia {
                out.append("特征 \(i + 1)：孔 Ø\(ncf(f.dia))，刀径必须小于孔径")
            }
            if f.kind == .pocket {
                if p.pocketDia / 2 >= f.dia / 2 {
                    out.append("特征 \(i + 1)：沉台 Ø\(ncf(f.dia))，刀径不能超过半径")
                }
                if f.depth > p.height { out.append("特征 \(i + 1)：沉台深度超过零件厚度") }
            }
            if f.kind == .rectPocket {
                if f.w <= p.pocketDia || f.h <= p.pocketDia {
                    out.append("特征 \(i + 1)：方腔 \(ncf(f.w))×\(ncf(f.h)) 比刀径小")
                }
                if f.depth > p.height { out.append("特征 \(i + 1)：方腔深度超过零件厚度") }
            }
        }
        return out
    }

    /// 把所有工序串成一个程序：共用一段抬头，每段自己带换刀后要用的 G43 H、S、F
    static func build(_ spec: PartSpec) -> String {
        var p = spec
        let ox = spec.originX, oy = spec.originY
        if abs(ox) > 1e-9 || abs(oy) > 1e-9 {
            p = shifted(spec, dx: -ox, dy: -oy)
        }
        var blocks: [String] = []
        var seq = 0
        var lastTool = -1

        func add(_ title: String, _ tool: Int, _ code: String) {
            seq += 1
            var seg = "( ===== 工序\(seq)  \(title) ===== )\n"
            if tool != lastTool {
                seg += "M00 (换刀：装 T\(tool) 后按循环启动)\n"
                lastTool = tool
            }
            seg += strip(code)
            blocks.append(seg)
        }

        if p.doFace && p.topStock > 0 {
            let b = bbox(p)
            var s = PocketSpec()
            s.mode = .face
            s.length = Double(b.width)
            s.width = Double(b.height)
            s.depth = p.topStock
            s.stepDown = min(p.topStock, max(0.3, p.stepDown))
            s.stepOver = p.stepOver
            s.toolDia = p.faceDia
            s.spindle = p.spindle
            s.feed = p.feed
            s.safeZ = p.safeZ
            s.hNo = p.faceTool
            s.cx = Double(b.midX)
            s.cy = Double(b.midY)
            add("顶面 平面铣 T\(p.faceTool) D\(ncf(p.faceDia))", p.faceTool, GCodeGenerator.generate(s))
        }

        if p.doContour {
            add("外形轮廓铣 T\(p.contourTool) D\(ncf(p.contourDia))", p.contourTool, ContourProg.generate(outline(p)))
        }

        for f in p.feats {
            if f.kind == .hole {
                guard p.doHole else { continue }
                switch p.holeMode {
                case .spiral:
                    var s = PocketSpec()
                    s.mode = .spiral
                    s.spiralDia = f.dia
                    s.toolDia = p.holeDia
                    s.depth = p.height + 1          // 钻穿
                    s.stepDown = p.stepDown
                    s.spindle = p.spindle
                    s.feed = p.feed
                    s.safeZ = p.safeZ
                    s.hNo = p.holeTool
                    s.cx = f.x
                    s.cy = f.y
                    add("孔 Ø\(ncf(f.dia)) @X\(ncf(f.x)) Y\(ncf(f.y)) 螺旋铣 T\(p.holeTool) D\(ncf(p.holeDia))",
                        p.holeTool, GCodeGenerator.generate(s))
                case .g81, .g83:
                    add("孔 Ø\(ncf(f.dia)) @X\(ncf(f.x)) Y\(ncf(f.y)) 钻孔 \(p.holeMode == .g81 ? "G81" : "G83")",
                        p.holeTool, drillBlock(p, f))
                case .tap:
                    add("孔 Ø\(ncf(f.dia)) @X\(ncf(f.x)) Y\(ncf(f.y)) 攻丝 G84 P\(ncf(p.tapPitch))",
                        p.tapTool, tapBlock(p, f))
                }
            } else if p.doPocket && f.kind == .rectPocket {
                var d = asDraw(p, outward: false, template: .rect,
                               dia: p.pocketDia, depth: f.depth, hNo: p.pocketTool)
                d.rectL = f.w
                d.rectW = f.h
                d.rectR = 0
                var code = ContourProg.generate(d)
                code = shift(code, dx: f.x, dy: f.y)
                add("方腔 \(ncf(f.w))×\(ncf(f.h)) 深\(ncf(f.depth)) @X\(ncf(f.x)) Y\(ncf(f.y)) 型腔铣 T\(p.pocketTool) D\(ncf(p.pocketDia))",
                    p.pocketTool, code)
            } else if p.doPocket {
                let d = asDraw(p, outward: false, template: .circle, circleD: f.dia,
                               dia: p.pocketDia, depth: f.depth, hNo: p.pocketTool)
                var code = ContourProg.generate(d)
                code = shift(code, dx: f.x, dy: f.y)
                add("沉台 Ø\(ncf(f.dia)) 深\(ncf(f.depth)) @X\(ncf(f.x)) Y\(ncf(f.y)) 型腔铣 T\(p.pocketTool) D\(ncf(p.pocketDia))",
                    p.pocketTool, code)
            }
        }

        for l in p.innerLoops {
            if l.template == .circle && l.through && !p.doHole { continue }
            if !(l.template == .circle && l.through) && !p.doPocket { continue }
            let depth = l.through ? p.height + 1 : min(l.depth, p.height)
            if l.template == .circle && l.through {
                switch p.holeMode {
                case .spiral:
                    var s = PocketSpec()
                    s.mode = .spiral
                    s.spiralDia = l.circleD
                    s.toolDia = p.holeDia
                    s.depth = depth
                    s.stepDown = p.stepDown
                    s.spindle = p.spindle
                    s.feed = p.feed
                    s.safeZ = p.safeZ
                    s.hNo = p.holeTool
                    s.cx = l.cx
                    s.cy = l.cy
                    add("\(l.name) Ø\(ncf(l.circleD)) @X\(ncf(l.cx)) Y\(ncf(l.cy)) 螺旋铣 T\(p.holeTool) D\(ncf(p.holeDia))",
                        p.holeTool, GCodeGenerator.generate(s))
                case .g81, .g83:
                    let f = PartFeat(kind: .hole, x: l.cx, y: l.cy, dia: l.circleD, depth: depth)
                    add("\(l.name) Ø\(ncf(l.circleD)) @X\(ncf(l.cx)) Y\(ncf(l.cy)) 钻孔 \(p.holeMode == .g81 ? "G81" : "G83")",
                        p.holeTool, drillBlock(p, f))
                case .tap:
                    let f = PartFeat(kind: .hole, x: l.cx, y: l.cy, dia: l.circleD, depth: depth)
                    add("\(l.name) Ø\(ncf(l.circleD)) @X\(ncf(l.cx)) Y\(ncf(l.cy)) 攻丝 G84 P\(ncf(p.tapPitch))",
                        p.tapTool, tapBlock(p, f))
                }
            } else {
                let d = drawForLoop(l, p, depth: depth, dia: p.pocketDia, hNo: p.pocketTool)
                var code = ContourProg.generate(d)
                code = shift(code, dx: l.cx, dy: l.cy)
                add("\(l.name) \(l.template.rawValue) 深\(ncf(depth)) @X\(ncf(l.cx)) Y\(ncf(l.cy)) 型腔铣 T\(p.pocketTool) D\(ncf(p.pocketDia))",
                    p.pocketTool, code)
            }
        }

        var L: [String] = []
        L.append("%")
        L.append("O1010 (绘图编程 · 多工序)")
        let b = bbox(p)
        L.append("( 外形 \(ncf(Double(b.width))) × \(ncf(Double(b.height)))  厚\(ncf(p.height))  顶面余量\(ncf(p.topStock)) )")
        L.append("( 工件坐标系 G\(p.coord)  X0=\(ncf(ox)) Y0=\(ncf(oy)) (草图坐标)  Z0=工件顶面 )")
        L.append("( 共 \(blocks.count) 道工序，每段前面注明了用哪把刀，换刀后从该段重新启动 )")
        L.append("G17 G21 G40 G49 G80 G90 G\(p.coord)")
        L.append("( X0 Y0 为 G\(p.coord) 零点；已按上面基准平移，程序坐标为工件坐标 )")
        L.append(blocks.joined(separator: "\n"))
        L.append("G0 Z\(ncf(p.safeZ, 1))")
        L.append("M5")
        L.append("M9")
        L.append("G28 G91 Z0")
        L.append("G90")
        L.append("M30")
        L.append("%")
        return L.joined(separator: "\n")
    }

    // MARK: - 拼装工具

    /// 去掉子程序自己的抬头/结尾，只留可执行的段落
    static func strip(_ code: String) -> String {
        var out: [String] = []
        for raw in code.components(separatedBy: "\n") {
            let t = raw.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            if t.hasPrefix("%") { continue }
            if t.hasPrefix("O"), t.count > 1, let c = t.dropFirst().first, c.isNumber { continue }
            if t.hasPrefix("G17 G21 G40 G49 G80 G90") { continue }
            if t.hasPrefix("G28") { continue }
            if t == "M30" || t == "M5" || t == "M9" { continue }
            out.append(t)
        }
        return out.joined(separator: "\n")
    }

    /// G81 / G83 钻孔
    static func drillBlock(_ p: PartSpec, _ f: PartFeat) -> String {
        let z = -(p.height + 1)
        var L: [String] = []
        L.append("G0 Z\(ncf(p.safeZ, 1))")
        L.append("( 孔 Ø\(ncf(f.dia)) @X\(ncf(f.x)) Y\(ncf(f.y)) )")
        var line = "G98 G\(p.holeMode == .g81 ? "81" : "83") X\(ncf(f.x)) Y\(ncf(f.y)) Z\(ncf(z, 1)) R2. F\(p.feed)"
        if p.holeMode == .g83 { line += " Q\(ncf(p.peck))" }
        L.append(line)
        L.append("G80")
        return L.joined(separator: "\n")
    }

    /// G84 攻丝：M29 刚性攻丝，F = 螺距 × 转速
    static func tapBlock(_ p: PartSpec, _ f: PartFeat) -> String {
        var L: [String] = []
        L.append("G0 Z\(ncf(p.safeZ, 1))")
        L.append("( 攻丝 Ø\(ncf(f.dia)) P\(ncf(p.tapPitch)) @X\(ncf(f.x)) Y\(ncf(f.y)) )")
        L.append("M29 S\(p.tapRpm)")
        L.append("G98 G84 X\(ncf(f.x)) Y\(ncf(f.y)) Z\(ncf(-(p.height + 1), 1)) R2. F\(ncf(Double(p.tapRpm) * p.tapPitch))")
        L.append("G80")
        return L.joined(separator: "\n")
    }

    /// 只平移 X / Y 数值（I、J 是增量，不能动；注释行不动）
    static func shift(_ code: String, dx: Double, dy: Double) -> String {
        let pattern = "([XY])(-?[0-9]+(?:\\.[0-9]*)?)"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return code }
        var out: [String] = []
        for raw in code.components(separatedBy: "\n") {
            let t = raw.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { out.append(t); continue }
            if t.hasPrefix("(") { out.append(t); continue }
            let ns = t as NSString
            let ms = re.matches(in: t, range: NSRange(location: 0, length: ns.length))
            if ms.isEmpty { out.append(t); continue }
            var line = t
            for m in ms.reversed() {
                guard m.numberOfRanges == 3 else { continue }
                let ax = ns.substring(with: m.range(at: 1))
                let vv = ns.substring(with: m.range(at: 2))
                guard let v = Double(vv) else { continue }
                let nv = ax == "X" ? v + dx : v + dy
                let rep = ax + ncf(nv)
                if let r = Range(m.range, in: line) {
                    line.replaceSubrange(r, with: rep)
                }
            }
            out.append(line)
        }
        return out.joined(separator: "\n")
    }
}
