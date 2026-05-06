# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this is

Jubako is a macOS-native OSS disk analyzer. Read **[DESIGN.md](DESIGN.md)** first — it has the architecture, scanner data model, categorization rules, "safe to delete" scoring, and phased roadmap. Don't duplicate that content here.

## Project state

Early scaffolding. No real app logic yet — `ContentView.swift` is a placeholder. The next concrete work is in the Phase 1 checklist of `DESIGN.md`.

## Build & dev commands

The Xcode project is **generated from `project.yml`** by [XcodeGen](https://github.com/yonaskolb/XcodeGen) and is gitignored. After editing `project.yml`, regenerate before building.

```bash
xcodegen generate                    # produces Jubako.xcodeproj
open Jubako.xcodeproj                # work in Xcode
xcodebuild -project Jubako.xcodeproj -scheme Jubako -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
```

When adding source files, place them under `Sources/` — XcodeGen picks them up automatically; no need to edit `project.yml`.

## Layout

```
project.yml                 # XcodeGen project definition (source of truth)
Sources/                    # all Swift code + Info.plist + entitlements
Resources/                  # assets, JSON rule files (categories.json future)
DESIGN.md                   # architecture / spec
```

## Key conventions

- **macOS 14 (Sonoma) minimum.** Don't add fallbacks for earlier versions.
- **Not sandboxed in v1.** Whole-disk scanning needs Full Disk Access; sandbox makes this impractical. Revisit only if Mac App Store distribution becomes a goal (currently not planned).
- **No telemetry in v1.** Don't add analytics, crash reporters, or network calls without an explicit decision.
- **English in code and comments.** Localization (Japanese) is Phase 3.
- **Default to no comments** — `DESIGN.md` is the place for rationale; code should explain itself.

## Distribution pipeline

- Releases come from CI (not yet built — Phase 1 task).
- Notarized `.dmg` → GitHub Releases on `snaka/jubako`.
- Cask formula in **`snaka/homebrew-jubako`** tap (separate repo at `~/ghq/github.com/snaka/homebrew-jubako`); CI bumps it via PR after each release.
- Apple Developer Program is enrolled — Developer ID signing + `notarytool` is the path.

## Gotchas

- After `xcodegen generate`, `Sources/Info.plist` and `Sources/Jubako.entitlements` get **populated** from `project.yml`. Don't hand-edit them — edit `project.yml` instead and regenerate.
- The `*.xcodeproj/` glob in `.gitignore` is intentional. Never `git add` the generated project.
- `fts(3)` (planned for the scanner) needs careful UTF-8 path handling on macOS — paths come as `char *` and must round-trip through `String(cString:)` safely.
