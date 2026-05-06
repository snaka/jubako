# Jubako

A macOS-native, open-source disk analyzer with a folder-drilldown UI.

> **Status: v0.1.0 — early but usable.**
> The scanner, drilldown, and persistence are working. The Bento grid,
> staleness heatmap, and category auto-classification described in
> [DESIGN.md](DESIGN.md) are upcoming.

## What's in v0.1.0

- **Parallel scanner** — pulls subtrees off a controller and walks them with
  `fts(3)` in two workers concurrently. Around 3 minutes for a 700 GB / 6.5M-file
  home directory on Apple Silicon.
- **Folder drilldown** — sorted-by-size list with breadcrumb navigation,
  back button, and per-folder totals.
- **Permission handling** — paths blocked by macOS TCC are routed to a
  separate "deferred" queue with a banner that deep-links to System
  Settings → Privacy → Full Disk Access and a one-click retry.
- **Snapshot persistence** — results are saved to a custom binary format at
  `~/Library/Application Support/Jubako/snapshot.bin` and restored on the
  next launch (typical save/load are a few seconds). Granting Full Disk
  Access usually requires an app relaunch; previous results stay around
  so the retry is fast.
- **Notarized release** — signed with Developer ID, notarized, and stapled.
  Distributed as a `.dmg` via [`snaka/homebrew-tap`](https://github.com/snaka/homebrew-tap).

## Not yet

- First-launch onboarding for Full Disk Access
- Bento-grid layout
- Time-axis staleness heatmap
- Category auto-classification (DerivedData, `node_modules`, Docker, etc.)
- Differential scan / duplicate detection

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

## License

MIT — see [LICENSE](LICENSE).
