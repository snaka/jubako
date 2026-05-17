# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this is

Jubako is a macOS-native OSS disk analyzer. **v0.3.0 ships today**, distributed as a notarized DMG via `brew install --cask snaka/tap/jubako`.

Read **[DESIGN.md](DESIGN.md)** for the original design and roadmap. The bullet list in [README.md](README.md) "What's in v0.3.0" reflects what's currently shipping.

## Build & dev commands

The Xcode project is **generated from `project.yml`** by [XcodeGen](https://github.com/yonaskolb/XcodeGen) and is gitignored. After editing `project.yml` (or pulling), regenerate before building.

```bash
xcodegen generate
open Jubako.xcodeproj
xcodebuild -project Jubako.xcodeproj -scheme Jubako -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
```

To regenerate the app icon after editing the renderer:

```bash
swift Tools/generate-icon.swift
```

## Layout

```
project.yml                              # XcodeGen project definition (source of truth)
Sources/                                 # all Swift code + Info.plist + entitlements
  JubakoApp.swift                        # @main + AppDelegate (delays ⌘Q while a save is in flight) + Help menu
  ContentView.swift                      # top-level View; phase machine, ScanMode enum, onboarding wiring
  OnboardingView.swift                   # first-launch FDA explainer
  FDAProbe.swift                         # has-access detection by listing TCC-protected paths
  HelpView.swift                         # in-app help sheet (⌘? / ? button on disk usage bar)
  BentoGridView.swift                    # 1+3+4+4 layout, BentoCard, BentoListRow, context-menu rescan
  Categorizer.swift                      # FileCategory enum + classify() + tints/icons
  AppResolver.swift                      # ~/Library path → owning macOS app via LaunchServices (cached)
  AppPill.swift                          # icon + name capsule rendered on cards for resolved apps
  VolumeUsage.swift                      # filesystem capacity/free-space lookup
  DiskUsageBar.swift                     # 3-segment Scanned/Other/Free Capsule bar with ? help button
  Scanner/DiskScanner.swift              # ScanController actor + 2-worker fts walker
  Persistence/SnapshotStore.swift        # save/load + prune + AppDelegate hook
  Persistence/BinarySnapshot.swift       # custom little-endian binary format
Resources/Assets.xcassets/AppIcon.appiconset/  # generated PNG set
Tools/generate-icon.swift                # icon renderer (CGContext + NSBitmapImageRep)
DESIGN.md                                # architecture / spec
RELEASE.md                               # operator runbook for cutting a release
```

## Key architecture decisions

- **fts(3) via direct `import Darwin`**, no bridging header. The walker is split across a `ScanController` actor and two `Task`-based workers; pre-walk seeds the queue at depth=2 so neither worker gets stuck on `~/Library`.
- **AsyncStream emits per-file `.file` events directly from workers** (the continuation is thread-safe, so we avoid a hot-path actor hop). Workers report progress in batches of 500 files to the controller, which emits the user-visible `.progress` events.
- **Snapshot is a custom little-endian binary format**, not plist or JSON. PropertyListEncoder boxes every value and was 30–60× slower at 1M+ entry scale. See `BinarySnapshot.swift`.
- **AppDelegate gates ⌘Q on `SnapshotStore.hasPendingSave`** so a fresh scan's snapshot isn't truncated by quit.
- **TCC-protected user-Library subpaths are pre-skipped** by the scanner (`tccProtectedHomeSubpaths`) and surfaced via `.deferred` events. The retry path uses `scan(roots:)` with the base skip list.
- **Categorizer is pure-function string work**, computed lazily via `ScanEntry.category`. No scan-time cost; called only for currently-rendered cells.
- **Snapshot is pruned before persisting**: keep all directories, drop files < 1 MB, cap each parent at 100 files. Cuts size by ~10× on a typical home.
- **`runScan(mode:)` is the single scan entry point**, with three modes: `.fullScan(root:)`, `.deferredRetry(roots:)`, and `.subtreeReplace(target:)`. Subtree replace prunes the target's keys from `byParent` on a local copy then assigns once — never mutate `@State` collections in a loop, the SwiftUI transaction per setter call CoW-copies the whole Dictionary and froze main for minutes on a home-sized snapshot (`sample`-confirmed).
- **Saving banner is set before `synthesizeShallowDirs`**, not after the `byParent` assignment, so the post-scan window has continuous visible progress (savingPhase: `finalizing` → `saving`).
- **App ownership** for `~/Library` paths comes from `AppResolver`, a `@MainActor` cache keyed on the extracted identifier (bundle-id or app name). Cards render an `AppPill` only when a match is found; unknown folders stay unlabelled.
- **Disk usage bar** clamps `scannedBytes` to `volume.usedBytes` so APFS hard links / clones / snapshots can't make the orange segment overflow the used region.
- **`.help()` is unreliable on macOS in nested SwiftUI layouts.** Tried it, tried wrapping `NSView.toolTip` via `NSViewRepresentable`, neither fired. The convention now is an explicit Help sheet reachable via the `?` button + ⌘? menu command.

## Conventions

- macOS 14 (Sonoma) minimum. Don't add fallbacks for earlier versions.
- Not sandboxed in v1 — whole-disk scanning needs Full Disk Access; sandbox makes this impractical. Mac App Store distribution is not a goal.
- No telemetry. Don't add analytics, crash reporters, or network calls without an explicit decision.
- English in code and comments. Localization (Japanese) is a Phase 3 task.
- Default to no comments — `DESIGN.md` is the place for rationale; code should explain itself.
- Heavy work goes off MainActor. Per-file work must not hop actors.

## CI

Two GitHub Actions workflows:

- `.github/workflows/build.yml` — runs on PRs and pushes to `main`; unsigned compile-only check.
- `.github/workflows/release.yml` — runs on `v*` tag push (real release) or manual `workflow_dispatch` (dry-run that uploads the DMG as an artifact only and skips Release + tap bump). Full sign / notarize / staple / dmg pipeline.

The release flow signs with Developer ID, notarizes via `notarytool`, builds a `.dmg`, creates a GitHub Release, and pushes an updated `Casks/jubako.rb` to **`snaka/homebrew-tap`** (renamed from `homebrew-jubako` mid-development; redirect is live). See **[RELEASE.md](RELEASE.md)** for the secrets list and the operator runbook.

## Gotchas

- After `xcodegen generate`, `Sources/Info.plist` and `Sources/Jubako.entitlements` get **populated** from `project.yml`. Don't hand-edit them — edit `project.yml` instead and regenerate.
- The `*.xcodeproj/` glob in `.gitignore` is intentional. Never `git add` the generated project.
- **`Resources/Assets.xcassets` belongs under `sources:` in `project.yml`, not `resources:`.** XcodeGen silently ignores asset catalogs under `resources:` — verified the hard way.
- DMG is stapled but not separately codesigned. The inner `.app` is `Notarized Developer ID`-signed and that is what matters for Gatekeeper / Cask installs.
- `fts(3)` paths come back as `char *`. Always round-trip through `String(cString:)`; don't try to keep the raw pointer alive past the next `fts_read`.
- `SnapshotStore.url` is in user `Library/Application Support/Jubako/`; don't confuse with the `Library/` paths the scanner traverses.
