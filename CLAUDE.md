# CLAUDE.md — SwiftNZB

Guidance for AI agents (and humans) working in this repo. Read this before making changes.

## What this is

**SwiftNZB** is a native SwiftUI app for **iPhone + iPad** that downloads **NZB files from
Usenet (NNTP)**: it parses an NZB, downloads article segments over many parallel TLS
connections, decodes **yEnc**, reassembles files, **verifies/repairs with PAR2**, **extracts
RAR** archives, and saves the result to the Files app. It shows a **Live Activity** (Lock
Screen + Dynamic Island) for the active download. Built with **XcodeGen + Fastlane**,
mirroring the author's **iobs** / Pagrr conventions.

- Min OS: **iOS 26**. Swift 6, SwiftUI, `@Observable` (Observation).
- Bundle IDs: app `de.valentinlehmann.swiftnzb`, widget `…swiftnzb.widgets`.
- Team `68BLC88PQ9`. Apple ID `info@valentinlehmann.de`.
- Distribution target: **public App Store** → no GPL code (PAR2 is clean-room, see below).

## Build / run / verify

The Xcode project is **generated** — never edit `SwiftNZB.xcodeproj` directly; edit
`project.yml`, then:

```bash
xcodegen generate
xcodebuild -project SwiftNZB.xcodeproj -scheme SwiftNZB \
  -destination 'generic/platform=iOS Simulator' -configuration Debug \
  build CODE_SIGNING_ALLOWED=NO
```

- After adding/removing/renaming **files**, run `xcodegen generate` before building (sources
  are globbed by path in `project.yml`).
- Engine logic lives in **local SPM packages** (`Packages/DownloadEngine`, `Packages/PAR2Kit`)
  — pure, deterministic, and unit-tested without the app: `cd Packages/DownloadEngine &&
  swift test` (likewise PAR2Kit). This is a deliberate deviation from iobs (which has no
  packages); the protocol/decoder/Reed-Solomon math demands isolated tests.
- Treat `** BUILD SUCCEEDED **` as success.

## Architecture

MVVM + `@Observable` singletons. UI/services live in the app target (`SwiftNZB/`); all NNTP +
decode + PAR2 specifics are isolated in the two local packages and surfaced to the UI through
the `DownloadManager` facade (the app's seam). Views/VMs use only the plain `Types/`.

```
project.yml                 XcodeGen config (2 targets: SwiftNZB, SwiftNZBWidgets)
Localizable.xcstrings        String catalog (auto-extracted; en + de) — don't hand-edit
fastlane/{Fastfile,Appfile,Matchfile}
Packages/DownloadEngine/     NNTP transport, yEnc, CRC32, scheduler, pool, assembler, checkpoint
Packages/PAR2Kit/            Clean-room PAR2 parse / verify / Reed-Solomon repair (no GPL)
Packages/NewznabKit/         Newznab indexer API: URL building, RSS/error parsing, NZB validation
SwiftNZB/
  Types/                     Plain Codable models (no logic); DownloadActivityAttributes is shared
  Services/                  @Observable @MainActor singletons (DownloadManager, ServerStore, …)
  ViewModels/                One @Observable VM per screen
  Views/                     Screens + Views/Components/ (reusable)
  Intents/                   App Intents: DownloadIntents (shared into widget), QueueIntents
                             (app-only: Siri/Shortcuts actions + AppShortcutsProvider)
SwiftNZBWidgets/             Live Activity (WidgetKit)
```

### Download engine (CRITICAL — read before touching networking)

- iOS **cannot** background raw-socket (NNTP) downloads — `URLSession` background mode is
  HTTP-only; `NWConnection` sockets suspend when the app backgrounds. Large downloads need the
  app foregrounded. Background support is best-effort: `beginBackgroundTask` wind-down +
  `BGProcessingTask` opportunistic resume, with checkpoint/resume making it safe.
- Concurrency: a fixed pool of `maxConnections` long-lived workers in one `withTaskGroup`,
  each owning one authenticated `NNTPConnection` actor, pulling `WorkItem`s from a shared
  `SegmentScheduler` actor. Reuses the auth handshake; structured cancellation.
- Assembly streams to disk: positional `FileHandle` writes into one sparse `.part` file per
  NZB file using each segment's `=ypart` byte offset. The scratch file IS the output; finalize
  renames. Idempotent → resume-safe.
- **Mobile network resilience is first-class**: `NWPathMonitor` parks/resumes on
  connectivity changes; per-request stall timeouts kill half-open cellular sockets; per-segment
  exponential backoff + jitter; adaptive active-connection count under degraded links; smoothed
  throughput/ETA. The segment is the atomic, idempotent, resumable unit — a flaky link degrades
  throughput but never corrupts state.

### PAR2 (CRITICAL — App Store licensing)

- PAR2 verify+repair is a **clean-room Swift implementation** in `Packages/PAR2Kit`. Do **not**
  introduce `par2cmdline`/`libpar2` or any GPL code — GPL is incompatible with App Store
  distribution. UnRAR (via the `Unrar.swift` SPM dependency) IS acceptable for the App Store.

### Indexer search

- Settings → Indexers holds Newznab indexers (NZBGeek, or NZBHydra2/Prowlarr via their Newznab
  endpoint); the API key is in the Keychain (`Keychain.indexerAPIKeyService`). The Search tab
  queries every enabled indexer in parallel through `IndexerSearchService`; one failing indexer
  is listed, never hides the others' results.
- Per-indexer **custom headers** (`IndexerHeader`) go on every request — search, test and the .nzb
  fetch — and override the default `User-Agent`. Stored as JSON in the Keychain
  (`Keychain.indexerHeadersService`) because values are often credentials. Names are validated as
  HTTP tokens, values reject CR/LF (checked per scalar: Swift's `"\r\n"` is one Character).
- The indexer **list syncs via iCloud KVS** (`indexers.v1`, mirrored to UserDefaults), like
  `ServerStore`; keys/headers sync via the synchronizable Keychain and may land a moment later.
  1.2.0 stored the list in UserDefaults only, so `mergeLocalIndexersOnce()` adds each device's
  local indexers once, after iCloud has delivered its copy (not before, or the whole-blob
  last-writer-wins store would drop the other device's list).
- **HTTPS only.** The API key rides in every query string, so `NewznabRequest.baseURL(from:)`
  refuses `http://` (a bare host gets `https://`). No ATS exception exists or is needed.
- Download = fetch the result's `t=get` link, check it is an NZB (`NZBValidation` — indexers send
  an `<error>` or HTML on grab limits), write it to a temp file, then
  `ImportCoordinator.handle(url:)`, the same path as a shared file. Don't add a second import path.
- **Redirects are followed only within the same host over HTTPS** (`SameHostRedirects`):
  URLSession would otherwise carry custom headers and the API-key query to the redirect target.
  Exception, for the .nzb download only: an HTTPS redirect to another host is followed as a bare
  request (User-Agent only). Prowlarr's `/{id}/download` does this for indexers with its
  "Redirect" option on, handing off to e.g. `api.nzbgeek.info` with that indexer's key in the URL.
  A refused redirect to `*.cloudflareaccess.com` maps to `.cloudflareAccess` (missing/invalid
  `CF-Access-Client-Id`/`-Secret` service token); empty 401/403 maps to `.unauthorized`.
- Two indexer kinds (`IndexerKind`): `.newznab` (a Newznab endpoint, incl. one Prowlarr indexer's
  `/<id>/api` feed) and `.prowlarr` (`ProwlarrClient`: Prowlarr's v1 API, `GET /api/v1/search`,
  key in `X-Api-Key`, one entry searches all Prowlarr indexers; torrent results are dropped). Test
  Connection for Prowlarr is `GET /api/v1/indexer`. Prowlarr's root `/api` is not Newznab.
- A Newznab-type entry pointed at Prowlarr's root gets `{"current":"v1",…}` from `/api`;
  `NewznabParser` reports `.prowlarrRoot` and Test Connection switches the type to Prowlarr.
- Header UX follows Ruddarr/LunaSea: rows + editor, **Add Basic Authentication** (builds
  `Authorization: Basic …`), and a `PasteButton` taking `Name: Value` lines
  (`NewznabRequest.parseHeaderLines`, split at the first colon; same name replaces the value).
- Prowlarr behind a TLS proxy builds `http://` links on its own host; `NewznabClient.secured` upgrades
  same-host `http` to `https` and refuses plain HTTP to any other host.
- Indexer requests use `NewznabClient.defaultSession`: **no cookies, no cache.** Cloudflare Access
  sets `CF_Authorization` on the first authorized request; a cookie jar would let later requests
  through without the service-token headers, so a revoked token would seem to keep working.
- An indexer's **website** address answers `/api` with an HTML login page (`nzbgeek.info` vs
  `api.nzbgeek.info`); `NewznabParser` reports that as `.webPage` with the fix, and any other
  unparseable body as `.unexpectedResponse(excerpt:)` quoting how it began.
- Indexers disagree on error codes (NZBGeek: 101 "Invalid API Key"), so show the indexer's own
  `description`; the code mapping is only a fallback.
- Not for the App Store: the review notes in `fastlane/metadata` and `docs/AppStoreReview.md`
  argue "no search in the app", which this feature contradicts.

### No purchases

- The app is **free for everyone**: no in-app purchases, no StoreKit, no paywall, no download limit.
  The Pro tier (`PurchaseStore`, `Entitlements`, `PaywallView`, `Packages/PurchasePolicy`,
  `SwiftNZB.storekit`) was removed; `ImportCoordinator.handle(url:)` imports unconditionally.
  Don't reintroduce a gate without also restoring the App Store metadata and privacy page texts.

## Conventions (carried from iobs)

- One `@Observable` view model per screen, created `@State private var viewModel = …()`.
  Services are `static let shared` singletons, mostly `@MainActor`.
- User-facing strings use `String(localized:)` / `LocalizedStringKey`; `Localizable.xcstrings`
  is auto-extracted at build — don't hand-edit it.
- **Numbers in SwiftUI `Text("\(int)")` get a locale thousands separator.** For ports, byte
  counts, speeds, connection counts, IDs use `Text(verbatim:)`.
- `.glassProminent` adds its own padding — size icon controls with a fixed tinted circle
  (`CircleActionButton`), not frame+padding alone.
- Adding a field to any Codable model / payload → use `decodeIfPresent` defaults
  (migration + cross-version safety).
- `@Observable` + a `didSet` on a stored property is safe: the macro moves the observer onto the
  private backing store and still emits the observation accessors (verified via
  `-dump-macro-expansions`). `DownloadManager.activeJobID` relies on this.
- **Downloads only progress in the foreground**, so `DownloadManager.refreshIdleTimer()` holds
  `isIdleTimerDisabled` while a job is active (auto-lock would background the app and suspend the
  sockets). It is driven by `activeJobID`'s `didSet` — don't set `activeJobID` behind its back.
- Dropping a job from history must go through `DownloadManager.forget(where:)`: a failed job keeps
  its partial `.part` files for resume, so removing the record without the working directory
  strands those bytes where no screen can reach them.
- Files added under a target's source path are picked up on the next `xcodegen generate`. Files
  shared across targets are listed explicitly in `project.yml` (currently
  `DownloadActivityAttributes.swift`; `DownloadIntents.swift` will join it).
- The Live Activity's `DownloadActivityAttributes` is shared into the widget and **must stay
  dependency-free**. The Live Activity intent file gates its `DownloadManager` calls behind the
  **`SWIFTNZB_APP`** compilation condition (set only on the app target).

## Provisioning (device / TestFlight)

- Code signing uses Fastlane **match** for both bundle IDs. One-time: `bundle exec fastlane
  register_ids` (creates the App IDs incl. widget), then `match development` / `match appstore`.
- **Appfile `app_identifier` must stay a single String** (`upload_to_testflight`/`produce`
  require it). The list of both bundle IDs for **match** lives in the **Matchfile**.
- The **Gemfile** must declare `multi_json` (and `abbrev`) — Bundler 4 / Ruby 3.3+ won't
  auto-load these transitive fastlane deps. No `Gemfile.lock` committed.
- **Build numbers** are a timestamp set per upload by the `update_build_number` lane, which runs
  `agvtool new-version -all` — that writes CFBundleVersion into the Info.plists *and*
  CURRENT_PROJECT_VERSION. Both plists reference `$(CURRENT_PROJECT_VERSION)` and `project.yml`
  sets `VERSIONING_SYSTEM: apple-generic`, so a build made without fastlane (Xcode, or a local
  `xcodebuild`) gets the same number the project setting carries instead of a stale literal.
- iPad **must** declare all four orientations (`…~ipad` incl. `PortraitUpsideDown`) or
  `upload_to_testflight` validation fails (409). iPhone keeps three.
- **iCloud KVS capability** must be enabled on the App ID (entitlement
  `com.apple.developer.ubiquity-kvstore-identifier`) or server/settings sync degrades to
  local-only (no crash).
- **App Transport Security**: the app declares **no** ATS exception. ATS governs only the URL
  Loading System (URLSession/CFNetwork); all Usenet traffic uses `NWConnection`
  (Network.framework), which ATS does not police — so plain NNTP / self-signed TLS already work
  without `NSAllowsArbitraryLoads`. Omitting a global exception avoids unnecessary review
  scrutiny. Re-add a *scoped* exception only if HTTP URL loading (e.g. NZB-by-URL) is introduced.
- **App Store review notes**: the app bundles no indexers or content — bring-your-own server +
  NZB. PAR2/unrar are generic file utilities. NZB/Usenet apps draw heightened scrutiny; keep the
  framing as a generic NNTP protocol client (see `docs/AppStoreReview.md` for the full strategy,
  demo-account/demo-NZB plan, and rejection playbook, plus listing texts in `fastlane/metadata/`).
- **Privacy manifests**: both targets ship a `PrivacyInfo.xcprivacy` (app: UserDefaults CA92.1,
  file timestamps C617.1, disk space E174.1; widget: none). Data-not-collected, no tracking.

## Gotchas recap

- Edit `project.yml`, not the xcodeproj. Regenerate after file changes.
- Don't add GPL code (no par2cmdline) — App Store + clean-room PAR2 is intentional.
- Local-package SOURCES under `Packages/` are committed; `.gitignore` deliberately does NOT
  ignore `Packages/` (only `.build/`, `.swiftpm/`, `Package.resolved`).
- App icon is `AppIcon.icon` (Icon Composer) at the repo root, referenced as a resource in
  `project.yml` with `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` +
  `ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS: YES` (as iobs does). Don't add an
  `AppIcon.appiconset` alongside it — two "AppIcon" sources conflict, and a set referencing a
  missing file crashes `actool`. A missing/empty icon also fails TestFlight upload with a 409
  (missing 120/152px icons + `CFBundleIconName`).
