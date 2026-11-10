package com.sqc.macrogen;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * 宏程序解释器（只支持本 App 生成程序用到的语法子集）：
 *   #1=表达式          变量赋值
 *   IF[条件]THEN赋值    单句条件
 *   WHILE[条件]DO1 ... END1   循环（支持嵌套 DO1/DO2）
 *   G0/G1/G2/G3  X Y Z I J R F   插补（G17 平面，圆弧离散成折线）
 *   G52 / G28 / G40 / G43 / M3 / M5 / M8 / M9 / M30  只跟踪状态，不参与画线
 * 目的：真正执行生成的程序文本，得到和机床一致刀心轨迹，用来查撞刀。
 */
public class MacroInterp {

    /** 轨迹点：位置 + 是否快移 + 来源行号 */
    public static class P {
        public double x, y, z;
        public boolean rapid;
        public int line;
        public P(double x, double y, double z, boolean rapid, int line) {
            this.x = x; this.y = y; this.z = z; this.rapid = rapid; this.line = line;
        }
    }

    public static class Path {
        public List<P> pts = new ArrayList<P>();
        public List<Double> dist = new ArrayList<Double>();  // 累计弧长
        public double maxLen;
        public double minX = 1e9, maxX = -1e9, minY = 1e9, maxY = -1e9, minZ = 1e9, maxZ = -1e9;
        public String error;
        public double totalCut;   // 切削长度
    }

    // ---------- 词法 ----------
    private static class Word {
        char letter;
        String expr;
        Word(char l, String e) { letter = l; expr = e; }
    }

    private final Map<Integer, Double> vars = new HashMap<Integer, Double>();
    private double x, y, z;
    private int motion = 0;
    private Path path;
    private String[] lines;
    private long steps;

    public static Path run(String code) {
        MacroInterp mi = new MacroInterp();
        return mi.exec(code);
    }

    private Path exec(String code) {
        path = new Path();
        path.pts.add(new P(0, 0, 0, true, 0));
        lines = code.split("\n");
        int pc = 0;
        Deque<int[]> loops = new ArrayDeque<int[]>();   // {doNum, whilePc}
        String error = null;
        try {
            while (pc < lines.length) {
                if (++steps > 2000000L) { error = "程序太长或循环不收敛，已停止"; break; }
                String raw = lines[pc];
                String s = strip(raw);
                if (s.length() == 0 || s.equals("%") || s.startsWith("O") && s.length() < 12 && isProgramNo(s)) {
                    pc++; continue;
                }
                if (s.charAt(0) == '#') {
                    assign(s);
                    pc++; continue;
                }
                String up = s.toUpperCase();
                if (up.startsWith("IF")) {
                    int b = up.indexOf('[');
                    int e = match(up, b);
                    double cond = eval(up.substring(b + 1, e));
                    String rest = up.substring(up.indexOf("THEN") + 4).trim();
                    if (cond != 0) {
                        if (rest.startsWith("#")) assign(rest);
                    }
                    pc++; continue;
                }
                if (up.startsWith("WHILE")) {
                    int b = up.indexOf('[');
                    int e = match(up, b);
                    double cond = eval(up.substring(b + 1, e));
                    int doNum = (int) eval(up.substring(up.indexOf("DO", e) + 2));
                    if (cond == 0) {
                        pc = findEnd(pc, doNum);
                    } else {
                        loops.push(new int[]{doNum, pc});
                    }
                    pc++; continue;
                }
                if (up.startsWith("END")) {
                    int doNum = (int) eval(up.substring(3));
                    if (!loops.isEmpty()) {
                        int[] top = loops.peek();
                        if (top[0] == doNum) {
                            loops.pop();   // 结束一轮，交给 WHILE 重新判断（为真会再入栈）
                            pc = top[1];
                            continue;
                        }
                    }
                    pc++; continue;
                }
                // 普通 G/M 语句
                execGCode(s, pc);
                pc++;
            }
        } catch (Exception ex) {
            error = "解析中断：" + ex.getMessage();
        }
        if (error != null) path.error = error;
        buildDistances();
        // 兜底默认视野
        if (path.pts.size() < 2) {
            path.minX = -50; path.maxX = 50; path.minY = -50; path.maxY = 50;
            path.minZ = -10; path.maxZ = 10;
        }
        return path;
    }

    private boolean isProgramNo(String s) {
        // O1001 (型腔宏程序) 这种程序号行，不是坐标语句
        for (int i = 1; i < s.length(); i++) {
            char c = s.charAt(i);
            if (c < '0' || c > '9') return false;
        }
        return true;
    }

    /** 去掉 (注释) 与 ; 之后的内容 */
    private String strip(String raw) {
        StringBuilder sb = new StringBuilder();
        int depth = 0;
        for (int i = 0; i < raw.length(); i++) {
            char c = raw.charAt(i);
            if (c == '(') depth++;
            else if (c == ')') { if (depth > 0) depth--; }
            else if (depth == 0) {
                if (c == ';') break;
                if (c == ' ') continue;
                sb.append(Character.toUpperCase(c));
            }
        }
        return sb.toString();
    }

    private int match(String s, int open) {
        int d = 0;
        for (int i = open; i < s.length(); i++) {
            char c = s.charAt(i);
            if (c == '[') d++;
            else if (c == ']') { d--; if (d == 0) return i; }
        }
        throw new RuntimeException("括号不配对：" + s);
    }

    private int findEnd(int whilePc, int doNum) {
        int nest = 0;
        for (int i = whilePc + 1; i < lines.length; i++) {
            String s = strip(lines[i]).toUpperCase();
            if (s.startsWith("WHILE") && s.contains("DO" + doNum)) nest++;
            else if (s.startsWith("END")) {
                if (s.equals("END" + doNum)) {
                    if (nest == 0) return i;
                    nest--;
                }
            }
        }
        return lines.length;
    }

    // ---------- 赋值与表达式 ----------
    private void assign(String s) {
        int eq = s.indexOf('=');
        if (eq < 0) return;
        int idx = (int) eval(s.substring(1, eq));
        double v = eval(s.substring(eq + 1));
        vars.put(idx, v);
    }

    private double var(int i) {
        Double d = vars.get(i);
        return d == null ? 0 : d;
    }

    /** 递归下降求值，支持 #n、[ ]、+ - * /、GT LT GE LE EQ NE、SIN/COS/TAN/ATAN/SQRT/ABS/FIX/ROUND */
    private double eval(String src) {
        Cur p = new Cur(src, 0);
        double v = rel(p);
        return v;
    }

    private class Cur {
        String s; int i;
        Cur(String s, int i) { this.s = s; this.i = i; }
        boolean end() { return i >= s.length(); }
        char peek() { return end() ? ' ' : s.charAt(i); }
        boolean eat(String t) {
            if (s.startsWith(t, i)) { i += t.length(); return true; }
            return false;
        }
        boolean eat(char c) { if (peek() == c) { i++; return true; } return false; }
    }

    private double rel(Cur p) {
        double a = pAdd(p);
        while (true) {
            if (p.eat("GT")) a = a > pAdd(p) ? 1 : 0;
            else if (p.eat("GE")) a = a >= pAdd(p) ? 1 : 0;
            else if (p.eat("LE")) a = a <= pAdd(p) ? 1 : 0;
            else if (p.eat("LT")) a = a < pAdd(p) ? 1 : 0;
            else if (p.eat("EQ")) a = a == pAdd(p) ? 1 : 0;
            else if (p.eat("NE")) a = a != pAdd(p) ? 1 : 0;
            else return a;
        }
    }

    private double pAdd(Cur p) {
        double a = pMul(p);
        while (true) {
            if (p.eat('+')) a += pMul(p);
            else if (p.eat('-')) a -= pMul(p);
            else return a;
        }
    }

    private double pMul(Cur p) {
        double a = pUnary(p);
        while (true) {
            if (p.eat('*')) a *= pUnary(p);
            else if (p.eat('/')) a /= pUnary(p);
            else return a;
        }
    }

    private double pUnary(Cur p) {
        if (p.eat('-')) return -pUnary(p);
        if (p.eat('+')) return pUnary(p);
        return pPrimary(p);
    }

    private double pPrimary(Cur p) {
        if (p.eat('#')) {
            int start = p.i;
            while (!p.end() && Character.isDigit(p.peek())) p.i++;
            int n = Integer.parseInt(p.s.substring(start, p.i));
            return var(n);
        }
        if (p.eat('[')) {
            double v = rel(p);
            p.eat(']');
            return v;
        }
        if (Character.isLetter(p.peek())) {
            int start = p.i;
            while (!p.end() && Character.isLetter(p.peek())) p.i++;
            String fn = p.s.substring(start, p.i);
            boolean br = p.eat('[');
            double v = rel(p);
            if (br) p.eat(']');
            if (fn.equals("SIN")) return Math.sin(Math.toRadians(v));
            if (fn.equals("COS")) return Math.cos(Math.toRadians(v));
            if (fn.equals("TAN")) return Math.tan(Math.toRadians(v));
            if (fn.equals("ATAN")) return Math.toDegrees(Math.atan(v));
            if (fn.equals("SQRT")) return Math.sqrt(v);
            if (fn.equals("ABS")) return Math.abs(v);
            if (fn.equals("FIX")) return (double) (long) v;
            if (fn.equals("ROUND")) return Math.round(v);
            if (fn.equals("FUP")) return Math.ceil(v);
            return v;
        }
        int start = p.i;
        while (!p.end() && (Character.isDigit(p.peek()) || p.peek() == '.')) p.i++;
        if (start == p.i) {
            // 遇到无法识别的东西，跳过一个字符，避免死循环
            p.i++;
            return 0;
        }
        return Double.parseDouble(p.s.substring(start, p.i));
    }

    // ---------- 逐句执行 ----------
    private void execGCode(String s, int lineNo) {
        List<Word> ws = words(s);
        double nx = x, ny = y, nz = z, i = 0, j = 0, r = Double.NaN;
        boolean hasArcR = false, hasArcIJ = false, hasX = false, hasY = false;
        int gm = -1;
        boolean anyG = false;
        for (Word w : ws) {
            switch (w.letter) {
                case 'G':
                    int g = (int) eval(w.expr);
                    anyG = true;
                    if (g == 0 || g == 1 || g == 2 || g == 3) gm = g;
                    continue;
                case 'X': nx = eval(w.expr); hasX = true; break;
                case 'Y': ny = eval(w.expr); hasY = true; break;
                case 'Z': nz = eval(w.expr); break;
                case 'I': i = eval(w.expr); hasArcIJ = true; break;
                case 'J': j = eval(w.expr); hasArcIJ = true; break;
                case 'R': r = eval(w.expr); hasArcR = true; break;
                default: break;
            }
        }
        // G52 / G28 / G43 / G40 / G80 / G17 … 这类设定语句不参与画线
        if (anyG && gm < 0) return;
        int mode = gm >= 0 ? gm : motion;
        if (gm >= 0) motion = gm;
        if (mode != 0 && mode != 1 && mode != 2 && mode != 3) return;
        if (!hasX && !hasY && z == nz) return;   // 没有位移的语句（M/S/安全指令）

        if (mode == 0 || mode == 1) {
            add(new P(nx, ny, nz, mode == 0, lineNo));
        } else {
            arc(mode, nx, ny, nz, i, j, r, hasArcIJ, hasArcR, lineNo);
        }
        x = nx; y = ny; z = nz;
    }

    /** 把一条语句拆成 (字母, 表达式) —— 表达式可以是 #n / [..] / 数字 / 带负号 */
    private List<Word> words(String s) {
        List<Word> out = new ArrayList<Word>();
        int i = 0;
        while (i < s.length()) {
            char c = s.charAt(i);
            if (Character.isLetter(c)) {
                int st = i + 1;                 // 值的起点（含可能的前导负号）
                int body = st;
                if (body < s.length() && (s.charAt(body) == '-' || s.charAt(body) == '+')) body++;
                String expr = null;
                int next = i + 1;
                if (body < s.length() && s.charAt(body) == '#') {
                    int k = body + 1;
                    while (k < s.length() && Character.isDigit(s.charAt(k))) k++;
                    expr = s.substring(st, k);
                    next = k;
                } else if (body < s.length() && s.charAt(body) == '[') {
                    int k = match(s, body);
                    expr = s.substring(st, k + 1);
                    next = k + 1;
                } else {
                    int k = body;
                    while (k < s.length() && (Character.isDigit(s.charAt(k)) || s.charAt(k) == '.')) k++;
                    if (k > body) { expr = s.substring(st, k); next = k; }
                    else next = i + 1;
                }
                if (expr != null) out.add(new Word(c, expr));
                i = Math.max(next, i + 1);
            } else {
                i++;
            }
        }
        return out;
    }

    private void add(P p) {
        path.pts.add(p);
        grow(p);
    }

    private void grow(P p) {
        if (p.x < path.minX) path.minX = p.x;
        if (p.x > path.maxX) path.maxX = p.x;
        if (p.y < path.minY) path.minY = p.y;
        if (p.y > path.maxY) path.maxY = p.y;
        if (p.z < path.minZ) path.minZ = p.z;
        if (p.z > path.maxZ) path.maxZ = p.z;
    }

    /** G2 顺时针 / G3 逆时针，I/J 为起点到圆心矢量，R 为半径 */
    private void arc(int mode, double nx, double ny, double nz, double i, double j,
                     double r, boolean hasIJ, boolean hasR, int lineNo) {
        double cx, cy;
        if (hasIJ) { cx = x + i; cy = y + j; }
        else if (hasR) {
            double dx = nx - x, dy = ny - y;
            double d = Math.sqrt(dx * dx + dy * dy);
            if (d < 1e-6) { add(new P(nx, ny, nz, false, lineNo)); return; }
            double h = Math.sqrt(Math.max(0, r * r - d * d / 4));
            double mx = (x + nx) / 2, my = (y + ny) / 2;
            double ux = -dy / d, uy = dx / d;   // 垂直方向
            // 优弧/劣弧判定：G2 顺时针 + R 正为劣弧
            double sign = (mode == 3) ? 1 : -1;
            if (r < 0) sign = -sign;
            cx = mx + ux * h * sign;
            cy = my + uy * h * sign;
        } else {
            add(new P(nx, ny, nz, false, lineNo));
            return;
        }
        double rs = Math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy));
        double re = Math.sqrt((nx - cx) * (nx - cx) + (ny - cy) * (ny - cy));
        if (rs < 1e-4) { add(new P(nx, ny, nz, false, lineNo)); return; }
        double a0 = Math.atan2(y - cy, x - cx);
        double a1 = Math.atan2(ny - cy, nx - cx);
        double sweep = a1 - a0;
        if (mode == 3) {                       // G3 逆时针，角度增大
            while (sweep <= 0) sweep += Math.PI * 2;
        } else {                               // G2 顺时针，角度减小
            while (sweep >= 0) sweep -= Math.PI * 2;
        }
        // 误差 0.15mm 以内的离散精度
        int n = (int) Math.max(4, Math.min(160, Math.abs(sweep) * rs / 0.15));
        for (int k = 1; k <= n; k++) {
            double t = k / (double) n;
            double a = a0 + sweep * t;
            double zz = z + (nz - z) * t;
            add(new P(cx + Math.cos(a) * rs, cy + Math.sin(a) * rs, zz, false, lineNo));
        }
        // 收尾对齐终点
        add(new P(nx, ny, nz, false, lineNo));
    }

    private void buildDistances() {
        double acc = 0;
        path.dist.add(0.0);
        for (int k = 1; k < path.pts.size(); k++) {
            P a = path.pts.get(k - 1), b = path.pts.get(k);
            double d = Math.sqrt((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)
                    + (b.z - a.z) * (b.z - a.z));
            acc += d;
            if (!b.rapid) path.totalCut += d;
            path.dist.add(acc);
        }
        path.maxLen = acc;
    }
}
