//
//  SearchView.swift
//  SwiftNZB
//
//  The Search tab: queries every enabled indexer at once and lists the results. Tapping download
//  hands the result's .nzb to the same import flow a shared file goes through.
//

import SwiftUI

struct SearchView: View {
    @State private var viewModel: SearchViewModel
    @State private var indexers: IndexerStore
    @State private var showingAddIndexer = false

    init(viewModel: SearchViewModel = SearchViewModel(), indexers: IndexerStore = .shared) {
        _viewModel = State(initialValue: viewModel)
        _indexers = State(initialValue: indexers)
    }

    var body: some View {
        content
            .navigationTitle("Search")
            .searchable(text: $viewModel.query, prompt: Text("Search your indexers"))
            .onSubmit(of: .search) { Task { await viewModel.search() } }
            .onChange(of: viewModel.query) { _, new in
                if new.isEmpty { viewModel.clear() }
            }
            .toolbar {
                if indexers.hasIndexers {
                    ToolbarItem(placement: .topBarTrailing) { sortAndFilterMenu }
                }
            }
            .sheet(isPresented: $showingAddIndexer) {
                NavigationStack { AddIndexerView(isModal: true) }
                    .presentationSizing(.form)
            }
    }

    @ViewBuilder
    private var content: some View {
        if !indexers.hasIndexers {
            noIndexers
        } else {
            switch viewModel.state {
            case .idle: idle
            case .searching: searching
            case .failed(let message): failed(message)
            case .results: results
            }
        }
    }

    // MARK: - States

    private var noIndexers: some View {
        ContentUnavailableView {
            Label("No Indexers", systemImage: "magnifyingglass")
        } description: {
            Text("Add a Newznab indexer, or NZBHydra2 or Prowlarr, to search for NZBs right here.")
        } actions: {
            Button("Add Indexer") { showingAddIndexer = true }
                .buttonStyle(.glassProminent)
        }
    }

    @ViewBuilder
    private var idle: some View {
        if viewModel.recentSearches.isEmpty {
            ContentUnavailableView {
                Label("Search Your Indexers", systemImage: "magnifyingglass")
            } description: {
                Text("Results from ^[\(indexers.enabledAccounts.count) indexer](inflect: true) appear here. Tap the arrow on one to download it.")
            }
        } else {
            List {
                Section("Recent Searches") {
                    ForEach(viewModel.recentSearches, id: \.self) { recent in
                        Button {
                            Task { await viewModel.search(for: recent) }
                        } label: {
                            Label { Text(verbatim: recent) } icon: { Image(systemName: "clock.arrow.circlepath") }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
        }
    }

    private var searching: some View {
        ProgressView {
            Text("Searching ^[\(indexers.enabledAccounts.count) indexer](inflect: true)…")
        }
    }

    private func failed(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Search Failed", systemImage: "exclamationmark.triangle")
        } description: {
            Text(verbatim: message)
        } actions: {
            Button("Try Again") { Task { await viewModel.search() } }
                .buttonStyle(.glass)
        }
    }

    private var results: some View {
        List {
            Section {
                categoryChips
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            .listSectionSpacing(.compact)

            if viewModel.visibleResults.isEmpty {
                ContentUnavailableView.search(text: viewModel.query)
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(viewModel.visibleResults) { result in
                        SearchResultRow(result: result) { viewModel.download(result) }
                    }
                } footer: {
                    Text("^[\(viewModel.visibleResults.count) result](inflect: true)")
                }
            }
        }
        .alert("Download Failed", isPresented: downloadErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: viewModel.downloadError ?? "")
        }
    }

    // MARK: - Controls

    /// Horizontally scrolling category filter. Seven categories are too many for a segmented
    /// control on iPhone.
    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(IndexerCategory.allCases) { category in
                    let isSelected = viewModel.category == category
                    Button {
                        viewModel.category = category
                    } label: {
                        Label(category.title, systemImage: category.systemImage)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .background(isSelected ? Color.accentColor : Color(.secondarySystemFill), in: Capsule())
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    private var sortAndFilterMenu: some View {
        Menu {
            Picker(selection: $viewModel.sort) {
                ForEach(IndexerSort.allCases) { Text($0.title).tag($0) }
            } label: {
                Label("Sort By", systemImage: "arrow.up.arrow.down")
            }
            .pickerStyle(.menu)

            if indexers.accounts.count > 1 {
                Picker(selection: $viewModel.indexerFilter) {
                    Text("All Indexers").tag(UUID?.none)
                    ForEach(indexers.accounts) { Text(verbatim: $0.name).tag(UUID?.some($0.id)) }
                } label: {
                    Label("Indexer", systemImage: "server.rack")
                }
                .pickerStyle(.menu)
            }
        } label: {
            Label("Sort and Filter", systemImage: "line.3.horizontal.decrease")
        }
    }

    private var downloadErrorBinding: Binding<Bool> {
        Binding(get: { viewModel.downloadError != nil },
                set: { if !$0 { viewModel.downloadError = nil } })
    }
}

#if DEBUG
enum SearchPreviewData {
    static let geek = IndexerAccount(name: "NZBGeek", url: "https://api.nzbgeek.info")
    static let planet = IndexerAccount(name: "NZBPlanet", url: "https://api.nzbplanet.net")
    static let hydra = IndexerAccount(name: "NZBHydra2", url: "http://192.168.1.20:5076", isEnabled: false)

    static var store: IndexerStore { IndexerStore(previewAccounts: [geek, planet, hydra]) }

    static func result(_ title: String, _ indexer: IndexerAccount, _ category: IndexerCategory,
                       gigabytes: Double, hoursAgo: Double, grabs: Int?) -> IndexerResult {
        IndexerResult(id: UUID().uuidString, title: title, indexerID: indexer.id, indexerName: indexer.name,
                      category: category, sizeBytes: Int(gigabytes * 1_073_741_824),
                      publishedAt: .now.addingTimeInterval(-hoursAgo * 3600), grabs: grabs,
                      nzbURL: URL(string: "https://example.com/get/\(UUID().uuidString).nzb")!)
    }

    static let results: [IndexerResult] = [
        result("Big.Buck.Bunny.2008.2160p.UHD.BluRay.x265-OPEN", geek, .movies, gigabytes: 6.4, hoursAgo: 3, grabs: 1204),
        result("Sintel.2010.1080p.BluRay.x264-BLENDER", planet, .movies, gigabytes: 2.1, hoursAgo: 26, grabs: 388),
        result("Tears.of.Steel.2012.1080p.WEB-DL.AAC2.0.H.264", geek, .movies, gigabytes: 1.7, hoursAgo: 72, grabs: 96),
        result("ubuntu-24.04.1-desktop-amd64", geek, .software, gigabytes: 5.8, hoursAgo: 5, grabs: 2310),
        result("Nine.Inch.Nails-Ghosts.I-IV-2008-FLAC", planet, .audio, gigabytes: 1.1, hoursAgo: 340, grabs: 57),
        result("Night.of.the.Living.Dead.1968.Restored.720p", planet, .movies, gigabytes: 0.9, hoursAgo: 900, grabs: nil),
    ]

    static func viewModel(searched: Bool) -> SearchViewModel {
        let vm = SearchViewModel(store: store) { _, _, _ in results }
        if searched {
            vm.query = "open movie"
            Task { await vm.search() }
        }
        return vm
    }
}

#Preview("Results") {
    NavigationStack {
        SearchView(viewModel: SearchPreviewData.viewModel(searched: true), indexers: SearchPreviewData.store)
    }
}

#Preview("Before Searching") {
    NavigationStack {
        SearchView(viewModel: SearchPreviewData.viewModel(searched: false), indexers: SearchPreviewData.store)
    }
}

#Preview("No Indexers") {
    NavigationStack {
        SearchView(viewModel: SearchViewModel(store: IndexerStore(previewAccounts: [])),
                   indexers: IndexerStore(previewAccounts: []))
    }
}
#endif
