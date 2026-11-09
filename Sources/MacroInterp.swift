import Foundation

/// 轨迹点：位置 + 是否快移 + 来源行号
struct SimPoint {
    var x: Double
    var y: Double
    var z: Double
    var rapid: Bool
    var line: Int
}

/// 解释器输出：点列 + 累计弧长 + 包围盒
struct SimPath {
    var pts: [SimPoint] = []
    var dist: [Double] = []
    var maxLen: Double = 0
    var minX: Double = 1e9, maxX: Double = -1e9
    var minY: Double = 1e9, maxY: Double = -1e9
    var minZ: Double = 1e9, maxZ: Double = -1e9
    var totalCut: Double = 0
    var error: String?
}

/// 宏程序解释器：真执行本 App 生成的 G 代码（含 #变量 / WHILE / IF / 圆弧）
/// 只支持生成程序用到的语法子集，目的不是通用仿真器，而是验自己生成的程序。
final class MacroInterp {

    private struct Word {
        var letter: Character
        var expr: String
    }

    private final class Cur {
        var s: [Character]
        var i: Int = 0
        init(_ str: String) { s = Array(str) }
        var ended: Bool { i >= s.count }
        func peek() -> Character { ended ? " " : s[i] }
        func eat(_ t: String) -> Bool {
            let tc = Array(t)
            if i + tc.count > s.count { return false }
            for k in 0..<tc.count where s[i + k] != tc[k] { return false }
            i += tc.count
            return true
        }
        func eat(_ c: Character) -> Bool { if peek() == c { i += 1; return true }; return false }
    }

    private var vars: [Int: Double] = [:]
    private var px: Double = 0, py: Double = 0, pz: Double = 0
    private var motion: Int = 0
    private var path = SimPath()
    private var lines: [String] = []
    private var steps = 0

    static func run(_ code: String) -> SimPath {
        MacroInterp().exec(code)
    }

    private func exec(_ code: String) -> SimPath {
        path = SimPath()
        path.pts.append(SimPoint(x: 0, y: 0, z: 0, rapid: true, line: 0))
        lines = code.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var pc = 0
        var loops: [(Int, Int)] = []       // (doNum, whilePc)
        var err: String?

        while pc < lines.count {
            steps += 1
            if steps > 2_000_000 { err = "程序太长或循环不收敛，已停止"; break }
            let s = strip(lines[pc])
            if s.isEmpty || s == "%" { pc += 1; continue }
            if s.first == "O", isProgramNo(s) { pc += 1; continue }

            if s.first == "#" { assign(s); pc += 1; continue }

            if s.hasPrefix("WHILE") {
                let open = s.firstIndex(of: "[")!
                let close = match(s, open)
                let cond = eval(String(s[s.index(after: open)..<close]))
                let rest = String(s[s.index(close, offsetBy: 1)...])
                let numStr = rest.replacingOccurrences(of: "DO", with: "")
                let doNum = Int(eval(numStr))
                if cond == 0 {
                    pc = findEnd(pc, doNum)
                } else {
                    loops.append((doNum, pc))
                }
                pc += 1; continue
            }

            if s.hasPrefix("IF") {
                let open = s.firstIndex(of: "[")!
                let close = match(s, open)
                let cond = eval(String(s[s.index(after: open)..<close]))
                if let r = s.range(of: "THEN") {
                    let rest = String(s[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                    if cond != 0, rest.first == "#" { assign(rest) }
                }
                pc += 1; continue
            }

            if s.hasPrefix("END") {
                let numStr = String(s.dropFirst(3))
                let doNum = Int(eval(numStr))
                if let top = loops.last, top.0 == doNum {
                    loops.removeLast()      // 结束一轮，交给 WHILE 重新判断
                    pc = top.1
                    continue
                }
                pc += 1; continue
            }

            execGCode(s, pc)
            pc += 1
        }

        path.error = err
        buildDistances()
        if path.pts.count < 2 {
            path.minX = -50; path.maxX = 50
            path.minY = -50; path.maxY = 50
            path.minZ = -10; path.maxZ = 10
        }
        return path
    }

    private func isProgramNo(_ s: String) -> Bool {
        for c in s.dropFirst() where !c.isNumber { return false }
        return true
    }

    /// 去掉 (注释) 与 ; 之后的内容，并大写去空格
    private func strip(_ raw: String) -> String {
        var out = ""
        var depth = 0
        for c in raw {
            if c == "(" { depth += 1 }
            else if c == ")" { if depth > 0 { depth -= 1 } }
            else if depth == 0 {
                if c == ";" { break }
                if c == " " { continue }
                out.append(contentsOf: String(c).uppercased())
            }
        }
        return out
    }

    /// 从 open 处的 [ 找到配对的 ]（返回其下标）
    private func match(_ str: String, _ open: String.Index) -> String.Index {
        var d = 0
        var idx = open
        while idx < str.endIndex {
            if str[idx] == "[" { d += 1 }
            else if str[idx] == "]" {
                d -= 1
                if d == 0 { return idx }
            }
            idx = str.index(after: idx)
        }
        return str.index(before: str.endIndex)
    }

    private func findEnd(_ whilePc: Int, _ doNum: Int) -> Int {
        var nest = 0
        var k = whilePc + 1
        while k < lines.count {
            let s = strip(lines[k])
            if s.hasPrefix("WHILE") && s.contains("DO\(doNum)") { nest += 1 }
            else if s.hasPrefix("END"), s == "END\(doNum)" {
                if nest == 0 { return k }
                nest -= 1
            }
            k += 1
        }
        return lines.count
    }

    // MARK: - 变量与表达式

    private func assign(_ s: String) {
        guard let eq = s.firstIndex(of: "=") else { return }
        let idx = Int(eval(String(s[s.index(after: s.startIndex)..<eq])))
        let v = eval(String(s[s.index(after: eq)...]))
        vars[idx] = v
    }

    private func variable(_ i: Int) -> Double { vars[i] ?? 0 }

    private func eval(_ src: String) -> Double {
        let p = Cur(src)
        return rel(p)
    }

    private func rel(_ p: Cur) -> Double {
        var a = pAdd(p)
        while true {
            if p.eat("GT") { a = a > pAdd(p) ? 1 : 0 }
            else if p.eat("GE") { a = a >= pAdd(p) ? 1 : 0 }
            else if p.eat("LE") { a = a <= pAdd(p) ? 1 : 0 }
            else if p.eat("LT") { a = a < pAdd(p) ? 1 : 0 }
            else if p.eat("EQ") { a = a == pAdd(p) ? 1 : 0 }
            else if p.eat("NE") { a = a != pAdd(p) ? 1 : 0 }
            else { return a }
        }
    }

    private func pAdd(_ p: Cur) -> Double {
        var a = pMul(p)
        while true {
            if p.eat("+") { a += pMul(p) }
            else if p.eat("-") { a -= pMul(p) }
            else { return a }
        }
    }

    private func pMul(_ p: Cur) -> Double {
        var a = pUnary(p)
        while true {
            if p.eat("*") { a *= pUnary(p) }
            else if p.eat("/") { a /= pUnary(p) }
            else { return a }
        }
    }

    private func pUnary(_ p: Cur) -> Double {
        if p.eat("-") { return -pUnary(p) }
        if p.eat("+") { return pUnary(p) }
        return pPrimary(p)
    }

    private func pPrimary(_ p: Cur) -> Double {
        if p.eat("#") {
            var digits = ""
            while p.peek().isNumber { digits.append(p.peek()); p.i += 1 }
            return variable(Int(digits) ?? 0)
        }
        if p.eat("[") {
            let v = rel(p)
            _ = p.eat("]")
            return v
        }
        if p.peek().isLetter {
            var name = ""
            while p.peek().isLetter { name.append(p.peek()); p.i += 1 }
            let br = p.eat("[")
            let v = rel(p)
            if br { _ = p.eat("]") }
            switch name {
            case "SIN": return sin(v * .pi / 180)
            case "COS": return cos(v * .pi / 180)
            case "TAN": return tan(v * .pi / 180)
            case "ATAN": return atan(v) * 180 / .pi
            case "SQRT": return sqrt(max(0, v))
            case "ABS": return abs(v)
            case "FIX": return (v < 0 ? ceil(v) : floor(v))
            case "ROUND": return v.rounded()
            case "FUP": return ceil(v)
            default: return v
            }
        }
        var num = ""
        while !p.ended, p.peek().isNumber || p.peek() == "." { num.append(p.peek()); p.i += 1 }
        if num.isEmpty { p.i += 1; return 0 }
        return Double(num) ?? 0
    }

    // MARK: - 逐句执行

    private func execGCode(_ s: String, _ lineNo: Int) {
        var nx = px, ny = py, nz = pz
        var ci = 0.0, cj = 0.0, cr = Double.nan
        var hasIJ = false, hasR = false, hasX = false, hasY = false
        var gm = -1
        var anyG = false

        for w in words(s) {
            switch w.letter {
            case "G":
                let g = Int(eval(w.expr))
                anyG = true
                if g == 0 || g == 1 || g == 2 || g == 3 { gm = g }
            case "X": nx = eval(w.expr); hasX = true
            case "Y": ny = eval(w.expr); hasY = true
            case "Z": nz = eval(w.expr)
            case "I": ci = eval(w.expr); hasIJ = true
            case "J": cj = eval(w.expr); hasIJ = true
            case "R": cr = eval(w.expr); hasR = true
            default: break
            }
        }

        // G52 / G28 / G43 / G40 / G80 / G17 这类设定语句不画线
        if anyG && gm < 0 { return }
        let mode = gm >= 0 ? gm : motion
        if gm >= 0 { motion = gm }
        guard mode >= 0 && mode <= 3 else { return }
        if !hasX && !hasY && pz == nz { return }

        if mode == 0 || mode == 1 {
            add(SimPoint(x: nx, y: ny, z: nz, rapid: mode == 0, line: lineNo))
        } else {
            arc(mode, nx, ny, nz, ci, cj, cr, hasIJ, hasR, lineNo)
        }
        px = nx; py = ny; pz = nz
    }

    /// 拆词：(字母, 表达式)，表达式可以是 #n / [..] / 数字 / 带负号
    private func words(_ s: String) -> [Word] {
        let cs = Array(s)
        var out: [Word] = []
        var i = 0
        while i < cs.count {
            let c = cs[i]
            guard c.isLetter else { i += 1; continue }
            var st = i + 1
            var body = st
            if body < cs.count, cs[body] == "-" || cs[body] == "+" { body += 1 }
            var expr: String?
            var next = i + 1
            if body < cs.count, cs[body] == "#" {
                var k = body + 1
                while k < cs.count, cs[k].isNumber { k += 1 }
                expr = String(cs[st..<k]); next = k
            } else if body < cs.count, cs[body] == "[" {
                var d = 0
                var k = body
                while k < cs.count {
                    if cs[k] == "[" { d += 1 }
                    else if cs[k] == "]" { d -= 1; if d == 0 { break } }
                    k += 1
                }
                let end = min(k + 1, cs.count)
                expr = String(cs[st..<end]); next = end
            } else {
                var k = body
                while k < cs.count, cs[k].isNumber || cs[k] == "." { k += 1 }
                if k > body { expr = String(cs[st..<k]); next = k } else { next = i + 1 }
            }
            if let e = expr { out.append(Word(letter: c, expr: e)) }
            i = max(next, i + 1)
        }
        return out
    }

    private func add(_ p: SimPoint) {
        path.pts.append(p)
        path.minX = min(path.minX, p.x); path.maxX = max(path.maxX, p.x)
        path.minY = min(path.minY, p.y); path.maxY = max(path.maxY, p.y)
        path.minZ = min(path.minZ, p.z); path.maxZ = max(path.maxZ, p.z)
    }

    /// G2 顺时针 / G3 逆时针，I/J 为起点到圆心矢量，R 为半径
    private func arc(_ mode: Int, _ nx: Double, _ ny: Double, _ nz: Double,
                     _ i: Double, _ j: Double, _ r: Double,
                     _ hasIJ: Bool, _ hasR: Bool, _ lineNo: Int) {
        var cx = 0.0, cy = 0.0
        if hasIJ {
            cx = px + i; cy = py + j
        } else if hasR, !r.isNaN {
            let dx = nx - px, dy = ny - py
            let d = sqrt(dx * dx + dy * dy)
            if d < 1e-6 {
                add(SimPoint(x: nx, y: ny, z: nz, rapid: false, line: lineNo)); return
            }
            let h = sqrt(max(0, r * r - d * d / 4))
            let mx = (px + nx) / 2, my = (py + ny) / 2
            let ux = -dy / d, uy = dx / d
            var sgn = mode == 3 ? 1.0 : -1.0
            if r < 0 { sgn = -sgn }
            cx = mx + ux * h * sgn
            cy = my + uy * h * sgn
        } else {
            add(SimPoint(x: nx, y: ny, z: nz, rapid: false, line: lineNo)); return
        }
        let rs = sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy))
        guard rs > 1e-4 else {
            add(SimPoint(x: nx, y: ny, z: nz, rapid: false, line: lineNo)); return
        }
        let a0 = atan2(py - cy, px - cx)
        let a1 = atan2(ny - cy, nx - cx)
        var sweep = a1 - a0
        if mode == 3 { while sweep <= 0 { sweep += .pi * 2 } }
        else { while sweep >= 0 { sweep -= .pi * 2 } }
        let n = max(4, min(160, Int(abs(sweep) * rs / 0.15)))
        for k in 1...n {
            let t = Double(k) / Double(n)
            let a = a0 + sweep * t
            add(SimPoint(x: cx + cos(a) * rs, y: cy + sin(a) * rs,
                         z: pz + (nz - pz) * t, rapid: false, line: lineNo))
        }
        add(SimPoint(x: nx, y: ny, z: nz, rapid: false, line: lineNo))
    }

    private func buildDistances() {
        var acc = 0.0
        path.dist = [0]
        guard path.pts.count > 1 else { path.maxLen = 0; return }
        for k in 1..<path.pts.count {
            let a = path.pts[k - 1], b = path.pts[k]
            let d = sqrt(pow(b.x - a.x, 2) + pow(b.y - a.y, 2) + pow(b.z - a.z, 2))
            acc += d
            if !b.rapid { path.totalCut += d }
            path.dist.append(acc)
        }
        path.maxLen = acc
    }
}
