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
    /// The response was neither a Newznab result list nor a Newznab error.
    case unexpectedResponse
    /// A downloaded file is not an NZB (typically an HTML page or an empty body).
    case notAnNZB

    public var errorDescription: String? {
        switch self {
        case .insecureOrInvalidURL:
            return String(localized: "The indexer address must be a full https:// URL.")
        case let .api(code, description):
            switch code {
            case 100: return String(localized: "The indexer rejected the API key.")
            case 101: return String(localized: "The indexer account is suspended.")
            case 102: return String(localized: "The indexer account isn't allowed to use the API.")
            case 429: return String(localized: "The indexer's request limit is reached. Try again later.")
            default:
                return description.isEmpty
                    ? String(localized: "The indexer reported error \(code).")
                    : description
            }
        case let .http(status):
            return String(localized: "The indexer returned HTTP \(status).")
        case .unexpectedResponse:
            return String(localized: "The indexer sent a response SwiftNZB doesn't understand. Check the address.")
        case .notAnNZB:
            return String(localized: "The indexer didn't send an NZB file.")
        }
    }
}
