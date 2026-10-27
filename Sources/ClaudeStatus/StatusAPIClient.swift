import Foundation

enum StatusAPIError: Error, CustomStringConvertible {
    case badURL(String)
    case badStatus(url: String, code: Int)
    case responseTooLarge(url: String, limit: Int)

    var description: String {
        switch self {
        case .badURL(let path):
            return "could not build URL for \(path)"
        case .badStatus(let url, let code):
            return "HTTP \(code) from \(url)"
        case .responseTooLarge(let url, let limit):
            return "response from \(url) exceeded \(limit) bytes"
        }
    }
}

struct StatusAPIClient: Sendable {
    let baseURL: URL
    private let session: URLSession

    init() {
        baseURL = Self.resolveBaseURL(ProcessInfo.processInfo.environment["CLAUDE_STATUS_BASE_URL"])
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

    // Ids come from parseLazyComponentIDs ([a-z0-9]+), so they are URL-safe.
    func fetchUptimeShowcase(componentIDs: [String]) async throws -> Data {
        try await get("/uptime_showcase?components=" + componentIDs.joined(separator: ","))
    }

    func fetchUptime() async throws -> [String: ComponentUptime] {
        let html = try await fetchHomepageHTML()
        let lazyIDs = HomepageUptimeParser.parseLazyComponentIDs(html)
        guard !lazyIDs.isEmpty else { return try HomepageUptimeParser.assemble(html: html) }
        return try HomepageUptimeParser.assemble(showcase: await fetchUptimeShowcase(componentIDs: lazyIDs))
    }

    // Testing hook: CLAUDE_STATUS_BASE_URL=http://... points both fetches at
    // a mock server. Anything unusable (empty, unparseable, non-http scheme)
    // falls back to the real site instead of crashing the app at launch.
    static func resolveBaseURL(_ override: String?) -> URL {
        let fallback = URL(string: "https://status.claude.com")!
        guard let override,
              let url = URL(string: override),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return fallback }
        return url
    }

    // Hard cap on buffered response size. The real homepage is well under
    // 1 MB; without a cap, a compromised or spoofed server could stream an
    // arbitrarily large body into memory.
    static let maxResponseBytes = 8 * 1024 * 1024

    static func collect<Bytes: AsyncSequence>(
        _ bytes: Bytes, limit: Int, url: String
    ) async throws -> Data where Bytes.Element == UInt8 {
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else {
                throw StatusAPIError.responseTooLarge(url: url, limit: limit)
            }
            data.append(byte)
        }
        return data
    }

    private func get(_ path: String) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw StatusAPIError.badURL(path)
        }
        let (bytes, response) = try await session.bytes(from: url)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard code == 200 else {
            throw StatusAPIError.badStatus(url: url.absoluteString, code: code)
        }
        return try await Self.collect(bytes, limit: Self.maxResponseBytes, url: url.absoluteString)
    }
}
