//
//  IndexerSearchService.swift
//  SwiftNZB
//
//  The app's seam to NewznabKit: searches every enabled indexer in parallel (Newznab endpoints and
//  Prowlarr's aggregated API alike), and turns a result into a local .nzb file for the import flow.
//

import Foundation
import NewznabKit

enum IndexerSearchService {
    /// Results from the indexers that answered, plus one message per indexer that failed. Throws
    /// only when every indexer failed, so one slow or broken indexer never hides the others.
    struct Outcome: Sendable {
        var results: [IndexerResult]
        var failures: [String]
    }

    struct Credentials: Sendable {
        var account: IndexerAccount
        var apiKey: String
        var headers: [IndexerHeader] = []
    }

    @MainActor
    static func credentials(for accounts: [IndexerAccount], store: IndexerStore) -> [Credentials] {
        accounts.compactMap { account in
            guard let key = store.apiKey(for: account.id), !key.isEmpty else { return nil }
            return Credentials(account: account, apiKey: key, headers: store.headers(for: account.id))
        }
    }

    static func search(query: String, category: IndexerCategory,
                       indexers: [Credentials]) async throws -> Outcome {
        guard !indexers.isEmpty else { throw SearchServiceError.noUsableIndexers }

        let perIndexer = await withTaskGroup(of: (IndexerAccount, Result<[IndexerResult], Error>).self) { group in
            for indexer in indexers {
                group.addTask {
                    do {
                        return (indexer.account, .success(try await results(for: indexer, query: query, category: category)))
                    } catch {
                        return (indexer.account, .failure(error))
                    }
                }
            }
            var collected: [(IndexerAccount, Result<[IndexerResult], Error>)] = []
            for await entry in group { collected.append(entry) }
            return collected
        }

        var results: [IndexerResult] = []
        var failures: [String] = []
        var firstError: Error?
        for (account, outcome) in perIndexer {
            switch outcome {
            case .success(let found):
                results += found
            case .failure(let error):
                firstError = firstError ?? error
                failures.append("\(account.name): \(error.localizedDescription)")
            }
        }
        if results.isEmpty, failures.count == perIndexer.count, let firstError { throw firstError }
        // Some indexers repeat a GUID within one response; duplicate ids break SwiftUI list identity.
        var seen = Set<String>()
        results = results.filter { seen.insert($0.id).inserted }
        return Outcome(results: results, failures: failures.sorted())
    }

    private static func results(for indexer: Credentials, query: String,
                                category: IndexerCategory) async throws -> [IndexerResult] {
        switch indexer.account.kind {
        case .newznab:
            return try await newznabClient(for: indexer)
                .search(query: query, categoryID: category.newznabID)
                .map { result(from: $0, indexer: indexer.account) }
        case .prowlarr:
            return try await prowlarrClient(for: indexer)
                .search(query: query, categoryID: category.newznabID)
                .compactMap { result(from: $0, indexer: indexer.account) }
        }
    }

    /// A cheap credentials check. Throws the indexer's own error; on success returns a line to show.
    static func test(kind: IndexerKind, url: String, apiKey: String,
                     headers: [IndexerHeader] = []) async throws -> String {
        let credentials = Credentials(account: IndexerAccount(name: "", url: url, kind: kind),
                                      apiKey: apiKey, headers: headers)
        switch kind {
        case .newznab:
            _ = try await newznabClient(for: credentials).search(query: nil, limit: 1)
            return String(localized: "The indexer accepted the API key.")
        case .prowlarr:
            let usenet = try await prowlarrClient(for: credentials).indexers()
                .filter { $0.enable != false && $0.protocol?.lowercased() == "usenet" }
            let names = usenet.compactMap(\.name).sorted().formatted(.list(type: .and))
            return usenet.isEmpty
                ? String(localized: "Connected to Prowlarr, but it has no enabled Usenet indexers.")
                : String(localized: "Connected to Prowlarr. Usenet indexers: \(names).")
        }
    }

    /// Downloads the result's .nzb into a temporary file named after the release, ready for
    /// `ImportCoordinator.handle(url:)` (which copies it into the app's nzb folder).
    static func fetchNZB(for result: IndexerResult, indexer: Credentials) async throws -> URL {
        let (data, serverFilename): (Data, String?)
        switch indexer.account.kind {
        case .newznab: (data, serverFilename) = try await newznabClient(for: indexer).fetchNZB(from: result.nzbURL)
        case .prowlarr: (data, serverFilename) = try await prowlarrClient(for: indexer).fetchNZB(from: result.nzbURL)
        }
        // The release title is the better job name; the server's filename is often an id.
        var base = result.title
        if base.isEmpty, let serverFilename { base = (serverFilename as NSString).deletingPathExtension }
        // One folder per download, so two releases with the same title can't overwrite each other's
        // file mid-import. The file keeps the release name, which the importer falls back to.
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("indexer-nzb", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(sanitized(base)).appendingPathExtension("nzb")
        try data.write(to: file, options: .atomic)
        return file
    }

    private static func base(for indexer: Credentials) throws -> URL {
        guard let base = NewznabRequest.baseURL(from: indexer.account.url) else {
            throw NewznabError.insecureOrInvalidURL
        }
        return base
    }

    /// Later entries win on a duplicate name, matching what the form shows last.
    private static func headerFields(for indexer: Credentials) -> [String: String] {
        Dictionary(indexer.headers.map { ($0.name, $0.value) }, uniquingKeysWith: { $1 })
    }

    private static func newznabClient(for indexer: Credentials) throws -> NewznabClient {
        NewznabClient(baseURL: try base(for: indexer), apiKey: indexer.apiKey, headers: headerFields(for: indexer))
    }

    private static func prowlarrClient(for indexer: Credentials) throws -> ProwlarrClient {
        ProwlarrClient(baseURL: try base(for: indexer), apiKey: indexer.apiKey, headers: headerFields(for: indexer))
    }

    private static func result(from item: NewznabItem, indexer: IndexerAccount) -> IndexerResult {
        // The most specific category decides the top-level one; all share the same thousand.
        let category = item.categoryIDs.last.map(IndexerCategory.init(newznabID:)) ?? .other
        return IndexerResult(id: "\(indexer.id.uuidString)/\(item.guid)", title: item.title,
                             indexerID: indexer.id, indexerName: indexer.name, category: category,
                             sizeBytes: item.sizeBytes, publishedAt: item.publishedAt,
                             grabs: item.grabs, nzbURL: item.nzbURL)
    }

    /// A Prowlarr release, attributed to the Prowlarr indexer it came from (e.g. "NZBgeek").
    private static func result(from release: ProwlarrRelease, indexer: IndexerAccount) -> IndexerResult? {
        guard let title = release.title, let link = release.downloadUrl, let url = URL(string: link) else { return nil }
        let category = release.newznabCategoryIDs.last.map(IndexerCategory.init(newznabID:)) ?? .other
        let guid = release.guid ?? link
        return IndexerResult(id: "\(indexer.id.uuidString)/\(release.indexerId ?? 0)/\(guid)", title: title,
                             indexerID: indexer.id, indexerName: release.indexer ?? indexer.name,
                             category: category, sizeBytes: release.size.map { Int($0) },
                             publishedAt: release.publishDate, grabs: release.grabs, nzbURL: url)
    }

    private static func sanitized(_ name: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = name.components(separatedBy: illegal).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "download" : String(cleaned.prefix(180))
    }
}

enum SearchServiceError: LocalizedError {
    case noUsableIndexers
    case indexerRemoved

    var errorDescription: String? {
        switch self {
        case .noUsableIndexers:
            return String(localized: "No enabled indexer has an API key. Check Settings → Indexers.")
        case .indexerRemoved:
            return String(localized: "The indexer for this result is no longer set up.")
        }
    }
}
