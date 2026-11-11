//
//  IndexerSearchService.swift
//  SwiftNZB
//
//  The app's seam to NewznabKit: searches every enabled indexer in parallel, and turns a result
//  into a local .nzb file for the import flow.
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
    }

    @MainActor
    static func credentials(for accounts: [IndexerAccount], store: IndexerStore) -> [Credentials] {
        accounts.compactMap { account in
            guard let key = store.apiKey(for: account.id), !key.isEmpty else { return nil }
            return Credentials(account: account, apiKey: key)
        }
    }

    static func search(query: String, category: IndexerCategory,
                       indexers: [Credentials]) async throws -> Outcome {
        guard !indexers.isEmpty else { throw SearchServiceError.noUsableIndexers }

        let perIndexer = await withTaskGroup(of: (IndexerAccount, Result<[NewznabItem], Error>).self) { group in
            for indexer in indexers {
                group.addTask {
                    do {
                        let client = try client(for: indexer)
                        let items = try await client.search(query: query, categoryID: category.newznabID)
                        return (indexer.account, .success(items))
                    } catch {
                        return (indexer.account, .failure(error))
                    }
                }
            }
            var collected: [(IndexerAccount, Result<[NewznabItem], Error>)] = []
            for await entry in group { collected.append(entry) }
            return collected
        }

        var results: [IndexerResult] = []
        var failures: [String] = []
        var firstError: Error?
        for (account, outcome) in perIndexer {
            switch outcome {
            case .success(let items):
                results += items.map { result(from: $0, indexer: account) }
            case .failure(let error):
                firstError = firstError ?? error
                failures.append("\(account.name): \(error.localizedDescription)")
            }
        }
        if results.isEmpty, failures.count == perIndexer.count, let firstError { throw firstError }
        return Outcome(results: results, failures: failures.sorted())
    }

    /// A cheap credentials check: one newest-releases result. Throws the indexer's own error.
    static func test(url: String, apiKey: String) async throws {
        let account = IndexerAccount(name: "", url: url)
        _ = try await client(for: Credentials(account: account, apiKey: apiKey))
            .search(query: nil, limit: 1)
    }

    /// Downloads the result's .nzb into a temporary file named after the release, ready for
    /// `ImportCoordinator.handle(url:)` (which copies it into the app's nzb folder).
    static func fetchNZB(for result: IndexerResult, indexer: Credentials) async throws -> URL {
        let (data, serverFilename) = try await client(for: indexer).fetchNZB(from: result.nzbURL)
        // The release title is the better job name; the server's filename is often an id.
        var base = result.title
        if base.isEmpty, let serverFilename { base = (serverFilename as NSString).deletingPathExtension }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("indexer-nzb", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(sanitized(base)).appendingPathExtension("nzb")
        try data.write(to: file, options: .atomic)
        return file
    }

    private static func client(for indexer: Credentials) throws -> NewznabClient {
        guard let base = NewznabRequest.baseURL(from: indexer.account.url) else {
            throw NewznabError.insecureOrInvalidURL
        }
        return NewznabClient(baseURL: base, apiKey: indexer.apiKey)
    }

    private static func result(from item: NewznabItem, indexer: IndexerAccount) -> IndexerResult {
        // The most specific category decides the top-level one; all share the same thousand.
        let category = item.categoryIDs.last.map(IndexerCategory.init(newznabID:)) ?? .other
        return IndexerResult(id: "\(indexer.id.uuidString)/\(item.guid)", title: item.title,
                             indexerID: indexer.id, indexerName: indexer.name, category: category,
                             sizeBytes: item.sizeBytes, publishedAt: item.publishedAt,
                             grabs: item.grabs, nzbURL: item.nzbURL)
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
