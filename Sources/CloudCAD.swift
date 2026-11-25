import Foundation

/// MacroGen Cloud CAD 客户端。
/// 说明：这是个人服务内置令牌；如果服务器轮换了 CAD_API_TOKEN，同步改这里。
enum CloudCADConfig {
    static let baseURL = URL(string: "https://60-205-185-33.sslip.io")!
    static let token = "Mml2g6SontracZvfUD83IDyLwXmiMPpOdlue75B-Zrs"
    static let pollIntervalNanos: UInt64 = 700_000_000
    static let maxPollCount = 60
}

struct CloudCADJobCreated: Decodable {
    let id: String
}

struct CloudCADJobStatus: Decodable {
    let id: String?
    let status: String
    let stage: String?
    let progress: Int?
    let message: String?
    let error: String?
    let artifacts: [String: String]?
    let drawing: CloudCADDrawing?
    let metrics: CloudCADMetrics?
}

struct CloudCADDrawing: Decodable {
    let partName: String?
    let stock: CloudCADStock?
    let features: [CloudCADFeature]?
    let language: String?
    let notes: [String]?

    enum CodingKeys: String, CodingKey {
        case partName = "part_name"
        case stock, features, language, notes
    }
}

struct CloudCADStock: Decodable {
    let length: Double?
    let width: Double?
    let height: Double?
    let shape: String?
    let innerDiameter: Double?

    enum CodingKeys: String, CodingKey {
        case length, width, height, shape
        case innerDiameter = "inner_diameter"
    }
}

struct CloudCADFeature: Decodable {
    let type: String?
    let length: Double?
    let width: Double?
    let depth: Double?
    let diameter: Double?
    let height: Double?
    let topDiameter: Double?
    let cornerRadius: Double?
    let centerX: Double?
    let centerY: Double?
    let angle: Double?
    let zTop: Double?
    let shape: String?
    let side: String?
    let counterboreDiameter: Double?
    let counterboreDepth: Double?
    let countersinkDiameter: Double?
    let countersinkAngle: Double?
    let pitch: Double?
    let internalThread: Bool?
    let radius: Double?
    let size: Double?
    let target: String?

    enum CodingKeys: String, CodingKey {
        case type, length, width, depth, diameter, height, angle, shape, side, pitch, radius, size, target
        case topDiameter = "top_diameter"
        case cornerRadius = "corner_radius"
        case centerX = "center_x"
        case centerY = "center_y"
        case zTop = "z_top"
        case counterboreDiameter = "counterbore_diameter"
        case counterboreDepth = "counterbore_depth"
        case countersinkDiameter = "countersink_diameter"
        case countersinkAngle = "countersink_angle"
        case internalThread = "internal"
    }
}

extension CloudCADDrawing {
    /// 把云端 drawing 转成 App 自己的参数化模型。
    /// STEP 用来显示真实 B-Rep；这份参数用于建模树和 CAM 的孔/腔/槽工序。
    func true3DParams(fallbackName: String = "云端文字模型") -> True3DParams {
        var params = True3DParams()
        params.projectName = (partName?.isEmpty == false) ? partName! : fallbackName
        let stock = self.stock
        params.width = max(stock?.length ?? 120, 1)
        params.depth = max(stock?.width ?? 80, 1)
        params.height = max(stock?.height ?? 10, 1)
        params.baseShape = (stock?.shape == "cylinder") ? .circle : .box
        params.edgeMode = .none
        params.features = (features ?? []).compactMap { $0.true3DFeature(stockHeight: params.height) }
        return params
    }
}

private extension CloudCADFeature {
    func true3DFeature(stockHeight: Double) -> True3DFeatureSpec? {
        let x = centerX ?? 0
        let y = centerY ?? 0
        let top = zTop ?? stockHeight

        switch type {
        case "rect_pocket":
            guard abs(angle ?? 0) < 0.001, let length, let width, let depth else { return nil }
            var f = True3DFeatureSpec(kind: .rectPocket, x: x, y: y)
            f.name = "方腔"
            f.width = length
            f.depthY = width
            f.depth = depth
            f.cornerRadius = cornerRadius ?? 0
            f.topZ = top
            return f

        case "circular_pocket":
            guard let diameter, let depth else { return nil }
            var f = True3DFeatureSpec(kind: .circularPocket, x: x, y: y)
            f.name = "圆腔"
            f.dia = diameter
            f.depth = depth
            f.topZ = top
            return f

        case "hole":
            guard let diameter else { return nil }
            var f = True3DFeatureSpec(kind: .hole, x: x, y: y)
            f.name = "孔"
            f.dia = diameter
            f.topZ = top
            if let counterboreDiameter {
                f.holeKind = .counterbore
                f.holeDepth = depth ?? stockHeight
                f.cbDia = counterboreDiameter
                f.cbDepth = counterboreDepth ?? 2
            } else if let countersinkDiameter {
                f.holeKind = .countersink
                f.holeDepth = depth ?? stockHeight
                f.csDia = countersinkDiameter
                f.csAngle = countersinkAngle ?? 90
            } else if let depth {
                f.holeKind = .blind
                f.holeDepth = depth
            } else {
                f.holeKind = .through
                f.holeDepth = stockHeight
            }
            return f

        case "boss":
            guard let diameter, let height else { return nil }
            if shape == "cone", let topDiameter {
                var f = True3DFeatureSpec(kind: .coneBoss, x: x, y: y)
                f.name = "锥形凸台"
                f.dia = diameter
                f.topDia = topDiameter
                f.bossHeight = height
                return f
            }
            guard shape != "sphere" else { return nil }
            var f = True3DFeatureSpec(kind: .boss, x: x, y: y)
            f.name = "凸台"
            f.dia = diameter
            f.bossHeight = height
            return f

        case "slot_pocket":
            guard let length, let width, let depth else { return nil }
            var f = True3DFeatureSpec(kind: .slot, x: x, y: y)
            f.name = "腰形槽"
            f.width = length
            f.depthY = width
            f.depth = depth
            f.topZ = top
            return f

        case "thread":
            guard internalThread != false, let diameter, let length else { return nil }
            var f = True3DFeatureSpec(kind: .hole, x: x, y: y)
            f.name = "螺纹底孔"
            f.dia = diameter
            f.holeKind = .thread
            f.holeDepth = length
            return f

        default:
            // step_cut / fillet / chamfer 暂未映射；STEP 仍然保留真实几何。
            return nil
        }
    }
}

struct CloudCADMetrics: Decodable {
    let faces: Int?
    let triangles: Int?
    let volume: Double?
}

enum CloudCADClientError: LocalizedError {
    case invalidResponse
    case http(Int, String)
    case failed(String)
    case missingSTEP
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "云端返回格式异常"
        case .http(let code, let detail):
            return "云端请求失败（HTTP \(code)）：\(detail)"
        case .failed(let message):
            return "云端生成失败：\(message)"
        case .missingSTEP:
            return "云端任务完成，但没有返回 STEP 文件"
        case .timeout:
            return "云端生成超时，请稍后再试"
        }
    }
}

enum CloudCADClient {
    static func createTextJob(prompt: String) async throws -> CloudCADJobCreated {
        var request = URLRequest(url: CloudCADConfig.baseURL.appendingPathComponent("api/jobs"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(CloudCADConfig.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "mode", value: "text"),
            URLQueryItem(name: "prompt", value: prompt)
        ]
        request.httpBody = body.percentEncodedQuery?.data(using: .utf8)
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response: response, data: data, accepted: [200, 201, 202])
        return try JSONDecoder().decode(CloudCADJobCreated.self, from: data)
    }

    static func waitForJob(id: String) async throws -> CloudCADJobStatus {
        for _ in 0..<CloudCADConfig.maxPollCount {
            let status = try await getJob(id: id)
            if status.status == "succeeded" {
                return status
            }
            if status.status == "failed" {
                throw CloudCADClientError.failed(status.error ?? status.message ?? "未知错误")
            }
            try await Task.sleep(nanoseconds: CloudCADConfig.pollIntervalNanos)
        }
        throw CloudCADClientError.timeout
    }

    static func getJob(id: String) async throws -> CloudCADJobStatus {
        var request = URLRequest(url: CloudCADConfig.baseURL.appendingPathComponent("api/jobs/\(id)"))
        request.setValue("Bearer \(CloudCADConfig.token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response: response, data: data, accepted: [200])
        return try JSONDecoder().decode(CloudCADJobStatus.self, from: data)
    }

    static func downloadSTEP(path: String) async throws -> URL {
        guard let url = URL(string: path, relativeTo: CloudCADConfig.baseURL) else {
            throw CloudCADClientError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(CloudCADConfig.token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        let (temporary, response) = try await URLSession.shared.download(for: request)
        try check(response: response, data: nil, accepted: [200])
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacroGen-Cloud-\(UUID().uuidString).step")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }

    private static func check(response: URLResponse, data: Data?, accepted: Set<Int>) throws {
        guard let http = response as? HTTPURLResponse else {
            throw CloudCADClientError.invalidResponse
        }
        guard accepted.contains(http.statusCode) else {
            let detail: String
            if let data, let text = String(data: data, encoding: .utf8), !text.isEmpty {
                detail = String(text.prefix(220))
            } else {
                detail = "无返回内容"
            }
            throw CloudCADClientError.http(http.statusCode, detail)
        }
    }
}
