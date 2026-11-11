//
//  SearchResultRow.swift
//  SwiftNZB
//

import SwiftUI

/// One indexer result: the release title, then category, size and age, then where it came from.
struct SearchResultRow: View {
    let result: IndexerResult
    let onDownload: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: result.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)

                HStack(spacing: 6) {
                    CategoryChip(category: result.category)
                    Text(verbatim: Format.bytes(result.sizeBytes))
                    Text(verbatim: "·")
                    Text(result.publishedAt, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Label { Text(verbatim: result.indexerName) } icon: { Image(systemName: "server.rack") }
                    if let grabs = result.grabs {
                        Label { Text(verbatim: "\(grabs)") } icon: { Image(systemName: "arrow.down") }
                            .accessibilityLabel(Text("^[\(grabs) grab](inflect: true)"))
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .labelStyle(CompactLabelStyle())
            }

            Spacer(minLength: 8)

            Button(action: onDownload) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Download"))
        }
        .padding(.vertical, 2)
    }
}

/// A small tinted capsule naming a result's category.
struct CategoryChip: View {
    let category: IndexerCategory

    var body: some View {
        Label(category.title, systemImage: category.systemImage)
            .font(.caption2.weight(.semibold))
            .labelStyle(CompactLabelStyle())
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(category.tint.opacity(0.15), in: Capsule())
            .foregroundStyle(category.tint)
    }
}

/// Icon and title with a tighter gap than the default label style.
private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
            configuration.title
        }
    }
}
