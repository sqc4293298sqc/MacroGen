import Foundation

/// 程序输出格式：宏程序保留 #变量/WHILE，G 代码把宏展开成普通坐标。
enum ProgramFormat: String, CaseIterable, Identifiable, Codable {
    case macro = "宏程序"
    case gcode = "G代码"

    var id: String { rawValue }

    var detail: String {
        switch self {
        case .macro:
            return "保留现有宏程序写法：#变量、WHILE 循环和 G41/G42 刀补"
        case .gcode:
            return "把同一份宏展开成普通 G 代码：变量和循环算成固定坐标"
        }
    }
}

/// 把本 App 生成的 FANUC 宏程序展开成普通 G 代码，并做 Siemens 兼容输出。
/// 只处理本 App 自己生成的宏语法（#变量 / WHILE / IF / TAN/FIX 等），
/// 不是通用 FANUC 宏解释器；G43/G28/G52 等仍需按目标机床核对。
enum PostProcessor {
    /// 按用户选择的格式输出：宏程序原样返回，G 代码用现有展开器转换。
    static func output(_ macro: String, format: ProgramFormat) -> String {
        switch format {
        case .macro: return macro
        case .gcode: return fanuc(macro)
        }
    }

    /// FANUC 风格普通 G 代码：保留 O 号和 FANUC 括号注释，只展开宏语法。
    static func fanuc(_ code: String) -> String {
        let expanded = MacroExpander.expand(code)
        var out: [String] = []
        out.append("( 普通 G 代码：宏变量与 WHILE/IF 已展开 )")
        out.append("( 由 MacroGen 现有宏程序转换，上机前核对 G43/G28/G52 与 D 刀补 )")
        for raw in expanded.components(separatedBy: "\n") {
            let t = raw.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            out.append(t)
        }
        return out.joined(separator: "\n") + "\n"
    }

    /// 把一个完整宏程序拆成 FANUC M98 主程序 + 子程序。
    /// 主程序只负责调用；子程序保留原来的变量、WHILE/IF/GOTO 和刀路。
    static func m98Bundle(_ code: String, subprogramNo: Int = 9001) -> (main: String, sub: String) {
        let normalized = code.replacingOccurrences(of: "\r\n", with: "\n")
        var lines = normalized.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        while let first = lines.first, first == "%" { lines.removeFirst() }
        var mainNo = 1
        if let first = lines.first, first.hasPrefix("O"), first.count > 1,
           let value = Int(first.dropFirst()) {
            mainNo = value
            lines.removeFirst()
        }
        while let last = lines.last, last == "M30" || last == "M02" || last == "%" {
            lines.removeLast()
        }
        let subNo = max(1, min(9999, subprogramNo))
        var main: [String] = []
        main.append("O\(mainNo)")
        main.append("( M98 子程序调用 · 子程序 O\(subNo) )")
        main.append("( 主程序只调用，子程序保留宏变量/WHILE/IF/GOTO )")
        main.append("M98 P\(subNo)")
        main.append("M30")
        var sub: [String] = []
        sub.append("O\(subNo)")
        sub.append(contentsOf: lines)
        sub.append("M99")
        return (main.joined(separator: "\n") + "\n", sub.joined(separator: "\n") + "\n")
    }

    static func siemens(_ code: String) -> String {
        let expanded = MacroExpander.expand(code)
        var out: [String] = []
        out.append("; Siemens 840D 兼容子集：宏已展开为普通G代码")
        out.append("; 上机前核对 G43 刀长、G28/G74 回零、G52 局部坐标和 D 刀补")
        for raw in expanded.components(separatedBy: "\n") {
            let t = raw.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            if t.hasPrefix("%") { continue }
            if t.hasPrefix("O"), t.count > 1,
               let c = t.dropFirst().first, c.isNumber { continue }
            let split = MacroExpander.splitComment(t)
            let body = split.code.trimmingCharacters(in: .whitespaces)
            let comment = split.comment
            if body.isEmpty {
                if let comment { out.append("; \(comment)") }
                continue
            }
            if let comment {
                out.append("\(body) ; \(comment)")
            } else {
                out.append(body)
            }
        }
        return out.joined(separator: "\n")
    }
}

private enum MacroExpander {
    struct Split { var code: String; var comment: String? }

    static func splitComment(_ line: String) -> Split {
        guard let open = line.firstIndex(of: "(") else { return Split(code: line, comment: nil) }
        var depth = 0
        var close: String.Index? = nil
        var i = open
        while i < line.endIndex {
            let ch = line[i]
            if ch == "(" { depth += 1 }
            if ch == ")" {
                depth -= 1
                if depth == 0 { close = i; break }
            }
            i = line.index(after: i)
        }
        guard let c = close else { return Split(code: line, comment: nil) }
        let code = String(line[..<open])
        let comment = String(line[line.index(after: open)..<c])
        return Split(code: code, comment: comment)
    }

    static func expand(_ code: String) -> String {
        let lines = code.components(separatedBy: "\n")
        var vars: [Int: Double] = [:]
        var out: [String] = []

        func clean(_ s: String) -> String {
            splitComment(s).code.trimmingCharacters(in: .whitespaces)
        }

        func firstBracket(_ s: String, prefix: String) -> String? {
            guard let r = s.range(of: prefix + "[") else { return nil }
            let start = r.upperBound
            var depth = 1
            var i = start
            while i < s.endIndex {
                let ch = s[i]
                if ch == "[" { depth += 1 }
                if ch == "]" {
                    depth -= 1
                    if depth == 0 { return String(s[start..<i]) }
                }
                i = s.index(after: i)
            }
            return nil
        }

        func condition(_ expr: String) -> Bool {
            let e = expr.replacingOccurrences(of: " ", with: "").uppercased()
            for op in ["LE", "GE", "NE", "LT", "GT", "EQ"] {
                if let r = e.range(of: op) {
                    let a = String(e[..<r.lowerBound])
                    let b = String(e[r.upperBound...])
                    let av = evalExpr(a, vars), bv = evalExpr(b, vars)
                    switch op {
                    case "LE": return av <= bv + 1e-9
                    case "GE": return av >= bv - 1e-9
                    case "NE": return abs(av - bv) > 1e-9
                    case "LT": return av < bv - 1e-9
                    case "GT": return av > bv + 1e-9
                    default: return abs(av - bv) <= 1e-9
                    }
                }
            }
            return abs(evalExpr(e, vars)) > 1e-9
        }

        func format(_ v: Double) -> String {
            if abs(v) < 5e-4 { return "0" }
            var s = String(format: "%.3f", v)
            while s.contains(".") && s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
            return s == "-0" ? "0" : s
        }

        func substitute(_ raw: String) -> String {
            var s = raw
            // 先算最内层方括号，再替换 #变量；这样 [..#..] 也能算。
            var guardCount = 0
            while guardCount < 200 {
                guardCount += 1
                guard let open = s.range(of: "[", options: .backwards) else { break }
                var depth = 0
                var close: String.Index? = nil
                var i = open.lowerBound
                while i < s.endIndex {
                    if s[i] == "[" { depth += 1 }
                    if s[i] == "]" {
                        depth -= 1
                        if depth == 0 { close = i; break }
                    }
                    i = s.index(after: i)
                }
                guard let c = close else { break }
                let inner = String(s[s.index(after: open.lowerBound)..<c])
                let value = evalExpr(inner, vars)
                s.replaceSubrange(open.lowerBound...c, with: format(value))
            }
            // 剩下的 #变量
            if let re = try? NSRegularExpression(pattern: "#([0-9]+)") {
                let ns = s as NSString
                let matches = re.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed()
                var result = s
                for m in matches {
                    let n = Int(ns.substring(with: m.range(at: 1))) ?? 0
                    let v = vars[n] ?? 0
                    if let r = Range(m.range, in: result) {
                        result.replaceSubrange(r, with: format(v))
                    }
                }
                s = result
            }
            return s
        }

        func process(_ raw: String) {
            let split = splitComment(raw)
            let t = split.code.trimmingCharacters(in: .whitespaces)
            if t.isEmpty {
                if let c = split.comment { out.append("( \(c) )") }
                return
            }
            if t.hasPrefix("#") {
                let body = t.replacingOccurrences(of: " ", with: "")
                if let eq = body.firstIndex(of: "=") {
                    let left = String(body[body.index(after: body.startIndex)..<eq])
                    if let n = Int(left) {
                        let rhs = String(body[body.index(after: eq)...])
                        vars[n] = evalExpr(rhs, vars)
                    }
                }
                return
            }
            if t.hasPrefix("WHILE[") { return }
            if t.hasPrefix("END") { return }
            if t.hasPrefix("IF[") { return }
            out.append(substitute(t) + (split.comment.map { " (\($0))" } ?? ""))
        }

        func findEnd(_ start: Int, _ to: Int) -> Int {
            var depth = 0
            var i = start + 1
            while i < to {
                let t = clean(lines[i])
                if t.hasPrefix("WHILE[") { depth += 1 }
                else if t.hasPrefix("END") {
                    if depth == 0 { return i }
                    depth -= 1
                }
                i += 1
            }
            return to - 1
        }

        func run(_ from: Int, _ to: Int) {
            var i = from
            while i < to {
                let t = clean(lines[i])
                if t.hasPrefix("WHILE[") {
                    let end = findEnd(i, to)
                    guard let cond = firstBracket(t, prefix: "WHILE") else { i = end + 1; continue }
                    var n = 0
                    while condition(cond) && n < 200000 {
                        run(i + 1, end)
                        n += 1
                    }
                    i = end + 1
                    continue
                }
                if t.hasPrefix("IF[") {
                    if let cond = firstBracket(t, prefix: "IF"),
                       let thenRange = t.range(of: "THEN") {
                        if condition(cond) {
                            let rest = String(t[thenRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                            if !rest.isEmpty { process(rest) }
                        }
                    }
                    i += 1
                    continue
                }
                process(lines[i])
                i += 1
            }
        }

        run(0, lines.count)
        return out.joined(separator: "\n")
    }

    // MARK: - 表达式

    private enum Tok {
        case number(Double)
        case variable(Int)
        case op(Character)
        case left, right
        case word(String)
        case end
    }

    private static func tokenize(_ s: String) -> [Tok] {
        var out: [Tok] = []
        var i = s.startIndex
        func number(_ start: String.Index) -> String.Index {
            var j = start
            var sawDigit = false
            while j < s.endIndex {
                let c = s[j]
                if c.isNumber || c == "." { sawDigit = true; j = s.index(after: j); continue }
                if c == "e" || c == "E" {
                    j = s.index(after: j)
                    if j < s.endIndex, s[j] == "+" || s[j] == "-" { j = s.index(after: j) }
                    continue
                }
                break
            }
            return sawDigit ? j : start
        }
        while i < s.endIndex {
            let c = s[i]
            if c == " " { i = s.index(after: i); continue }
            if c == "#" {
                var j = s.index(after: i)
                var digits = ""
                while j < s.endIndex, s[j].isNumber { digits.append(s[j]); j = s.index(after: j) }
                out.append(.variable(Int(digits) ?? 0)); i = j; continue
            }
            if c.isNumber || c == "." {
                let j = number(i)
                out.append(.number(Double(String(s[i..<j])) ?? 0))
                i = j; continue
            }
            if c == "+" || c == "-" || c == "*" || c == "/" {
                out.append(.op(c)); i = s.index(after: i); continue
            }
            if c == "[" || c == "(" { out.append(.left); i = s.index(after: i); continue }
            if c == "]" || c == ")" { out.append(.right); i = s.index(after: i); continue }
            if c.isLetter {
                var j = i
                var word = ""
                while j < s.endIndex, s[j].isLetter { word.append(s[j]); j = s.index(after: j) }
                out.append(.word(word.uppercased())); i = j; continue
            }
            i = s.index(after: i)
        }
        out.append(.end)
        return out
    }

    private static func evalExpr(_ text: String, _ vars: [Int: Double]) -> Double {
        let tokens = tokenize(text)
        var i = 0
        func peek() -> Tok { tokens[min(i, tokens.count - 1)] }
        func take() -> Tok { let t = peek(); i += 1; return t }
        func primary() -> Double {
            let t = take()
            switch t {
            case .number(let v): return v
            case .variable(let n): return vars[n] ?? 0
            case .op(let c) where c == "-": return -primary()
            case .op(let c) where c == "+": return primary()
            case .left:
                let v = expr()
                _ = take()
                return v
            case .word(let w):
                var a: Double = 0
                if case .left = peek() {
                    _ = take()
                    a = expr()
                    _ = take()
                }
                switch w {
                case "ABS": return abs(a)
                case "SQRT": return sqrt(max(0, a))
                case "FIX": return floor(a)
                case "ROUND": return round(a)
                case "TAN": return tan(a * .pi / 180)
                case "SIN": return sin(a * .pi / 180)
                case "COS": return cos(a * .pi / 180)
                default: return a
                }
            default: return 0
            }
        }
        func term() -> Double {
            var v = primary()
            while true {
                switch peek() {
                case .op(let c) where c == "*": _ = take(); v *= primary()
                case .op(let c) where c == "/": _ = take(); let d = primary(); v = abs(d) < 1e-12 ? 0 : v / d
                default: return v
                }
            }
        }
        func expr() -> Double {
            var v = term()
            while true {
                switch peek() {
                case .op(let c) where c == "+": _ = take(); v += term()
                case .op(let c) where c == "-": _ = take(); v -= term()
                default: return v
                }
            }
        }
        return expr()
    }
}
