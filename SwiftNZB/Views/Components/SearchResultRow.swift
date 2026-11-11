//
//  SearchResultRow.swift
//  SwiftNZB
//

import SwiftUI

/// One indexer result: the release title, then category, size and age, then where it came from.
struct SearchResultRow: View {
    let result: IndexerResult
    /// True while the .nzb is being fetched; the arrow becomes a spinner.
    var isDownloading = false
    let onDownload: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: Self.wrappable(result.title))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)

                HStack(spacing: 6) {
                    CategoryChip(category: result.category)
                    if let size = result.sizeBytes {
                        Text(verbatim: Format.bytes(size))
                    }
                    if result.sizeBytes != nil, result.publishedAt != nil {
                        Text(verbatim: "·")
                    }
                    if let published = result.publishedAt {
                        Text(published, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Label { Text(verbatim: result.indexerName).fontWeight(.medium) } icon: { Image(systemName: "server.rack") }
                    if let grabs = result.grabs {
                        Label { Text(verbatim: "\(grabs)") } icon: { Image(systemName: "arrow.down") }
                            .accessibilityLabel(Text("^[\(grabs) grab](inflect: true)"))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(CompactLabelStyle())
            }

            Spacer(minLength: 8)

            Button(action: onDownload) {
                Group {
                    if isDownloading {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.title)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .disabled(isDownloading)
            .accessibilityLabel(Text("Download"))
        }
        .padding(.vertical, 2)
    }

    /// Release names use dots and dashes instead of spaces, so without a break opportunity the
    /// text wraps mid-word. A zero-width space after each separator lets lines break there.
    private static func wrappable(_ title: String) -> String {
        title.replacing(".", with: ".\u{200B}")
            .replacing("-", with: "-\u{200B}")
            .replacing("_", with: "_\u{200B}")
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
