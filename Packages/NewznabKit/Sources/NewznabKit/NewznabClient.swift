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
    /// Extra HTTP headers sent with every request, e.g. a required User-Agent or a proxy's
    /// Authorization header. They override the client's defaults of the same name.
    public var headers: [String: String]
    private let session: URLSession

    /// No cookies, no cache. Proxies such as Cloudflare Access hand out a session cookie on the
    /// first authorized request; keeping it would let later requests through without the configured
    /// headers, so a removed or rotated token would appear to keep working until the cookie expired.
    public static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    public init(baseURL: URL, apiKey: String, headers: [String: String] = [:],
                session: URLSession = NewznabClient.defaultSession) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.headers = headers
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
        guard let url = Self.secured(url, base: baseURL) else { throw NewznabError.insecureOrInvalidURL }
        // Prowlarr's download link redirects to the source indexer when the indexer has Prowlarr's
        // "Redirect" option on; that hop is followed, without this indexer's credentials.
        let (data, response) = try await send(url, followForeignRedirects: true)
        let http = response as? HTTPURLResponse
        if let error = NewznabParser.apiError(in: data) { throw error }
        if let http { try Self.checkStatus(http, body: data) }
        guard NZBValidation.looksLikeNZB(data) else { throw NewznabError.notAnNZB }
        return (data, http.flatMap { NZBValidation.filename(fromContentDisposition: $0.value(forHTTPHeaderField: "Content-Disposition")) })
    }

    private func get(_ url: URL) async throws -> Data {
        let (data, response) = try await send(url)
        if let http = response as? HTTPURLResponse {
            // Indexers often put a Newznab error body on a non-2xx status; prefer its message.
            if !(200..<300).contains(http.statusCode), let error = NewznabParser.apiError(in: data) { throw error }
            try Self.checkStatus(http, body: data)
        }
        return data
    }

    /// The URL to fetch a download link from: as-is over HTTPS; upgraded to HTTPS when it is plain
    /// HTTP on the indexer's own host (Prowlarr behind a TLS proxy builds `http://` links because
    /// it can't see the proxy's TLS); refused when it is plain HTTP anywhere else.
    public static func secured(_ url: URL, base: URL) -> URL? {
        switch url.scheme?.lowercased() {
        case "https":
            return url
        case "http" where url.host()?.lowercased() == base.host()?.lowercased():
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.scheme = "https"
            // An explicit :80 belonged to the plain-HTTP origin.
            if components?.port == 80 { components?.port = nil }
            return components?.url
        default:
            return nil
        }
    }

    /// Sends a request. Redirects are followed within the same host over HTTPS; with
    /// `followForeignRedirects`, also to another HTTPS host, but as a bare request without the
    /// custom headers (see `SameHostRedirects`).
    private func send(_ url: URL, followForeignRedirects: Bool = false) async throws -> (Data, URLResponse) {
        try await session.data(for: request(url),
                               delegate: SameHostRedirects(followForeignRedirects: followForeignRedirects))
    }

    /// Maps a non-2xx response to the most useful error. Redirects arrive here unfollowed when
    /// `SameHostRedirects` refused them.
    static func checkStatus(_ http: HTTPURLResponse, body: Data) throws {
        let status = http.statusCode
        if (200..<300).contains(status) { return }
        if (300..<400).contains(status) {
            let target = http.value(forHTTPHeaderField: "Location").flatMap { URL(string: $0, relativeTo: http.url) }
            throw redirectError(to: target)
        }
        if status == 401 || status == 403 { throw NewznabError.unauthorized(status: status) }
        throw NewznabError.http(status: status)
    }

    static func redirectError(to target: URL?) -> NewznabError {
        let host = target?.host() ?? ""
        if host.hasSuffix("cloudflareaccess.com") || target?.path().contains("/cdn-cgi/access/") == true {
            return .cloudflareAccess
        }
        return .redirected(host: host.isEmpty ? "another address" : host)
    }

    func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("SwiftNZB", forHTTPHeaderField: "User-Agent")
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return request
    }
}

/// Decides redirects. URLSession would otherwise carry the custom headers (proxy credentials such
/// as a Cloudflare Access secret, the Prowlarr X-Api-Key) to wherever the server points.
///
/// - Same host over HTTPS: followed with the request as is.
/// - Another host over HTTPS, only when `followForeignRedirects` (the .nzb download): followed as
///   a fresh request carrying nothing but the target URL and a User-Agent. That is how Prowlarr
///   hands off to the source indexer, whose own key Prowlarr put in the URL.
/// - Plain HTTP, or a Cloudflare Access login page: never followed; the 3xx is returned and
///   mapped to an error by `checkStatus`.
final class SameHostRedirects: NSObject, URLSessionTaskDelegate {
    enum Decision: Equatable { case follow, followWithoutCredentials, refuse }

    let followForeignRedirects: Bool

    init(followForeignRedirects: Bool = false) {
        self.followForeignRedirects = followForeignRedirects
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        guard let from = task.originalRequest?.url, let to = request.url else { return nil }
        switch Self.decision(from: from, to: to, followForeignRedirects: followForeignRedirects) {
        case .follow:
            return request
        case .followWithoutCredentials:
            var bare = URLRequest(url: to, timeoutInterval: request.timeoutInterval)
            bare.setValue("SwiftNZB", forHTTPHeaderField: "User-Agent")
            return bare
        case .refuse:
            return nil
        }
    }

    static func decision(from: URL, to: URL, followForeignRedirects: Bool) -> Decision {
        guard to.scheme?.lowercased() == "https", let toHost = to.host()?.lowercased() else { return .refuse }
        if from.host()?.lowercased() == toHost { return .follow }
        if toHost.hasSuffix("cloudflareaccess.com") || to.path().contains("/cdn-cgi/access/") { return .refuse }
        return followForeignRedirects ? .followWithoutCredentials : .refuse
    }

    static func allows(from: URL, to: URL) -> Bool {
        decision(from: from, to: to, followForeignRedirects: false) == .follow
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
