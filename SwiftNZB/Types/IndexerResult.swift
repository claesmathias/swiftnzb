//
//  IndexerResult.swift
//  SwiftNZB
//

import SwiftUI

/// The Newznab top-level categories a search can be narrowed to. Newznab numbers categories in
/// thousands (2000 Movies, 5000 TV, …); subcategories such as 2040 (Movies/HD) fold into their
/// parent here.
enum IndexerCategory: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all, movies, tv, audio, books, software, other

    var id: String { rawValue }

    /// The Newznab `cat` parameter for this category; nil searches every category.
    var newznabID: Int? {
        switch self {
        case .all: return nil
        case .movies: return 2000
        case .tv: return 5000
        case .audio: return 3000
        case .books: return 7000
        case .software: return 4000
        case .other: return 8000
        }
    }

    /// Maps any Newznab category number (including subcategories) to its top-level category.
    init(newznabID: Int) {
        switch newznabID / 1000 {
        case 2: self = .movies
        case 5: self = .tv
        case 3: self = .audio
        case 7: self = .books
        case 4: self = .software
        default: self = .other
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .all: return "All"
        case .movies: return "Movies"
        case .tv: return "TV"
        case .audio: return "Audio"
        case .books: return "Books"
        case .software: return "Software"
        case .other: return "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .movies: return "film"
        case .tv: return "tv"
        case .audio: return "music.note"
        case .books: return "book"
        case .software: return "app.badge"
        case .other: return "shippingbox"
        }
    }

    var tint: Color {
        switch self {
        case .all: return .secondary
        case .movies: return .purple
        case .tv: return .blue
        case .audio: return .pink
        case .books: return .brown
        case .software: return .teal
        case .other: return .gray
        }
    }
}

/// One item from an indexer's search results.
struct IndexerResult: Identifiable, Hashable, Sendable {
    /// The indexer's GUID for the release, unique per indexer.
    var id: String
    var title: String
    var indexerID: UUID
    var indexerName: String
    var category: IndexerCategory
    var sizeBytes: Int
    var publishedAt: Date
    /// How often the NZB was downloaded, when the indexer reports it.
    var grabs: Int?
    /// Where the .nzb file is fetched from.
    var nzbURL: URL
}

/// How search results are ordered.
enum IndexerSort: String, CaseIterable, Identifiable, Sendable {
    case newest, largest, mostGrabbed

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .newest: return "Newest"
        case .largest: return "Largest"
        case .mostGrabbed: return "Most Grabbed"
        }
    }

    func sorted(_ results: [IndexerResult]) -> [IndexerResult] {
        switch self {
        case .newest: return results.sorted { $0.publishedAt > $1.publishedAt }
        case .largest: return results.sorted { $0.sizeBytes > $1.sizeBytes }
        case .mostGrabbed: return results.sorted { ($0.grabs ?? 0) > ($1.grabs ?? 0) }
        }
    }
}
