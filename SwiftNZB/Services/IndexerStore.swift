//
//  IndexerStore.swift
//  SwiftNZB
//
//  The configured Newznab indexers. Metadata is persisted as JSON in UserDefaults; each API key
//  and custom-header list lives in the Keychain under the indexer's id, the same split ServerStore
//  uses for passwords.
//

import Foundation
import Observation

@MainActor
@Observable
final class IndexerStore {
    static let shared = IndexerStore()

    private(set) var accounts: [IndexerAccount] = []

    private let key = "indexers.v1"
    /// Set once this device's local-only indexers (from builds before iCloud sync) are merged in.
    private let migratedKey = "indexers.v1.mergedIntoICloud"
    private let defaults = UserDefaults.standard
    private let kvs = NSUbiquitousKeyValueStore.default
    /// False for preview stores, which must never write to the real defaults, iCloud or Keychain.
    private let persists: Bool

    private init() {
        persists = true
        load()
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvs, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.load()
                // iCloud has now delivered its copy, so merging can't overwrite another device's list.
                self?.mergeLocalIndexersOnce()
            }
        }
        kvs.synchronize()
        if kvs.data(forKey: key) != nil {
            mergeLocalIndexersOnce()
        } else {
            // An empty iCloud store may never send a change notification; merge after a grace
            // period that gives a non-empty one time to arrive first.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(10))
                self?.mergeLocalIndexersOnce()
            }
        }
    }

    /// An in-memory store for previews.
    init(previewAccounts: [IndexerAccount]) {
        persists = false
        accounts = previewAccounts
    }

    var hasIndexers: Bool { !accounts.isEmpty }
    var enabledAccounts: [IndexerAccount] { accounts.filter(\.isEnabled) }

    func upsert(_ account: IndexerAccount, apiKey: String, headers: [IndexerHeader] = []) {
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
        if persists {
            Keychain.setPassword(apiKey, for: account.id.uuidString, service: Keychain.indexerAPIKeyService)
            if headers.isEmpty {
                Keychain.deletePassword(for: account.id.uuidString, service: Keychain.indexerHeadersService)
            } else if let data = try? JSONEncoder().encode(headers) {
                Keychain.setPassword(String(decoding: data, as: UTF8.self), for: account.id.uuidString,
                                     service: Keychain.indexerHeadersService)
            }
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
            Keychain.deletePassword(for: id.uuidString, service: Keychain.indexerHeadersService)
        }
        save()
    }

    func apiKey(for id: UUID) -> String? {
        guard persists else { return nil }
        return Keychain.password(for: id.uuidString, service: Keychain.indexerAPIKeyService)
    }

    func headers(for id: UUID) -> [IndexerHeader] {
        guard persists,
              let json = Keychain.password(for: id.uuidString, service: Keychain.indexerHeadersService),
              let headers = try? JSONDecoder().decode([IndexerHeader].self, from: Data(json.utf8)) else { return [] }
        return headers
    }

    // MARK: - Persistence

    /// The list syncs through iCloud Key-Value Store (mirrored to UserDefaults, local-only when
    /// iCloud is unavailable), like ServerStore. API keys and headers ride along separately in the
    /// synchronizable Keychain, so they can arrive a moment after the list on another device.
    private func load() {
        accounts = Self.decode(kvs.data(forKey: key)) ?? Self.decode(defaults.data(forKey: key)) ?? []
    }

    /// Builds before iCloud sync kept indexers in UserDefaults only. The iCloud copy is one blob
    /// with last-writer-wins, so the first device to save would replace the other's list; instead,
    /// each device adds its own local indexers once, matched by id.
    private func mergeLocalIndexersOnce() {
        guard !defaults.bool(forKey: migratedKey) else { return }
        let local = Self.decode(defaults.data(forKey: key)) ?? []
        let missing = local.filter { indexer in !accounts.contains { $0.id == indexer.id } }
        if !missing.isEmpty {
            accounts += missing
            save()
        } else if kvs.data(forKey: key) == nil, !accounts.isEmpty {
            save()
        }
        defaults.set(true, forKey: migratedKey)
    }

    private static func decode(_ data: Data?) -> [IndexerAccount]? {
        data.flatMap { try? JSONDecoder().decode([IndexerAccount].self, from: $0) }
    }

    private func save() {
        guard persists, let data = try? JSONEncoder().encode(accounts) else { return }
        defaults.set(data, forKey: key)
        kvs.set(data, forKey: key)
        kvs.synchronize()
    }
}
