# AGENTS.md

## Role

This repository is an **intent-cli child-implementation repo** (`role = "child-implementation"`,
see `host-binding.toml`). It is the target of implementation work, not a design host.

- Domain: `jubako`
- Target repo: `snaka/jubako`
- Base branch policy: `direct-main` (child PRs target `main`)

## Invariants

- This repo MUST NOT contain a `.intent-cli/` directory (G300 / G333). Its absence is the
  expected steady state and must not, by itself, abort a workflow (G305).
- The child loop is **GitHub-contract-only**: it reads issues, PRs, comments, labels, and files
  in this repo. It MUST NOT read or mutate parent host state (queue-state, runs.jsonl, packets,
  intent metadata). Host metadata reconciliation is owned by the host / review-runtime loop.
- Never apply `intent-target` here; it is host-owned.
- All workflow label transitions go through `intent-cli automation` / `intent-cli worker`.
  No raw `gh ... --add-label` / `--remove-label` fallback.

## Where guidance comes from

Read workflow guidance from the installed CLI, never from copied prompt files or local
runbooks. Installed guidance wins over any repository-local rule doc (G473).

```bash
intent-cli guide worker --format json          # child worker surface
intent-cli guide model --format json           # chat-first collaboration model
intent-cli guide onboarding --format json      # first-call sequence for a fresh agent
intent-cli guide commands list --format json   # primary / support / advanced classification
intent-cli automation doctor --format json     # verify the installed CLI before mutating
```

## Loop body

Canonical wake body, run from this worktree:

```bash
intent-cli worker next-action --repo snaka/jubako --github-only --format json
```

Dispatch on `action` (`none` → idle, `issue-to-pr`, `pr-comment-fix`), then
`worker claim` → `worker result-summary` → `worker complete`. Process at most one action
per wake. Ask `intent-cli guide workflow task implementation-loop` for the current
paste-ready loop prompt rather than relying on this file for the details.

## Project build

Jubako's own build and architecture notes live in [CLAUDE.md](CLAUDE.md) and
[DESIGN.md](DESIGN.md). This file covers the intent-cli role binding only.
