import Foundation

/// 真 3D 工程持久化：只存参数和特征，不存 OCCT Shape。
enum True3DProjectStore {
    static var fileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("MacroGen-3D-project.json")
    }

    static func save(_ params: True3DParams) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(params)
        try data.write(to: fileURL, options: .atomic)
    }

    static func load() throws -> True3DParams {
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(True3DParams.self, from: data)
    }
}
