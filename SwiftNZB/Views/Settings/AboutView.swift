//
//  AboutView.swift
//  SwiftNZB
//

import SwiftUI

struct AboutView: View {
    /// The repository releases are published to. Each release is tagged `v<CFBundleShortVersionString>`.
    private static let repositoryURL = URL(string: "https://github.com/claesmathias/swiftnzb")!

    private var marketingVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var appVersion: String {
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(marketingVersion) (\(b))"
    }

    /// The GitHub release page for the running version, e.g. …/releases/tag/v1.2.0.
    private var releaseURL: URL {
        Self.repositoryURL.appending(path: "releases/tag/v\(marketingVersion)")
    }

    var body: some View {
        Form {
            Section {
                Link(destination: releaseURL) {
                    LabeledContent("Version") {
                        HStack(spacing: 4) {
                            Text(verbatim: appVersion)
                            Image(systemName: "arrow.up.right.square")
                                .imageScale(.small)
                        }
                    }
                }
                .accessibilityHint(Text("Opens the release notes for this version on GitHub."))
                Link(destination: Self.repositoryURL) {
                    Label("Source on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            } footer: {
                Text("Tap the version for its release notes.")
            }
            Section {
                Text("SwiftNZB is a native client for the Usenet (NNTP) protocol. Bring your own provider account, and your own NZB files or Newznab indexers. PAR2 verification and repair is a clean-room implementation. RAR extraction uses the UnRAR library.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section {
                Text("SwiftNZB ships no content. Searches go only to the indexers you add. You are responsible for what you download, and it should only be material you have the right to.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
#Preview("About") {
    NavigationStack { AboutView() }
}
#endif
