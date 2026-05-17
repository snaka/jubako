<div align="center">
  <img src="Resources/Assets.xcassets/AppIcon.appiconset/icon_256.png" width="160" height="160" alt="Jubako icon">
  <h1>Jubako</h1>
  <p>A macOS-native, open-source disk analyzer with a Bento-grid UI.</p>
</div>

> **Status: v0.3.0 — early but usable.**
> Scanner, drilldown, persistence, Bento layout, category color-coding,
> Full Disk Access onboarding, per-folder rescan, disk capacity bar,
> and app-ownership badges are working. Time-axis staleness heatmap and
> differential scan from [DESIGN.md](DESIGN.md) are next.

## What's in v0.3.0

- **Per-folder rescan** — refresh a single subtree without re-walking
  the whole home. Right-click any Bento card or list row for
  "Rescan this folder"; right-click the breadcrumb for "Rescan current
  folder". Deleted files drop out of the snapshot in the same pass.
- **Disk capacity bar** — a three-segment Capsule under the banners
  shows Scanned (orange) / Other (gray) / Free (green) for the volume
  containing the scan root, alongside the volume name and total size.
- **App-ownership badges** — folders under `~/Library/Containers`,
  `Application Support`, `Caches`, `Preferences`, etc. that match
  Apple's standard layout are labelled with the macOS app that owns
  them (icon + display name resolved via LaunchServices). Folders
  outside the conventions stay unlabelled.
- **In-app Help** — a `?` button on the disk usage bar and the
  Help → "Jubako Help" menu (⌘?) open a sheet that documents every UI
  element introduced so far.
- **Consolidated rescan UI** — the primary button now switches between
  "Scan Home" / "Cancel" / "Rescan Home" by phase, and the
  near-duplicate Rescan buttons on the snapshot/breadcrumb banners are
  retired in favour of context menus.
- **Saving-banner timing fix** — the snapshot-save banner now appears
  the instant a scan finishes, so the post-scan "frozen" feel during
  finalize + write is gone.

## Carried over from v0.2.0

- **Bento grid layout** — top 12 entries per folder render as one hero
  card, three secondary, four medium, and four small. Items past 12
  fall into a compact "More" list. The name (重箱 — stacked lacquer
  boxes) and the layout finally line up.
- **Category color-coding** — paths are classified into a small set
  (`devCache`, `docker`, `simulator`, `browserCache`, `appCache`,
  `downloads`, `media`, `archive`, `system`, ...) and each card picks
  up a tint and icon from its category. Big `node_modules` and
  `.gradle` directories pop visually as orange dev caches.
- **First-launch onboarding** — new users without Full Disk Access see
  a guided welcome screen that deep-links to the Privacy & Security
  pane and provides a recheck button. Returning users with a saved
  snapshot skip it entirely.
- **App icon** — generated from `Tools/generate-icon.swift`; lacquer
  red background with gold Bento compartments.

## Carried over from v0.1.0

- **Parallel scanner** — controller actor + two workers running
  concurrent `fts(3)` walks. Around 3 minutes for a 700 GB / 6.5M-file
  home directory on Apple Silicon.
- **Folder drilldown** — breadcrumb navigation, back button, per-folder
  totals.
- **Permission handling** — TCC-blocked paths go to a deferred queue
  with a banner that deep-links to Full Disk Access and offers
  one-click retry.
- **Snapshot persistence** — custom binary format at
  `~/Library/Application Support/Jubako/snapshot.bin`. Save and load
  each take a few seconds even on a fully-populated home; ⌘Q waits
  for an in-flight save before terminating.
- **Notarized release** — signed with Developer ID, notarized, stapled,
  distributed as a `.dmg` via
  [`snaka/homebrew-tap`](https://github.com/snaka/homebrew-tap).

## Not yet

- Time-axis staleness heatmap
- "Safe to delete" score + recommendation banner
- Differential scan / duplicate detection
- Submission to the official `homebrew/cask`

See [DESIGN.md](DESIGN.md) for the full roadmap.

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon or Intel

## Installation

```bash
brew install --cask snaka/tap/jubako
```

(The release pipeline writes the formula to
[`snaka/homebrew-tap`](https://github.com/snaka/homebrew-tap); if `brew`
reports the cask is missing, the GitHub Action that publishes it may
still be running.)

## Building from source

```bash
brew install xcodegen
git clone https://github.com/snaka/jubako.git
cd jubako
xcodegen generate
open Jubako.xcodeproj
```

To regenerate the app icon after editing `Tools/generate-icon.swift`:

```bash
swift Tools/generate-icon.swift
```

## License

MIT — see [LICENSE](LICENSE).
