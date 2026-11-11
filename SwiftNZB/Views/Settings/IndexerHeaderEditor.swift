//
//  IndexerHeaderEditor.swift
//  SwiftNZB
//
//  Edits one custom HTTP header of an indexer. Pushed from AddIndexerView, so the form itself only
//  lists headers as compact rows.
//

import SwiftUI
import NewznabKit

struct IndexerHeaderEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var header: IndexerHeader
    private let isNew: Bool
    private let onSave: (IndexerHeader) -> Void

    init(header: IndexerHeader = IndexerHeader(), isNew: Bool, onSave: @escaping (IndexerHeader) -> Void) {
        _header = State(initialValue: header)
        self.isNew = isNew
        self.onSave = onSave
    }

    /// Headers people actually need for an indexer, offered as one-tap names.
    private static let suggestions: [(name: String, hint: LocalizedStringKey)] = [
        ("User-Agent", "When the indexer only accepts certain apps"),
        ("Authorization", "Credentials for a proxy in front of the indexer"),
        ("Cookie", "A session the indexer or its proxy expects"),
    ]

    private var name: String { header.name.trimmingCharacters(in: .whitespaces) }
    private var value: String { header.value.trimmingCharacters(in: .whitespaces) }

    private var problem: LocalizedStringKey? {
        if name.isEmpty { return nil }
        if !NewznabRequest.isValidHeaderName(name) {
            return "Use only letters, digits and - _ . in a header name, without spaces."
        }
        if !NewznabRequest.isValidHeaderValue(value) { return "The value can't contain line breaks." }
        return nil
    }

    private var canSave: Bool { !name.isEmpty && problem == nil }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $header.name, prompt: Text(verbatim: "User-Agent"))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
            } header: {
                Text("Name")
            } footer: {
                if let problem {
                    Text(problem).foregroundStyle(.red)
                }
            }

            Section("Value") {
                TextField("Value", text: $header.value, prompt: Text("Value"), axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                    .lineLimit(1...4)
            }

            Section("Common Headers") {
                ForEach(Self.suggestions, id: \.name) { suggestion in
                    Button {
                        header.name = suggestion.name
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: suggestion.name)
                                    .font(.body.monospaced())
                                    .foregroundStyle(.primary)
                                Text(suggestion.hint)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if name.caseInsensitiveCompare(suggestion.name) == .orderedSame {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(isNew ? "Add Header" : "Edit Header")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isNew ? "Add" : "Done") {
                    onSave(IndexerHeader(id: header.id, name: name, value: value))
                    dismiss()
                }
                .disabled(!canSave)
            }
        }
    }
}

/// One header as a compact list row: the name, and below it the value (masked for credentials).
struct IndexerHeaderRow: View {
    let header: IndexerHeader

    /// Names whose value is a secret and is shown masked in the list.
    private var isSensitive: Bool {
        let lower = header.name.lowercased()
        return ["authorization", "proxy-authorization", "cookie"].contains(lower)
            || ["token", "key", "secret", "password"].contains { lower.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: header.name)
                .font(.body.monospaced())
            Group {
                if header.value.isEmpty {
                    Text("Empty value")
                } else if isSensitive {
                    Text(verbatim: "••••••••")
                } else {
                    Text(verbatim: header.value)
                }
            }
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }
}

#if DEBUG
#Preview("Add Header") {
    NavigationStack { IndexerHeaderEditor(isNew: true) { _ in } }
}
#endif
