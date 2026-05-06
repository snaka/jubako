# Jubako

A macOS-native, open-source disk analyzer with a Bento-grid UI.

> **Status: early design / scaffolding.** No usable build yet.

## What is it?

Jubako helps everyday Mac users find and clean up large or unused files.
Three things make it different from existing tools:

1. **Bento grid + drilldown** — a modern, scannable card layout, not a dense treemap.
2. **Time-axis heatmap** — surfaces stale files (the 50 GB folder you haven't touched in 3 years).
3. **Auto-categorization** — groups dev caches (DerivedData, `node_modules`, Docker, iOS Simulator, browser caches) so the real disk hogs are obvious.

See [DESIGN.md](DESIGN.md) for the full design.

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon or Intel

## Building from source

```bash
brew install xcodegen
git clone https://github.com/snaka/jubako.git
cd jubako
xcodegen generate
open Jubako.xcodeproj
```

## Installation (planned)

Once the first release ships:

```bash
brew install --cask snaka/jubako/jubako
```

## License

MIT — see [LICENSE](LICENSE).
