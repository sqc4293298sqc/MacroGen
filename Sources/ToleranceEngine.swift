import Foundation

/// 尺寸公差计算：GB/T 1800.2（ISO 286-2）数值，内部按 μm 计算，显示按 mm
enum ToleranceEngine {

    static let ranges: [(Double, Double)] = [
        (0, 3), (3, 6), (6, 10), (10, 18), (18, 30), (30, 50), (50, 80),
        (80, 120), (120, 180), (180, 250), (250, 315), (315, 400), (400, 500)
    ]

    // IT5 ~ IT16（μm）
    static let itTable: [[Int]] = [
        [4, 5, 6, 8, 9, 11, 13, 15, 18, 20, 23, 25, 27],
        [6, 8, 9, 11, 13, 16, 19, 22, 25, 29, 32, 36, 40],
        [10, 12, 15, 18, 21, 25, 30, 35, 40, 46, 52, 57, 63],
        [14, 18, 22, 27, 33, 39, 46, 54, 63, 72, 81, 89, 97],
        [25, 30, 36, 43, 52, 62, 74, 87, 100, 115, 130, 140, 155],
        [40, 48, 58, 70, 84, 100, 120, 140, 160, 185, 210, 230, 250],
        [60, 75, 90, 110, 130, 160, 190, 220, 250, 290, 320, 360, 400],
        [100, 120, 150, 180, 210, 250, 300, 350, 400, 460, 520, 570, 630],
        [140, 180, 220, 270, 330, 390, 460, 540, 630, 720, 810, 890, 970],
        [250, 300, 360, 430, 520, 620, 740, 870, 1000, 1150, 1300, 1400, 1550],
        [400, 480, 580, 700, 840, 1000, 1200, 1400, 1600, 1850, 2100, 2300, 2500],
        [640, 750, 900, 1100, 1300, 1600, 1900, 2200, 2500, 2900, 3200, 3600, 4000]
    ]

    static let dEs = [-20, -30, -40, -50, -65, -80, -100, -120, -145, -170, -190, -210, -230]
    static let eEs = [-14, -20, -25, -32, -40, -50, -60, -72, -85, -100, -110, -125, -135]
    static let fEs = [-6, -10, -13, -16, -20, -25, -30, -36, -43, -50, -56, -62, -68]
    static let gEs = [-2, -4, -5, -6, -7, -9, -10, -12, -14, -15, -17, -18, -20]

    static let kEi = [0, 1, 1, 1, 2, 2, 2, 3, 3, 4, 4, 4, 5]
    static let mEi = [2, 4, 6, 7, 8, 9, 11, 13, 15, 17, 20, 21, 23]
    static let nEi = [4, 8, 10, 12, 15, 17, 20, 23, 27, 31, 34, 37, 40]
    static let pEi = [6, 12, 15, 18, 22, 26, 32, 37, 43, 50, 56, 62, 68]

    static let holePositions = ["H", "G", "F", "E", "D", "JS"]
    static let shaftPositions = ["h", "g", "f", "e", "d", "js", "k", "m", "n", "p"]
    static let minGrade = 5
    static let maxGrade = 12

    static func rangeIndex(_ d: Double) -> Int? {
        for (i, r) in ranges.enumerated() {
            if d > r.0 && d <= r.1 { return i }
        }
        if d > 0 && d <= 3 { return 0 }
        return nil
    }

    static func it(_ size: Double, _ grade: Int) -> Int? {
        guard let i = rangeIndex(size), grade >= minGrade, grade <= maxGrade else { return nil }
        return itTable[grade - minGrade][i]
    }

    /// 返回 (上偏差, 下偏差, 公差)，单位 μm
    static func shaftDev(_ pos: String, _ size: Double, _ grade: Int) -> (Int, Int, Int)? {
        guard let i = rangeIndex(size), let t = it(size, grade) else { return nil }
        switch pos {
        case "js": return (t / 2, -t / 2, t)
        case "h": return (0, -t, t)
        case "g": return (gEs[i], gEs[i] - t, t)
        case "f": return (fEs[i], fEs[i] - t, t)
        case "e": return (eEs[i], eEs[i] - t, t)
        case "d": return (dEs[i], dEs[i] - t, t)
        case "k":
            let ei = grade <= 7 ? kEi[i] : 0
            return (ei + t, ei, t)
        case "m": return (mEi[i] + t, mEi[i], t)
        case "n": return (nEi[i] + t, nEi[i], t)
        case "p": return (pEi[i] + t, pEi[i], t)
        default: return nil
        }
    }

    static func holeDev(_ pos: String, _ size: Double, _ grade: Int) -> (Int, Int, Int)? {
        guard let _ = rangeIndex(size), let t = it(size, grade) else { return nil }
        if pos == "JS" { return (t / 2, -t / 2, t) }
        if pos == "H" { return (t, 0, t) }
        guard let s = shaftDev(pos.lowercased(), size, grade) else { return nil }
        let ei = -s.0
        return (ei + t, ei, t)
    }

    static func textHalf(_ um: Int) -> String {
        String(format: "%+.4f", Double(um) / 2000.0)
    }

    static func text(_ um: Int) -> String {
        String(format: "%+.3f", Double(um) / 1000.0)
    }

    static func fitType(hole: String, shaft: String, size: Double, hg: Int, sg: Int) -> String {
        guard let h = holeDev(hole, size, hg), let s = shaftDev(shaft, size, sg) else { return "" }
        let maxGap = h.0 - s.1
        let minGap = h.1 - s.0
        if minGap > 0 { return "间隙配合" }
        if maxGap < 0 { return "过盈配合" }
        return "过渡配合"
    }
}
