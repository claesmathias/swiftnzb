//
//  NewznabRequest.swift
//  NewznabKit
//
//  Builds Newznab API URLs. The API lives at `{base}/api`; some users paste the full API URL,
//  so a base that already ends in `/api` is used as-is.
//

import Foundation

public enum NewznabRequest {
    /// Results requested per indexer. Most indexers cap a page at 100.
    public static let defaultLimit = 100

    /// Normalizes what a user typed into an indexer base URL: trims whitespace, adds `https://`
    /// when no scheme was given, and refuses anything that is not HTTPS with a host.
    public static func baseURL(from input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text),
              url.scheme?.lowercased() == "https",
              let host = url.host(), !host.isEmpty else { return nil }
        return url
    }

    /// `t=search`. A nil or empty `query` asks for the newest releases, which indexers allow and
    /// which makes a cheap credentials check.
    public static func search(base: URL, apiKey: String, query: String?,
                              categoryID: Int? = nil, limit: Int = defaultLimit) throws -> URL {
        var items = [
            URLQueryItem(name: "t", value: "search"),
            URLQueryItem(name: "apikey", value: apiKey),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "extended", value: "1"),
        ]
        if let query, !query.isEmpty { items.append(URLQueryItem(name: "q", value: query)) }
        if let categoryID { items.append(URLQueryItem(name: "cat", value: String(categoryID))) }
        return try apiURL(base: base, queryItems: items)
    }

    static func apiURL(base: URL, queryItems: [URLQueryItem]) throws -> URL {
        guard base.scheme?.lowercased() == "https",
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw NewznabError.insecureOrInvalidURL
        }
        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        if !path.lowercased().hasSuffix("/api") { path += "/api" }
        components.path = path
        components.queryItems = queryItems
        // URLQueryItem leaves "+" alone, which servers decode as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else { throw NewznabError.insecureOrInvalidURL }
        return url
    }
}
