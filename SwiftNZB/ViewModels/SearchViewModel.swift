//
//  SearchViewModel.swift
//  SwiftNZB
//
//  Drives the Search tab: the query, the category, sorting and filtering by indexer, and handing
//  a chosen result's .nzb to the import flow.
//

import Foundation
import Observation

@MainActor
@Observable
final class SearchViewModel {
    enum State: Equatable {
        case idle
        case searching
        case results
        case failed(String)
    }

    /// Runs one search across the given indexers. Injected so previews can supply sample results.
    typealias Searcher = @MainActor (_ query: String, _ category: IndexerCategory,
                                     _ indexers: [IndexerAccount]) async throws -> IndexerSearchService.Outcome
    /// Turns a result into a local .nzb file. Injected for the same reason.
    typealias Fetcher = @MainActor (_ result: IndexerResult) async throws -> URL

    var query = ""
    var category: IndexerCategory = .all
    var sort: IndexerSort = .newest
    /// The source indexer to show (a result's `indexerName`, so the indexers behind a Prowlarr entry
    /// each count separately); nil shows every source.
    var indexerFilter: String?
    private(set) var state: State = .idle
    private(set) var results: [IndexerResult] = []
    /// One line per indexer that failed while others answered.
    private(set) var failures: [String] = []
    private(set) var recentSearches: [String] = []
    /// Results whose .nzb is being fetched right now.
    private(set) var downloadingIDs: Set<String> = []
    /// Set when fetching a result's .nzb fails; drives the alert.
    var downloadError: String?

    private let store: IndexerStore
    private let searcher: Searcher
    private let fetcher: Fetcher
    private var searchTask: Task<Void, Never>?

    /// `store` defaults to `.shared`, resolved here rather than as a default argument: default
    /// arguments are evaluated outside the main actor, where `shared` isn't reachable.
    init(store: IndexerStore? = nil, searcher: Searcher? = nil, fetcher: Fetcher? = nil) {
        let store = store ?? .shared
        self.store = store
        self.searcher = searcher ?? { query, category, indexers in
            let credentials = IndexerSearchService.credentials(for: indexers, store: store)
            return try await IndexerSearchService.search(query: query, category: category, indexers: credentials)
        }
        self.fetcher = fetcher ?? { result in
            guard let account = store.accounts.first(where: { $0.id == result.indexerID }),
                  let credentials = IndexerSearchService.credentials(for: [account], store: store).first else {
                throw SearchServiceError.indexerRemoved
            }
            return try await IndexerSearchService.fetchNZB(for: result, indexer: credentials)
        }
    }

    struct SourceCount: Identifiable, Hashable {
        let name: String
        let count: Int
        var id: String { name }
    }

    private var resultsInCategory: [IndexerResult] {
        results.filter { category == .all || $0.category == category }
    }

    /// How many results each source indexer returned for the current category, most first.
    var sourceCounts: [SourceCount] {
        Dictionary(grouping: resultsInCategory, by: \.indexerName)
            .map { SourceCount(name: $0.key, count: $0.value.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count
                                           : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var categoryResultCount: Int { resultsInCategory.count }

    var visibleResults: [IndexerResult] {
        sort.sorted(resultsInCategory.filter { indexerFilter == nil || $0.indexerName == indexerFilter })
    }

    /// Starts a search, replacing any that is still running.
    func submit() {
        searchTask?.cancel()
        searchTask = Task { await search() }
    }

    func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        rememberSearch(trimmed)
        state = .searching
        do {
            let outcome = try await searcher(trimmed, category, store.enabledAccounts)
            guard !Task.isCancelled else { return }
            results = outcome.results
            failures = outcome.failures
            // Keep the source filter only if that indexer returned something this time.
            if let filter = indexerFilter, !results.contains(where: { $0.indexerName == filter }) {
                indexerFilter = nil
            }
            state = .results
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            failures = []
            state = .failed(error.localizedDescription)
        }
    }

    func search(for recent: String) {
        query = recent
        submit()
    }

    /// The category chips re-run the search, so the indexer filters server-side and returns a
    /// full page of that category rather than a slice of the mixed results.
    func categoryChanged() {
        if state == .results || state == .searching { submit() }
    }

    /// Fetches the result's .nzb and hands it to the same import flow a shared file uses, which
    /// opens the Add Download sheet.
    func download(_ result: IndexerResult) {
        guard !downloadingIDs.contains(result.id) else { return }
        downloadingIDs.insert(result.id)
        Task {
            defer { downloadingIDs.remove(result.id) }
            do {
                let file = try await fetcher(result)
                ImportCoordinator.shared.handle(url: file)
                // The importer keeps its own copy in the app's nzb folder; drop the per-download folder.
                try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
            } catch {
                downloadError = error.localizedDescription
            }
        }
    }

    func clear() {
        searchTask?.cancel()
        results = []
        failures = []
        state = .idle
    }

    private func rememberSearch(_ query: String) {
        recentSearches.removeAll { $0.caseInsensitiveCompare(query) == .orderedSame }
        recentSearches.insert(query, at: 0)
        recentSearches = Array(recentSearches.prefix(8))
    }
}
