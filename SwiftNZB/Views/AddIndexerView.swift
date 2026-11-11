//
//  AddIndexerView.swift
//  SwiftNZB
//

import SwiftUI
import NewznabKit

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
    @State private var kind: IndexerKind
    @State private var confirmingDelete = false
    @State private var testState: TestState = .idle
    @State private var headers: [IndexerHeader]
    /// False until the stored headers are loaded, so onAppear runs that once.
    @State private var loadedHeaders: Bool

    enum TestState: Equatable { case idle, testing, success(String), failure(String) }

    /// `initialHeaders` bypasses the Keychain, for previews.
    init(existing: IndexerAccount? = nil, store: IndexerStore? = nil, isModal: Bool = false,
         initialHeaders: [IndexerHeader]? = nil) {
        self.existing = existing
        self.store = store ?? .shared
        self.isModal = isModal
        _name = State(initialValue: existing?.name ?? "")
        _url = State(initialValue: existing?.url ?? "")
        _isEnabled = State(initialValue: existing?.isEnabled ?? true)
        _kind = State(initialValue: existing?.kind ?? .newznab)
        _headers = State(initialValue: initialHeaders ?? [])
        _loadedHeaders = State(initialValue: initialHeaders != nil)
    }

    private var trimmedURL: String { url.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// HTTPS only: the API key travels in every request's query string. A bare host gets https://.
    private var parsedURL: URL? { NewznabRequest.baseURL(from: trimmedURL) }

    private var trimmedKey: String { apiKey.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The headers to store: trimmed, with rows left completely empty dropped.
    private var cleanedHeaders: [IndexerHeader] {
        headers.map { IndexerHeader(id: $0.id, name: $0.name.trimmingCharacters(in: .whitespaces),
                                    value: $0.value.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.name.isEmpty || !$0.value.isEmpty }
    }

    private func isValid(_ header: IndexerHeader) -> Bool {
        NewznabRequest.isValidHeaderName(header.name) && NewznabRequest.isValidHeaderValue(header.value)
    }

    private var headersAreValid: Bool { cleanedHeaders.allSatisfy(isValid) }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && parsedURL != nil && !trimmedKey.isEmpty
            && headersAreValid
    }

    var body: some View {
        Form {
            Section {
                Picker("Type", selection: $kind) {
                    Text(verbatim: "Newznab").tag(IndexerKind.newznab)
                    Text(verbatim: "Prowlarr").tag(IndexerKind.prowlarr)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } footer: {
                switch kind {
                case .newznab:
                    Text("A Newznab indexer such as NZBGeek, or NZBHydra2.")
                case .prowlarr:
                    Text("Searches every Usenet indexer in your Prowlarr at once.")
                }
            }

            Section {
                TextField("Name", text: $name, prompt: Text(verbatim: kind == .prowlarr ? "Prowlarr" : "NZBGeek"))
                TextField("URL", text: $url, prompt: Text(verbatim: kind == .prowlarr
                                                          ? "https://prowlarr.example.com"
                                                          : "https://api.nzbgeek.info"))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textContentType(.URL)
                if !trimmedURL.isEmpty, parsedURL == nil {
                    Text("Use an https:// address. Plain HTTP isn't supported, because it would send your API key unencrypted.")
                        .font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("Indexer")
            } footer: {
                if kind == .prowlarr {
                    Text("Prowlarr's own address, the one you open in a browser.")
                }
            }

            Section {
                SecureField("API Key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("API Key")
            } footer: {
                switch kind {
                case .newznab: Text("Find it on your indexer's profile or API page.")
                case .prowlarr: Text("In Prowlarr: Settings → General → Security → API Key.")
                }
            }

            headersSection

            Section {
                Toggle("Use for Searches", isOn: $isEnabled)
            }

            Section {
                Button {
                    Task { await test() }
                } label: {
                    HStack {
                        Text("Test Connection")
                        Spacer()
                        switch testState {
                        case .idle: EmptyView()
                        case .testing: ProgressView()
                        case .success: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        case .failure: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                        }
                    }
                }
                .disabled(parsedURL == nil || trimmedKey.isEmpty || !headersAreValid || testState == .testing)

                switch testState {
                case .failure(let message):
                    Text(verbatim: message).font(.caption).foregroundStyle(.red)
                case .success(let message):
                    Text(verbatim: message).font(.caption).foregroundStyle(.green)
                default:
                    Text("Checks the address and API key with the indexer.")
                        .font(.caption).foregroundStyle(.secondary)
                }
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
            if let existing, !loadedHeaders {
                headers = store.headers(for: existing.id)
                loadedHeaders = true
            }
        }
        .onChange(of: url) { testState = .idle }
        .onChange(of: apiKey) { testState = .idle }
        .onChange(of: headers) { testState = .idle }
        // Not while testing: the auto-switch to Prowlarr changes the type mid-check.
        .onChange(of: kind) { if testState != .testing { testState = .idle } }
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

    private var headersSection: some View {
        Section {
            ForEach(headers) { header in
                NavigationLink {
                    IndexerHeaderEditor(header: header, isNew: false) { updated in
                        if let index = headers.firstIndex(where: { $0.id == updated.id }) {
                            headers[index] = updated
                        }
                    }
                } label: {
                    IndexerHeaderRow(header: header)
                }
            }
            .onDelete { headers.remove(atOffsets: $0) }

            NavigationLink {
                IndexerHeaderEditor(isNew: true) { headers.append($0) }
            } label: {
                Label("Add Header", systemImage: "plus")
            }
            NavigationLink {
                BasicAuthenticationEditor { addOrReplace(IndexerHeader(name: "Authorization", value: $0)) }
            } label: {
                Label("Add Basic Authentication", systemImage: "person.badge.key")
            }
        } header: {
            HStack {
                Text("Custom Headers")
                Spacer()
                // PasteButton reads the clipboard without the "allow paste" prompt.
                PasteButton(payloadType: String.self) { strings in
                    let pasted = strings.flatMap { NewznabRequest.parseHeaderLines($0) }
                    for header in pasted { addOrReplace(IndexerHeader(name: header.name, value: header.value)) }
                }
                .labelStyle(.titleOnly)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
            }
        } footer: {
            Text("Optional. Sent with every request to this indexer and stored in the Keychain. Use them for a proxy such as Cloudflare Access: Paste takes lines like CF-Access-Client-Id: …")
        }
    }

    /// Adds a header, or updates the value of one with the same name (case-insensitive), so pasting
    /// a rotated token replaces the old one instead of duplicating it.
    private func addOrReplace(_ header: IndexerHeader) {
        if let index = headers.firstIndex(where: { $0.name.caseInsensitiveCompare(header.name) == .orderedSame }) {
            headers[index].value = header.value
        } else {
            headers.append(header)
        }
    }

    private func test() async {
        guard let parsedURL else { return }
        testState = .testing
        do {
            do {
                let message = try await IndexerSearchService.test(kind: kind, url: parsedURL.absoluteString,
                                                                  apiKey: trimmedKey, headers: cleanedHeaders)
                testState = .success(message)
            } catch NewznabError.prowlarrRoot where kind == .newznab {
                // The address is Prowlarr itself: switch the type and check again as Prowlarr.
                kind = .prowlarr
                testState = .testing
                let message = try await IndexerSearchService.test(kind: .prowlarr, url: parsedURL.absoluteString,
                                                                  apiKey: trimmedKey, headers: cleanedHeaders)
                testState = .success(String(localized: "This is Prowlarr, so the type was switched to Prowlarr. \(message)"))
            }
        } catch {
            testState = .failure(error.localizedDescription)
        }
    }

    private func save() {
        guard let parsedURL else { return }
        var account = existing ?? IndexerAccount()
        account.name = name.trimmingCharacters(in: .whitespaces)
        // Store the normalized https URL, so a bare host typed in is saved with its scheme.
        account.url = parsedURL.absoluteString
        account.isEnabled = isEnabled
        account.kind = kind
        store.upsert(account, apiKey: trimmedKey, headers: cleanedHeaders)
        dismiss()
    }
}

#if DEBUG
#Preview("Add Indexer") {
    NavigationStack { AddIndexerView(store: SearchPreviewData.store) }
}

#Preview("Edit Indexer") {
    NavigationStack {
        AddIndexerView(existing: SearchPreviewData.geek, store: SearchPreviewData.store,
                       initialHeaders: [IndexerHeader(name: "User-Agent", value: "SwiftNZB/1.1"),
                                        IndexerHeader(name: "Authorization", value: "Bearer abc123")])
    }
}
#endif

#if DEBUG
#Preview("Prowlarr") {
    NavigationStack {
        AddIndexerView(existing: IndexerAccount(name: "Prowlarr", url: "https://prowlarr.example.com", kind: .prowlarr),
                       store: SearchPreviewData.store,
                       initialHeaders: [IndexerHeader(name: "CF-Access-Client-Id", value: "example-id.access"),
                                        IndexerHeader(name: "CF-Access-Client-Secret", value: "secret")])
    }
}
#endif
