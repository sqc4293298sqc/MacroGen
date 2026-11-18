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
                  let spec = decodeSpec(data) else { continue }
            return spec
        }
        return nil
    }

    /// 旧工程兼容：新版本给 PartSpec 加了非可选字段，直接 decode 会整份失败。
    /// 先尝试正常解码；失败时把当前默认工程 JSON 递归补齐到旧 JSON 缺失的键，再解码。
    private static func decodeSpec(_ data: Data) -> PartSpec? {
        if let spec = try? JSONDecoder().decode(PartSpec.self, from: data) {
            return spec
        }
        guard let rawObject = try? JSONSerialization.jsonObject(with: data),
              let raw = rawObject as? [String: Any],
              let defaultsData = try? JSONEncoder().encode(PartSpec()),
              let defaultsObject = try? JSONSerialization.jsonObject(with: defaultsData),
              let defaults = defaultsObject as? [String: Any] else {
            return nil
        }
        let merged = mergeDefaults(defaults, raw)
        guard let mergedData = try? JSONSerialization.data(withJSONObject: merged) else {
            return nil
        }
        return try? JSONDecoder().decode(PartSpec.self, from: mergedData)
    }

    /// 用当前默认值补齐旧 JSON 的顶层/嵌套字典缺失键；已有值一律保留。
    private static func mergeDefaults(_ defaults: [String: Any], _ old: [String: Any]) -> [String: Any] {
        var out = defaults
        for (key, value) in old {
            if let base = out[key] as? [String: Any], let nested = value as? [String: Any] {
                out[key] = mergeDefaults(base, nested)
            } else {
                out[key] = value
            }
        }
        return out
    }

    static func clear() {
        try? FileManager.default.removeItem(at: file)
        try? FileManager.default.removeItem(at: backup)
    }
}
