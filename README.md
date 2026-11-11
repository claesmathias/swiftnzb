<p align="center">
  <img src="docs/appicon.png" alt="SwiftNZB app icon" width="160" height="160">
</p>

<h1 align="center">SwiftNZB</h1>

<p align="center">
  A native SwiftUI <b>Usenet NZB downloader</b> for iPhone and iPad, with built-in indexer search.
</p>

<p align="center">
  <a href="https://github.com/claesmathias/swiftnzb/releases/latest">Latest release</a> ·
  fork of <a href="https://github.com/valentinlehmann/swiftnzb">valentinlehmann/swiftnzb</a>
</p>

Bring your own Usenet server, then search your own Newznab indexers or Prowlarr from inside the
app, or hand it NZB files. SwiftNZB downloads the article segments over many parallel TLS
connections, decodes yEnc, reassembles the files, verifies/repairs them with PAR2, extracts RAR
archives, and saves the result to the Files app — with a Live Activity showing live progress on
the Lock Screen and in the Dynamic Island.

The app bundles **no indexers and no content**: searches go only to the indexers you add, and
downloads only to the server you configure. Every feature is free.

## What this fork adds

- **Indexer search** — a Search tab that queries every enabled indexer at once.
- **Prowlarr support** — one entry searches all of Prowlarr's Usenet indexers.
- **Custom headers** for indexers behind a proxy such as Cloudflare Access.
- **No Pro tier** — the paywall, purchases and download limit are gone.
- **iCloud sync** of indexers between your devices.
- A fixed Dynamic Island layout, and the About screen links each version to its release notes.

See the [releases](https://github.com/claesmathias/swiftnzb/releases) for what changed in each
version.

## Features

### Search

- **Search every indexer at once** — results from all enabled indexers in one list, filtered by
  category (Movies, TV, Audio, Books, Software, Other) and sorted by newest, largest or most
  grabbed.
- **See which indexer returned what** — a per-indexer breakdown with counts above the results
  (tap one to see only its results), including each indexer behind Prowlarr.
- **One tap to download** — the result's .nzb is fetched and opens the usual *Add Download*
  sheet, where you pick files and the server.
- **Newznab indexers** such as NZBGeek, plus NZBHydra2 or a single Prowlarr indexer feed.
- **Prowlarr** via its own API: enter Prowlarr's address and API key once to search all of its
  Usenet indexers; torrent results are left out.
- **Custom headers** per indexer: paste `Name: Value` lines (e.g. a Cloudflare Access service
  token), add HTTP Basic authentication, or edit headers one by one.
- **Clear setup errors** — a website address instead of the API, Prowlarr entered as a Newznab
  feed (Test Connection switches the type for you), Cloudflare Access blocking the request, a
  refused API key, or an indexer's grab limit.
- **One failing indexer never hides the others** — its error is listed below the results.

### Downloading

- **Fast parallel downloads** — a fixed pool of long-lived, authenticated NNTP connections pulls
  segments from a shared scheduler; the auth handshake is reused across segments.
- **yEnc decode + CRC32 verification** of every article segment.
- **Streaming assembly to disk** — each segment is written at its `=ypart` byte offset into a
  sparse `.part` file, so the scratch file *is* the output; finalize just renames.
- **Resume-safe** — the segment is the atomic, idempotent unit. Checkpoints + positional writes
  mean a dropped connection, a backgrounded app, or a killed process degrades throughput but
  never corrupts state.
- **PAR2 verify + repair** — a clean-room Swift Reed-Solomon implementation (no GPL).
- **RAR extraction** via the UnRAR library.
- **Mobile-network resilience** — `NWPathMonitor` parks/resumes on connectivity changes,
  per-request stall timeouts kill half-open cellular sockets, per-segment exponential backoff
  with jitter, and the active-connection count adapts to degraded links.
- **Live Activity** on the Lock Screen and Dynamic Island for the active download, with
  pause/resume.

### Everything else

- **Multiple servers** with a default pick, per-server usage tracking, and connection/bandwidth
  limits (including cellular control).
- **Flexible import** — in-app search, Files picker, Share sheet / Open-in, drag & drop, and a
  file-selection confirmation step before enqueueing.
- **App Intents & Shortcuts** for automation.
- **iCloud sync** of servers, indexers and settings (key-value store), with passwords, API keys
  and headers in iCloud Keychain. Degrades gracefully to local-only.
- **iPhone + iPad** with an adaptive tab bar / sidebar, and **English + German** localization.

## Setting up an indexer

**Settings → Indexers → Add Indexer**, then **Test Connection** before saving.

| You use | Type | URL | API key |
|---|---|---|---|
| NZBGeek | Newznab | `https://api.nzbgeek.info` (not the website `nzbgeek.info`) | your NZBGeek API key |
| Another Newznab indexer, NZBHydra2 | Newznab | the indexer's API address | the indexer's API key |
| Prowlarr, all indexers | Prowlarr | Prowlarr's address, e.g. `https://prowlarr.example.com` | Prowlarr → Settings → General → API Key |
| One Prowlarr indexer | Newznab | `https://prowlarr.example.com/<indexer id>/` | Prowlarr's API key |

**Behind Cloudflare Access?** Create a service token, allow it in the application's Access
policy (a *Service Auth* rule), and add its two headers to the indexer — copy them as

```text
CF-Access-Client-Id: <token id>.access
CF-Access-Client-Secret: <token secret>
```

and tap **Paste** next to *Custom Headers*.

> [!NOTE]
> Indexer requests are **HTTPS only**, because the API key travels in every request. Requests
> keep no cookies, and redirects are followed only on the same host. One exception is the .nzb
> download: when Prowlarr hands the download off to the source indexer, that hop is followed
> without your proxy headers or Prowlarr key.

## Screens

Four tabs, each a focused `NavigationStack`:

- **Queue** — active and waiting downloads with live speed/ETA/progress, pause/resume all, and
  drag-to-reorder for queued jobs.
- **Downloads** — completed downloads.
- **Search** — search your indexers and download results.
- **Settings** — Servers, Indexers, Connections, Bandwidth, Post-Processing, Files & Storage,
  Background, and About.

## Architecture

MVVM + `@Observable`. UI and services live in the app target; the NNTP, decode, PAR2 and
indexer-protocol specifics are isolated in three local Swift packages.

```
project.yml                  XcodeGen config (SwiftNZB app + SwiftNZBWidgets)
Localizable.xcstrings         String catalog (auto-extracted; en + de)
Packages/DownloadEngine/      NNTP transport, yEnc, CRC32, scheduler, assembler, checkpoints
Packages/PAR2Kit/             Clean-room PAR2 parse / verify / Reed-Solomon repair (no GPL)
Packages/NewznabKit/          Newznab + Prowlarr API clients, parsing, NZB validation, redirects
SwiftNZB/
  Types/                      Plain Codable models (DownloadActivityAttributes shared to widget)
  Services/                   @Observable @MainActor singletons (DownloadManager, ServerStore,
                              IndexerStore, IndexerSearchService, …)
  ViewModels/                 One @Observable view model per screen
  Views/                      Screens + reusable Views/Components/
  Intents/                    App Intents + AppShortcuts
SwiftNZBWidgets/              Live Activity (WidgetKit)
```

> [!NOTE]
> iOS **cannot** background raw-socket (NNTP) downloads — `URLSession` background mode is
> HTTP-only and `NWConnection` sockets suspend on backgrounding. Large downloads need the app
> foregrounded; background support is best-effort (`beginBackgroundTask` wind-down +
> opportunistic `BGProcessingTask` resume), made safe by checkpoint/resume.

See [`CLAUDE.md`](CLAUDE.md) for the full engineering notes and conventions.

## Requirements

- iOS 26+, Xcode 26+ (Swift 6, SwiftUI, Observation)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Ruby + Bundler (only for the optional Fastlane lanes)

## Build

The Xcode project is **generated** — edit `project.yml`, never `SwiftNZB.xcodeproj` directly,
and regenerate after adding/removing/renaming files:

```bash
xcodegen generate
xcodebuild -project SwiftNZB.xcodeproj -scheme SwiftNZB \
  -destination 'generic/platform=iOS Simulator' -configuration Debug \
  build CODE_SIGNING_ALLOWED=NO
```

Package unit tests run without a simulator:

```bash
( cd Packages/DownloadEngine && swift test )
( cd Packages/PAR2Kit && swift test )
( cd Packages/NewznabKit && swift test )
```

## Releases

Builds are signed automatically with the team in `project.yml` and distributed through
**TestFlight**, with a matching GitHub release per version. To ship a version:

1. Bump `MARKETING_VERSION` in `project.yml`, run `xcodegen generate`, and commit.
2. Archive with a timestamp build number and upload it to App Store Connect from Xcode
   (*Product → Archive → Distribute App*), or with `xcodebuild -exportArchive` as described in
   [`CLAUDE.md`](CLAUDE.md).
3. Tag the commit `v<version>` and publish a GitHub release. The app's About screen links its
   version to that tag, so they must match.

The GitHub Actions workflows are inherited from upstream and expect its signing secrets; they
are not set up for this fork.

## License

[MIT](LICENSE), as upstream. PAR2 verify/repair is a clean-room implementation (no GPL), and RAR
extraction uses the UnRAR library.
