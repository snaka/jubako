# Jubako — Design Document

> macOS-native OSS disk analyzer with a Bento-grid UI.
> Status: design draft — no code yet.

## 1. Goal & Non-Goals

### Goal
Help everyday Mac users **find and clean up large/unused files** with a modern, intuitive UI. Not for forensic analysis — for *tidying up*.

### Non-Goals
- Full filesystem forensics (use GrandPerspective).
- Cloud / network drive deep integration (out of scope for v1).
- Windows / Linux ports.

## 2. Target User & Core Use Case

A Mac user who notices "disk is full" and wants to:
1. See *what* is taking the most space, fast.
2. Decide *which* are safe to delete (and which should not be touched).
3. Move them to Trash with one click.

The whole flow should take **under 60 seconds** from launch to first deletion on a typical machine.

## 3. Differentiation Pillars

| # | Pillar | Why it matters |
|---|--------|----------------|
| 1 | **Bento grid + drilldown** | Modern, scannable; better than dense treemaps for non-experts. |
| 2 | **Time-axis heatmap** | Shows *staleness* — a 50GB folder untouched for 3 years is the real win. |
| 3 | **Auto-categorization** | Surfaces dev caches (DerivedData, node_modules, Docker, Simulator) as a group — often the actual culprit. |

## 4. Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                       SwiftUI App (UI)                      │
│   BentoGridView · CategoryView · HeatmapOverlay · Detail    │
└──────────────────────────┬──────────────────────────────────┘
                           │ ObservableObject (Combine/Async)
┌──────────────────────────▼──────────────────────────────────┐
│                       AppModel / Store                      │
│         scan state · selection · sort · filters             │
└──────────────────────────┬──────────────────────────────────┘
                           │
        ┌──────────────────┼─────────────────────┐
        ▼                  ▼                     ▼
┌──────────────┐   ┌─────────────────┐   ┌──────────────────┐
│   Scanner    │   │  Categorizer    │   │  PersistenceDB   │
│  (fts(3))    │   │   (rules)       │   │   (GRDB/SQLite)  │
└──────────────┘   └─────────────────┘   └──────────────────┘
```

### Layers

- **UI**: SwiftUI only. macOS 14+ to use the latest layout APIs.
- **AppModel**: single source of truth. Async streams from Scanner.
- **Scanner**: `fts(3)` wrapper in Swift, runs on background queue. Emits incremental results so the UI can populate before the scan finishes.
- **Categorizer**: pure function — given a path, returns a category enum. Rules are data-driven (see §6).
- **Persistence**: SQLite via GRDB. Stores last scan snapshot for diff (Phase 3) and avoids rescanning unchanged subtrees.

### Why GRDB over SwiftData
GRDB is mature, debuggable, and gives raw SQL when needed (e.g., "top N by size grouped by category"). SwiftData is great for app-state but less ergonomic for analytical queries.

## 5. Scanner Data Model

```swift
struct FileEntry {
    let path: String          // absolute
    let size: Int64           // bytes (allocated, not logical)
    let modifiedAt: Date      // mtime
    let accessedAt: Date      // atime (note: macOS may have noatime)
    let isDirectory: Bool
    let parentID: Int64?      // tree linkage in DB
    let category: Category?   // resolved by Categorizer
}

enum Category: String, CaseIterable {
    case devCache       // DerivedData, node_modules, target/, .gradle, ...
    case docker         // Docker Desktop disk images
    case simulator      // ~/Library/Developer/CoreSimulator
    case browserCache   // Chrome/Safari/Firefox caches
    case appCache       // ~/Library/Caches/*
    case downloads      // ~/Downloads
    case media          // photos/videos/audio
    case archive        // .zip .dmg .tar.*
    case userDocument   // unclassified user files
    case system         // /System, /Library — generally untouchable
}
```

### Sizing semantics
- Use `st_blocks * 512` for **on-disk size** (handles APFS clones / sparse files better than `st_size`).
- For directories: aggregate from children. Computed during scan, not on the fly.

### Scan algorithm
1. `fts_open` from selected root with `FTS_PHYSICAL` (don't follow symlinks).
2. Stream entries to a bounded buffer; flush to DB in batches of N (e.g., 5000).
3. Emit progress events: bytes scanned, files seen, current path.
4. After scan: compute aggregates (per-directory totals, per-category totals).

### Skip list (always)
- `/System`, `/private/var/vm` (swap), `/private/var/db/dyld_shared_cache_*`
- Bind mounts and other volumes (unless explicitly added)
- `.Spotlight-V100`, `.Trashes`, `.fseventsd`

## 6. Categorization Rules

Rules are matched in order; first match wins.

| Category | Match (path glob or basename) |
|----------|------|
| docker | `~/Library/Containers/com.docker.docker/Data/vms/**/Docker.raw` |
| simulator | `~/Library/Developer/CoreSimulator/Devices/**` |
| devCache | basename in {`DerivedData`, `node_modules`, `target`, `.gradle`, `.cargo`, `.next`, `.nuxt`, `dist`, `build`, `.venv`, `__pycache__`, `Pods`, `.bundle`} |
| browserCache | `~/Library/Caches/Google/Chrome/**`, `~/Library/Caches/com.apple.Safari/**`, `~/Library/Caches/Firefox/**` |
| appCache | `~/Library/Caches/**` (fallback after browserCache) |
| downloads | `~/Downloads/**` |
| media | extension in {`.jpg`, `.jpeg`, `.png`, `.heic`, `.mov`, `.mp4`, `.mkv`, `.mp3`, `.flac`, `.wav`} |
| archive | extension in {`.zip`, `.dmg`, `.tar`, `.tar.gz`, `.tgz`, `.7z`, `.rar`} |
| system | path under `/System` or `/Library` (and not user library) |
| userDocument | (default) |

Rules ship as a **JSON file in the bundle** so users can override via `~/Library/Application Support/Jubako/categories.json` (Phase 2 feature).

## 7. "Safe to Delete" Score

Composite score 0–100 per item. Higher = safer to delete.

```
score = w1 * stalenessScore(accessedAt)        // 0..40
      + w2 * regenerableScore(category)        // 0..40
      + w3 * sizeBoost(size)                   // 0..20  (favors big wins)
```

- `stalenessScore`: 0 if accessed today, 40 if > 1 year.
- `regenerableScore`: devCache=40, docker=35, simulator=35, appCache=30, browserCache=30, downloads=20, archive=10, media=0, userDocument=0, system=−∞ (never recommend).
- `sizeBoost`: log-scaled, capped.

UI bands: ≥70 green ("safe"), 40–69 yellow ("review"), <40 gray ("keep").

## 8. UI / Screen Flow

```
[Launch] → [Root picker]
              │ (Home / volume / custom path)
              ▼
        [Scan in progress]   ← incremental Bento grid populates as scan runs
              │
              ▼
        [Bento grid: top 12 cards]   ← main screen
          │     │      │
          │     │      └─ tap card → drill into directory (push, breadcrumb)
          │     └─ toggle: by Size / by Staleness / by Category
          └─ "Categories" tab: docker, devCache, ... aggregated view
              │
              ▼
        [Detail / preview / Move to Trash]
```

### Bento grid spec
- Hero card (largest): top item, ~40% of grid area.
- Secondary (next 3): ~20% each.
- Tail (next 8): small uniform.
- Card content: name, size, last-accessed badge, category pill, mini sparkline if subtree.
- Background tint = staleness heatmap (white→amber→red).

### Empty/edge states
- No Full Disk Access → guide screen with deep link to System Settings.
- Scan canceled / errored → retry from last batch.
- Result < N items → show fewer cards (don't pad).

## 9. Permissions

- **Full Disk Access** (`com.apple.security.app-sandbox` off, or Hardened Runtime + entitlement). Required to read `~/Library/*` etc.
- App is **not sandboxed** in v1 (sandbox makes whole-disk scan painful). Will revisit if Mac App Store distribution is ever pursued — currently not planned.

## 10. Distribution

- **Repo**: `github.com/snaka/jubako` (this repo).
- **Tap**: `github.com/snaka/homebrew-jubako`.
- **CI** (GitHub Actions):
  1. `xcodebuild archive`
  2. `codesign` with Developer ID (cert + key from secrets, p12 base64).
  3. `notarytool submit --wait`.
  4. `stapler staple`.
  5. Create `.dmg` (or zip), upload to GitHub Release.
  6. Open PR to `homebrew-jubako` bumping version + sha256.
- **Public install**: `brew install --cask snaka/jubako/jubako` (after first release).
- **Apple Developer Program**: enrolled (2026-05-06).

## 11. Phased Roadmap

### Phase 1 — MVP (target: working end-to-end)
- [ ] Xcode project skeleton (SwiftUI App, macOS 14+).
- [ ] Scanner (fts-based) with incremental events.
- [ ] AppModel + persistence layer (GRDB schema).
- [ ] Root picker + Full Disk Access onboarding.
- [ ] Bento grid (size mode only) + drilldown + breadcrumbs.
- [ ] Move-to-Trash action.
- [ ] CI: build + sign + notarize + Release + tap bump.

### Phase 2 — Differentiation
- [ ] Categorizer + Categories tab.
- [ ] Time-axis heatmap overlay (staleness).
- [ ] Safe-to-delete score + recommendation banner.
- [ ] User-overridable category rules.

### Phase 3 — Polish & advanced
- [ ] Differential scan ("what grew since last week").
- [ ] Duplicate file detection.
- [ ] Localization (ja first, en second).
- [ ] Submit to official `homebrew/cask`.

## 12. Open Questions

1. **macOS minimum version** — 14 vs 13. SwiftUI Bento-style layouts are easier on 14+.
2. **Animation library** — pure SwiftUI vs Lottie for the Bento transitions.
3. **Icon design** — top-down jubako (lacquered box) view; commission later, placeholder for now.
4. **Telemetry** — none in v1 (privacy-first). Crash reporting only via Sentry/standard `.crash` later.
5. **Localization timing** — ship en-only first, or ja/en day 1?
