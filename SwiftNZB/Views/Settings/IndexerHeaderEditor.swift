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
        ("CF-Access-Client-Id", "Cloudflare Access service token ID"),
        ("CF-Access-Client-Secret", "Cloudflare Access service token secret"),
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
                                    .foregroundStyle(.primary)
                                Text(suggestion.hint)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if name.caseInsensitiveCompare(suggestion.name) == .orderedSame {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                        .contentShape(.rect)
                    }
                    // A plain style keeps the row text in label colors instead of link blue.
                    .buttonStyle(.plain)
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

/// Builds an `Authorization: Basic …` header from a username and password, for a proxy that uses
/// HTTP Basic authentication. Only the encoded header is stored, not the separate fields.
struct BasicAuthenticationEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var password = ""
    let onSave: (String) -> Void

    var body: some View {
        Form {
            Section {
                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.username)
                SecureField("Password", text: $password)
                    .textContentType(.password)
            } footer: {
                Text("For a proxy or server that asks for a username and password (HTTP Basic). Saved as an Authorization header.")
            }
        }
        .navigationTitle("Basic Authentication")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    onSave(NewznabRequest.basicAuthorization(username: username, password: password))
                    dismiss()
                }
                .disabled(username.isEmpty || username.contains(":"))
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
            Group {
                if header.value.isEmpty {
                    Text("Empty value")
                } else if isSensitive {
                    Text(verbatim: "••••••••")
                } else {
                    Text(verbatim: header.value)
                }
            }
            .font(.caption)
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
