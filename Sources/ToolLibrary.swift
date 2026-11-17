import Foundation

enum ToolKind: String, CaseIterable, Identifiable, Codable {
    case flat = "平底刀"
    case ball = "球刀"
    case drill = "钻头"
    case tap = "丝锥"
    case chamfer = "倒角刀"
    var id: String { rawValue }
}

struct ToolRecord: Identifiable, Equatable, Codable {
    var id = UUID()
    var name: String = "新刀具"
    var no: Int = 1
    var dia: Double = 6
    var kind: ToolKind = .flat
    var rpm: Int = 2000
    var feed: Int = 400
    var flutes: Int = 2

    var summary: String { "T\(no)  Ø\(fmt(dia))  \(kind.rawValue)" }

    private func fmt(_ v: Double) -> String {
        String(format: "%.2f", v)
    }
}

/// 刀具库跟工程分开存：换工程也保留常用刀具。
enum ToolLibraryStore {
    private static let key = "macrogen.toolLibrary.v1"

    static func load() -> [ToolRecord] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([ToolRecord].self, from: data),
              !list.isEmpty else {
            return defaults
        }
        return list
    }

    static func save(_ list: [ToolRecord]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static let defaults: [ToolRecord] = [
        ToolRecord(name: "飞面刀", no: 1, dia: 6, kind: .flat, rpm: 2500, feed: 600, flutes: 3),
        ToolRecord(name: "轮廓刀", no: 2, dia: 8, kind: .flat, rpm: 2000, feed: 450, flutes: 3),
        ToolRecord(name: "钻头", no: 3, dia: 6, kind: .drill, rpm: 1200, feed: 120, flutes: 2),
        ToolRecord(name: "型腔刀", no: 4, dia: 6, kind: .flat, rpm: 2200, feed: 400, flutes: 3),
        ToolRecord(name: "丝锥", no: 5, dia: 10, kind: .tap, rpm: 300, feed: 450, flutes: 3)
    ]
}
