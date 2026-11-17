import Foundation
import UIKit

/// 工程持久化：只存 PartSpec 的 JSON，退出 App 后下次自动恢复。
enum ProjectStore {
    private static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MacroGen", isDirectory: true)
    }

    private static var file: URL { folder.appendingPathComponent("project.json") }
    private static var backup: URL { folder.appendingPathComponent("project.bak.json") }

    static func save(_ spec: PartSpec) {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(spec)
            if FileManager.default.fileExists(atPath: file.path) {
                try? FileManager.default.removeItem(at: backup)
                try? FileManager.default.copyItem(at: file, to: backup)
            }
            try data.write(to: file, options: .atomic)
        } catch {
            print("保存工程失败: \(error)")
        }
    }

    static func load() -> PartSpec? {
        for url in [file, backup] {
            guard let data = try? Data(contentsOf: url),
                  let spec = try? JSONDecoder().decode(PartSpec.self, from: data) else { continue }
            return spec
        }
        return nil
    }

    static func clear() {
        try? FileManager.default.removeItem(at: file)
        try? FileManager.default.removeItem(at: backup)
    }
}
