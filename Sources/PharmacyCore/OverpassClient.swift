import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct OverpassClient: Sendable {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private enum Failure: Error {
        case httpStatus(Int)
        case invalidResponse
    }

    private static let endpoints = [
        URL(string: "https://overpass-api.de/api/interpreter")!,
        URL(string: "https://overpass.private.coffee/api/interpreter")!
    ]

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 22
        return URLSession(configuration: configuration)
    }()

    public static let shared = OverpassClient { request in
        try await session.data(for: request)
    }

    private let transport: Transport

    init(transport: @escaping Transport) {
        self.transport = transport
    }

    /// One bounded fallback for transient failures; never retries 403 or 429.
    public func fetch(query: String) async throws -> Data {
        do {
            return try await request(query: query, endpoint: Self.endpoints[0])
        } catch {
            try Task.checkCancellation()
            guard Self.canUseFallback(after: error) else { throw error }
            return try await request(query: query, endpoint: Self.endpoints[1])
        }
    }

    private func request(query: String, endpoint: URL) async throws -> Data {
        try Task.checkCancellation()
        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) else {
            throw Failure.invalidResponse
        }
        request.httpBody = Data(("data=" + encoded).utf8)

        let (data, response) = try await transport(request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw Failure.invalidResponse }
        guard http.statusCode == 200 else { throw Failure.httpStatus(http.statusCode) }
        try PharmacySearch.validatePayload(data)
        return data
    }

    private static func canUseFallback(after error: Error) -> Bool {
        if error is CancellationError { return false }
        if let failure = error as? Failure {
            switch failure {
            case .httpStatus(let status): return [500, 502, 503, 504].contains(status)
            case .invalidResponse: return true
            }
        }
        if let networkError = error as? URLError {
            return [.timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
                    .dnsLookupFailed, .notConnectedToInternet].contains(networkError.code)
        }
        return error is DecodingError || (error as? SearchError) == .invalidResponse
    }
}
