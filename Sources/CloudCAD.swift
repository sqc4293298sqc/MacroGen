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
    let stock: CloudCADStock?
    let features: [CloudCADFeature]?
    let language: String?
    let notes: [String]?
}

struct CloudCADStock: Decodable {
    let length: Double?
    let width: Double?
    let height: Double?
    let shape: String?
}

struct CloudCADFeature: Decodable {
    let type: String?
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
