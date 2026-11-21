import Foundation

/// 3D 工程的可持久化快照。OCCT `Shape`/`Mesh` 不写入 JSON，
/// STEP 源只保存复制到 Documents 里的文件名，载入时重新解析。
struct True3DStoredProject: Codable {
    enum SourceKind: String, Codable, Equatable {
        case parametric
        case importedStep
    }

    var id: UUID
    var name: String
    var sourceKind: SourceKind
    var params: True3DParams?
    var importedName: String?
    var importedFileName: String?
    var importedUnitInMeters: Double?
    var importedAt: Date?
    var operations: [True3DHistoryOperation] = []
    var selectedNodeID: UUID?

    init(
        id: UUID,
        name: String,
        sourceKind: SourceKind,
        params: True3DParams? = nil,
        importedName: String? = nil,
        importedFileName: String? = nil,
        importedUnitInMeters: Double? = nil,
        importedAt: Date? = nil,
        operations: [True3DHistoryOperation] = [],
        selectedNodeID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.sourceKind = sourceKind
        self.params = params
        self.importedName = importedName
        self.importedFileName = importedFileName
        self.importedUnitInMeters = importedUnitInMeters
        self.importedAt = importedAt
        self.operations = operations
        self.selectedNodeID = selectedNodeID
    }
}

/// 真 3D 工程持久化：只存参数、操作历史和 STEP 文件名，不存 OCCT Shape。
enum True3DProjectStore {
    static var fileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("MacroGen-3D-project.json")
    }

    static var modelsDirectory: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("MacroGen-3D-models", isDirectory: true)
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

    static func saveDocument(_ project: True3DStoredProject) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(project)
        try data.write(to: fileURL, options: .atomic)
    }

    static func loadDocument() throws -> True3DStoredProject {
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(True3DStoredProject.self, from: data)
    }

    /// 把用户选中的 STEP 复制进 App 容器，避免安全作用域 URL 失效。
    static func copyModelFile(from sourceURL: URL) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: modelsDirectory,
            withIntermediateDirectories: true
        )
        let ext = sourceURL.pathExtension.isEmpty ? "step" : sourceURL.pathExtension.lowercased()
        let destination = modelsDirectory.appendingPathComponent("\(UUID().uuidString).\(ext)")
        try fileManager.copyItem(at: sourceURL, to: destination)
        return destination
    }

    static func modelURL(fileName: String) -> URL {
        let safeName = (fileName as NSString).lastPathComponent
        return modelsDirectory.appendingPathComponent(safeName)
    }
}
