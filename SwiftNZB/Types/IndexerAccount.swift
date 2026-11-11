//
//  IndexerAccount.swift
//  SwiftNZB
//

import Foundation

/// A configured Newznab-compatible indexer (a direct indexer, or an aggregator such as NZBHydra2
/// or Prowlarr, which speak the same API). The API key is stored in the Keychain, keyed by `id` —
/// it is intentionally NOT part of this struct.
struct IndexerAccount: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    /// Display label, e.g. "NZBGeek".
    var name: String
    /// Base URL of the indexer, e.g. "https://api.nzbgeek.info". The API path is appended to it.
    var url: String
    /// Whether this indexer is queried by a search.
    var isEnabled: Bool

    init(id: UUID = UUID(), name: String = "", url: String = "", isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.url = url
        self.isEnabled = isEnabled
    }

    // Migration-safe decoder: new fields default so older payloads still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }

    /// The URL without scheme or trailing slash, for compact display.
    var displayHost: String {
        var host = url
        for prefix in ["https://", "http://"] where host.hasPrefix(prefix) {
            host.removeFirst(prefix.count)
        }
        while host.hasSuffix("/") { host.removeLast() }
        return host
    }
}
