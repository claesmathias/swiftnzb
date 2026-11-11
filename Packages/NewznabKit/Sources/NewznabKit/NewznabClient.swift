//
//  NewznabClient.swift
//  NewznabKit
//
//  Talks to one Newznab indexer over HTTPS: searches, and fetches the .nzb behind a result.
//

import Foundation

public struct NewznabClient: Sendable {
    public var baseURL: URL
    public var apiKey: String
    private let session: URLSession

    public init(baseURL: URL, apiKey: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
    }

    public func search(query: String?, categoryID: Int? = nil,
                       limit: Int = NewznabRequest.defaultLimit) async throws -> [NewznabItem] {
        let url = try NewznabRequest.search(base: baseURL, apiKey: apiKey, query: query,
                                            categoryID: categoryID, limit: limit)
        let data = try await get(url)
        return try NewznabParser.parseSearch(data)
    }

    /// Fetches the .nzb behind a result's download link (`t=get`, which carries the API key).
    /// Returns the file's bytes and, when the server names it, its filename.
    public func fetchNZB(from url: URL) async throws -> (data: Data, filename: String?) {
        guard url.scheme?.lowercased() == "https" else { throw NewznabError.insecureOrInvalidURL }
        let (data, response) = try await session.data(for: request(url))
        let http = response as? HTTPURLResponse
        if let error = NewznabParser.apiError(in: data) { throw error }
        if let status = http?.statusCode, !(200..<300).contains(status) { throw NewznabError.http(status: status) }
        guard NZBValidation.looksLikeNZB(data) else { throw NewznabError.notAnNZB }
        return (data, http.flatMap { NZBValidation.filename(fromContentDisposition: $0.value(forHTTPHeaderField: "Content-Disposition")) })
    }

    private func get(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(for: request(url))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            // Indexers often put a Newznab error body on a non-2xx status; prefer its message.
            throw NewznabParser.apiError(in: data) ?? NewznabError.http(status: http.statusCode)
        }
        return data
    }

    private func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("SwiftNZB", forHTTPHeaderField: "User-Agent")
        return request
    }
}

public enum NZBValidation {
    /// True when `data` is an NZB document: an `<nzb` root element near the start. Indexers send an
    /// HTML page or a Newznab `<error>` instead when, for example, the daily grab limit is used up.
    public static func looksLikeNZB(_ data: Data) -> Bool {
        let head = String(decoding: data.prefix(4096), as: UTF8.self).lowercased()
        return head.contains("<nzb")
    }

    /// The filename from a `Content-Disposition` header, e.g.
    /// `attachment; filename="Some.Release.nzb"`.
    public static func filename(fromContentDisposition header: String?) -> String? {
        guard let header else { return nil }
        for part in header.split(separator: ";") {
            let pair = part.trimmingCharacters(in: .whitespaces)
            guard pair.lowercased().hasPrefix("filename=") else { continue }
            let value = pair.dropFirst("filename=".count)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
            return value.isEmpty ? nil : value
        }
        return nil
    }
}
