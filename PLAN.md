# RocksDB Viewer macOS Implementation Plan

This plan is anchored to `spec/SPEC.md` and must be reread with the spec after any context compaction or before any subagent starts work.

## Constraints From SPEC.md

- Build a native Swift macOS app with a minimal footprint, macOS 14 minimum and macOS 15 optimized (`SPEC.md` sections 1, 3, 12).
- Use SwiftUI for primary UI, AppKit only for file panels and desktop behaviors (`SPEC.md` sections 3, 7.2, 8).
- Access RocksDB through a narrow owned bridge; SwiftUI must not hold raw RocksDB pointers (`SPEC.md` sections 3, 7.1, 18.1).
- Keep memory bounded: stream rows in batches, retain only a limited row window, preview values at 4 KiB by default, never load all keys or values into Swift arrays (`SPEC.md` sections 2, 3, 6.3, 7.3, 12).
- Implement MVP workflows: open/recent history, column family selection, comparators, browse, exact/prefix/range/reverse scan, add/edit/delete, snapshots, backup, restore, progress/cancel (`SPEC.md` sections 5.1, 9, 11, 19).
- UI should be a dense macOS utility, not a landing page (`SPEC.md` section 8).

## Branch Phases

Each phase gets its own branch so milestones can be reviewed independently. Branches are cumulative unless noted.

### Phase 0: Plan

- Branch: `codex/phase-0-plan`
- Deliverable: `PLAN.md`
- Acceptance:
  - Plan references the spec sections that drive architecture and product behavior.
  - Plan lists branch names and acceptance criteria for incremental milestones.

### Phase 1: SwiftPM App Skeleton

- Branch: `codex/phase-1-swiftpm-shell`
- Deliverables:
  - `Package.swift`
  - SwiftUI app entry point and main window shell.
  - Core model types matching `SPEC.md` section 6.
  - Minimal AppShell layout: sidebar, toolbar, browser table, inspector, search panel, snapshots/backups panel, operation log/settings placeholders.
- Acceptance:
  - `swift build` succeeds.
  - App can launch with `swift run RocksDBViewer`.
  - Fresh UI starts without opening RocksDB automatically, matching `SPEC.md` section 12.1.

### Phase 2: RocksDB Bridge and Session Core

- Branch: `codex/phase-2-rocksdb-bridge`
- Deliverables:
  - Narrow Objective-C++ bridge linked to local RocksDB.
  - `DatabaseSession` actor that owns the bridge handle.
  - Column family discovery/open, close lifecycle, read-only/read-write modes.
  - Swift-friendly error mapping.
- Acceptance:
  - `swift build` succeeds.
  - Unit tests open the included `jazz.rocksdb` database read-only if available.
  - Swift types never expose raw RocksDB pointers to UI code.

### Phase 3: Streaming Browser and Search

- Branch: `codex/phase-3-scan-browser`
- Deliverables:
  - `ScanEngine` with exact lookup, prefix scan, bounded range scan, forward and reverse direction.
  - Bounded row retention and 4 KiB preview limit.
  - Browser table and inspector wired to live scan results.
  - Cancellation for active scans.
- Acceptance:
  - `swift test` covers byte decoding, previews, exact lookup, and bounded scan behavior.
  - UI requests rows in batches and caps retained rows at 2,000 by default.
  - Cancelling a scan releases iterator work promptly.

### Phase 4: Open Flow, History, and Comparators

- Branch: `codex/phase-4-open-history-comparators`
- Deliverables:
  - Open database sheet with path picker, recent list, open mode, create-if-missing toggle, column family discovery, comparator selection.
  - `HistoryStore` in Application Support using Codable JSON.
  - `ComparatorRegistry` with built-in bytewise, reverse bytewise, fixed-width signed integer, fixed-width unsigned integer, and UTF-8 lexical profiles.
  - Custom comparator bundle validation UI scaffold with explicit unsupported/validation messaging where bridge integration is limited.
- Acceptance:
  - Successful open updates history metadata only.
  - Failed open does not create history.
  - Comparator profile identity is persisted with recent database metadata.

### Phase 5: Writes and Safety Dialogs

- Branch: `codex/phase-5-writes-safety`
- Deliverables:
  - Add/edit/delete sheet with UTF-8, hex, JSON, and raw byte views.
  - Write path through bridge: put, delete, and atomic key change via write batch.
  - Read-only and snapshot views disable write controls.
  - Delete and unsaved-edit confirmations.
- Acceptance:
  - `swift test` covers encoding validation and write guards.
  - Save failure leaves UI state unchanged.
  - Destructive actions require confirmation.

### Phase 6: Snapshots, Backup, Restore, and Polish

- Branch: `codex/phase-6-snapshots-backups-polish`
- Deliverables:
  - Snapshot create/release and snapshot selector.
  - Backup creation and restore to selected destination with progress/cancel UI.
  - Restore-over-open-database guard.
  - Keyboard shortcuts from `SPEC.md` section 17.
  - Accessibility labels for primary controls.
  - Focused perf harness commands for open/get/scan.
- Acceptance:
  - `swift build` and `swift test` pass.
  - Manual app run can open `jazz.rocksdb`, browse rows, run searches, create/release snapshots, and show backup/restore operations.
  - MVP release checklist from `SPEC.md` section 19 is implemented or has a clearly documented local limitation.

## Implementation Notes

- Prefer SwiftPM commands for build and tests: `swift build`, `swift test`, and `swift run RocksDBViewer`.
- Link RocksDB from Homebrew when present at `/opt/homebrew/opt/rocksdb`; keep the bridge small and isolated so linking flags are easy to adjust.
- Keep UI row state bounded: default scan batch size 256, retained row cap 2,000, preview byte limit 4 KiB.
- Do not cache key or value contents in history or settings.
- Use `jazz.rocksdb` only as a local fixture for read-only smoke testing.
