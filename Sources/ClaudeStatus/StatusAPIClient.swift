import Foundation

enum StatusAPIError: Error, CustomStringConvertible {
    case badURL(String)
    case badStatus(url: String, code: Int)

    var description: String {
        switch self {
        case .badURL(let path):
            return "could not build URL for \(path)"
        case .badStatus(let url, let code):
            return "HTTP \(code) from \(url)"
        }
    }
}

struct StatusAPIClient: Sendable {
    let baseURL: URL
    private let session: URLSession

    init() {
        let env = ProcessInfo.processInfo.environment["CLAUDE_STATUS_BASE_URL"]
        baseURL = URL(string: env ?? "https://status.claude.com")!
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = ["User-Agent": "ClaudeStatus/1.0"]
        session = URLSession(configuration: config)
    }

    func fetchSummary() async throws -> Summary {
        let data = try await get("/api/v2/summary.json")
        return try JSONDecoder().decode(Summary.self, from: data)
    }

    func fetchHomepageHTML() async throws -> String {
        let data = try await get("/")
        return String(decoding: data, as: UTF8.self)
    }

    func fetchUptime() async throws -> [String: ComponentUptime] {
        try HomepageUptimeParser.assemble(html: await fetchHomepageHTML())
    }

    private func get(_ path: String) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw StatusAPIError.badURL(path)
        }
        let (data, response) = try await session.data(from: url)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard code == 200 else {
            throw StatusAPIError.badStatus(url: url.absoluteString, code: code)
        }
        return data
    }
}
