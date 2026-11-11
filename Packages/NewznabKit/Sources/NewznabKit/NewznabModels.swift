//
//  NewznabModels.swift
//  NewznabKit
//

import Foundation

/// One `<item>` from a Newznab search response.
public struct NewznabItem: Hashable, Sendable {
    /// The indexer's GUID for the release (text of `<guid>`), unique per indexer.
    public var guid: String
    public var title: String
    /// Where the .nzb is fetched: the `<enclosure url>`, else `<link>`. Indexers embed the API key
    /// in it, so it can be fetched as-is.
    public var nzbURL: URL
    public var publishedAt: Date?
    public var sizeBytes: Int?
    /// Every Newznab category number on the item, most general first as the indexer lists them
    /// (e.g. `[2000, 2040]`).
    public var categoryIDs: [Int]
    public var grabs: Int?

    public init(guid: String, title: String, nzbURL: URL, publishedAt: Date?, sizeBytes: Int?,
                categoryIDs: [Int], grabs: Int?) {
        self.guid = guid
        self.title = title
        self.nzbURL = nzbURL
        self.publishedAt = publishedAt
        self.sizeBytes = sizeBytes
        self.categoryIDs = categoryIDs
        self.grabs = grabs
    }
}

public enum NewznabError: LocalizedError, Equatable, Sendable {
    /// The indexer address is not a valid `https://` URL. Plain HTTP is refused: the API key
    /// travels in the query string.
    case insecureOrInvalidURL
    /// The indexer answered with a Newznab `<error code=… description=…/>`.
    case api(code: Int, description: String)
    case http(status: Int)
    /// HTTP 401/403 with no Newznab error body: the API key (or a proxy in front) was refused.
    case unauthorized(status: Int)
    /// Cloudflare Access sent the request to its login page: no valid service-token headers.
    case cloudflareAccess
    /// The server redirected to another host or to plain HTTP, which is not followed so the API
    /// key and custom headers never leave the configured host.
    case redirected(host: String)
    /// The address served an HTML page (typically the indexer's website or login page) instead of
    /// its API — e.g. `nzbgeek.info` rather than `api.nzbgeek.info`.
    case webPage
    /// The address is Prowlarr's (or another *arr app's) root API — it answers `/api` with
    /// `{"current":"v1",…}` — so the entry should use the Prowlarr type, not Newznab.
    case prowlarrRoot
    /// The response was neither a Newznab result list nor a Newznab error. `excerpt` is the start
    /// of the body, to show what came back instead.
    case unexpectedResponse(excerpt: String)
    /// A downloaded file is not an NZB (typically an HTML page or an empty body).
    case notAnNZB

    public var errorDescription: String? {
        switch self {
        case .insecureOrInvalidURL:
            return String(localized: "The indexer address must be a full https:// URL.")
        case let .api(code, description):
            // Indexers disagree on codes (NZBGeek sends 101, "suspended" in the spec, for a wrong
            // key), so their own description wins; the code only covers a bare error.
            let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return String(localized: "The indexer said: \(trimmed)") }
            switch code {
            case 100: return String(localized: "The indexer rejected the API key.")
            case 101: return String(localized: "The indexer account is suspended.")
            case 102: return String(localized: "The indexer account isn't allowed to use the API.")
            case 429: return String(localized: "The indexer's request limit is reached. Try again later.")
            default: return String(localized: "The indexer reported error \(code).")
            }
        case let .http(status):
            return String(localized: "The indexer returned HTTP \(status).")
        case let .unauthorized(status):
            return String(localized: "The indexer refused the request (HTTP \(status)). Check the API key. For Prowlarr, use Prowlarr's own API key from Settings → General.")
        case .cloudflareAccess:
            return String(localized: "Cloudflare Access blocked the request. Add the CF-Access-Client-Id and CF-Access-Client-Secret headers of a service token that this application's Access policy allows.")
        case let .redirected(host):
            return String(localized: "The indexer redirected to \(host). SwiftNZB doesn't follow redirects to another address or to plain HTTP, so your API key stays with the indexer. Use the final address instead.")
        case .webPage:
            return String(localized: "That address returned a web page, not a Newznab API. For NZBGeek use https://api.nzbgeek.info. For Prowlarr use an indexer's Newznab address, like https://prowlarr.example.com/1/.")
        case .prowlarrRoot:
            return String(localized: "This address is Prowlarr, not a Newznab feed. Set the type to Prowlarr to search all its indexers.")
        case let .unexpectedResponse(excerpt):
            return excerpt.isEmpty
                ? String(localized: "The indexer sent an empty response. Check the address.")
                : String(localized: "The indexer sent a response SwiftNZB doesn't understand. It began with: \(excerpt)")
        case .notAnNZB:
            return String(localized: "The indexer didn't send an NZB file.")
        }
    }
}
