//
//  AddIndexerView.swift
//  SwiftNZB
//

import SwiftUI

struct AddIndexerView: View {
    @Environment(\.dismiss) private var dismiss
    private let store: IndexerStore
    private let existing: IndexerAccount?
    /// True when presented as a sheet (no navigation back button), so a Cancel button is shown.
    private let isModal: Bool

    @State private var name: String
    @State private var url: String
    @State private var apiKey = ""
    @State private var isEnabled: Bool
    @State private var confirmingDelete = false

    init(existing: IndexerAccount? = nil, store: IndexerStore = .shared, isModal: Bool = false) {
        self.existing = existing
        self.store = store
        self.isModal = isModal
        _name = State(initialValue: existing?.name ?? "")
        _url = State(initialValue: existing?.url ?? "")
        _isEnabled = State(initialValue: existing?.isEnabled ?? true)
    }

    private var trimmedURL: String { url.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var parsedURL: URL? {
        guard let parsed = URL(string: trimmedURL), let scheme = parsed.scheme?.lowercased(),
              ["http", "https"].contains(scheme), parsed.host() != nil else { return nil }
        return parsed
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && parsedURL != nil
            && !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        Form {
            Section("Indexer") {
                TextField("Name", text: $name)
                TextField("URL", text: $url, prompt: Text(verbatim: "https://api.indexer.example"))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textContentType(.URL)
                if !trimmedURL.isEmpty, parsedURL == nil {
                    Text("Enter the full address, starting with https://.")
                        .font(.caption).foregroundStyle(.red)
                } else if parsedURL?.scheme?.lowercased() == "http" {
                    Text("Plain HTTP sends your API key unencrypted. Use it only on your own network.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }

            Section {
                SecureField("API Key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("API Key")
            } footer: {
                Text("Find it on your indexer's profile or API page.")
            }

            Section {
                Toggle("Use for Searches", isOn: $isEnabled)
            }

            Section {
                Button {
                    // Wired to the Newznab capabilities request together with search.
                } label: {
                    Text("Test Connection")
                }
                .disabled(!canSave)
                Text("Checks the address and API key with the indexer.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if let existing {
                Section {
                    Button("Delete Indexer", role: .destructive) { confirmingDelete = true }
                        .confirmationDialog("Delete \(existing.name)?", isPresented: $confirmingDelete,
                                            titleVisibility: .visible) {
                            Button("Delete Indexer", role: .destructive) {
                                store.remove(existing.id)
                                dismiss()
                            }
                        }
                }
            }
        }
        .navigationTitle(existing == nil ? "Add Indexer" : "Edit Indexer")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let existing, apiKey.isEmpty { apiKey = store.apiKey(for: existing.id) ?? "" }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!canSave)
            }
            if isModal {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func save() {
        var account = existing ?? IndexerAccount()
        account.name = name.trimmingCharacters(in: .whitespaces)
        account.url = trimmedURL
        account.isEnabled = isEnabled
        store.upsert(account, apiKey: apiKey.trimmingCharacters(in: .whitespaces))
        dismiss()
    }
}

#if DEBUG
#Preview("Add Indexer") {
    NavigationStack { AddIndexerView(store: SearchPreviewData.store) }
}

#Preview("Edit Indexer") {
    NavigationStack { AddIndexerView(existing: SearchPreviewData.geek, store: SearchPreviewData.store) }
}
#endif
