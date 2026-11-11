//
//  IndexerStore.swift
//  SwiftNZB
//
//  The configured Newznab indexers. Metadata is persisted as JSON in UserDefaults; each API key
//  lives in the Keychain under the indexer's id, the same split ServerStore uses for passwords.
//

import Foundation
import Observation

@MainActor
@Observable
final class IndexerStore {
    static let shared = IndexerStore()

    private(set) var accounts: [IndexerAccount] = []

    private let key = "indexers.v1"
    private let defaults = UserDefaults.standard
    /// False for preview stores, which must never write to the real defaults or Keychain.
    private let persists: Bool

    private init() {
        persists = true
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([IndexerAccount].self, from: data) {
            accounts = decoded
        }
    }

    /// An in-memory store for previews.
    init(previewAccounts: [IndexerAccount]) {
        persists = false
        accounts = previewAccounts
    }

    var hasIndexers: Bool { !accounts.isEmpty }
    var enabledAccounts: [IndexerAccount] { accounts.filter(\.isEnabled) }

    func upsert(_ account: IndexerAccount, apiKey: String) {
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
        if persists {
            Keychain.setPassword(apiKey, for: account.id.uuidString, service: Keychain.indexerAPIKeyService)
        }
        save()
    }

    func setEnabled(_ enabled: Bool, for id: UUID) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[index].isEnabled = enabled
        save()
    }

    func remove(_ id: UUID) {
        accounts.removeAll { $0.id == id }
        if persists {
            Keychain.deletePassword(for: id.uuidString, service: Keychain.indexerAPIKeyService)
        }
        save()
    }

    func apiKey(for id: UUID) -> String? {
        guard persists else { return nil }
        return Keychain.password(for: id.uuidString, service: Keychain.indexerAPIKeyService)
    }

    private func save() {
        guard persists, let data = try? JSONEncoder().encode(accounts) else { return }
        defaults.set(data, forKey: key)
    }
}
