//
//  IndexersSettingsView.swift
//  SwiftNZB
//

import SwiftUI

struct IndexersSettingsView: View {
    @State private var store: IndexerStore

    init(store: IndexerStore? = nil) {
        _store = State(initialValue: store ?? .shared)
    }

    var body: some View {
        List {
            Section {
                ForEach(store.accounts) { account in
                    NavigationLink {
                        AddIndexerView(existing: account, store: store)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: account.name)
                                Text(verbatim: account.displayHost)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if !account.isEnabled {
                                Spacer()
                                Text("Off")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) { store.remove(account.id) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                NavigationLink { AddIndexerView(store: store) } label: {
                    Label("Add Indexer", systemImage: "plus")
                }
            } footer: {
                Text("Indexers you have an account with. NZBHydra2 and Prowlarr work too: add them with their Newznab URL and API key.")
            }
        }
        .navigationTitle("Indexers")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
#Preview("Indexers") {
    NavigationStack { IndexersSettingsView(store: SearchPreviewData.store) }
}
#endif
