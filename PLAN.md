# Implementation Plan: Close SPEC.md Gaps

This plan replaces the archived phase plan at `docs/archive/PLAN.phase-0-through-6.md`.

Before continuing implementation after any compaction or delegation, read:

- `spec/SPEC.md`
- `docs/rocksdb/README.md`
- `docs/implementation-gap-audit.md`
- this `PLAN.md`

## Current State

The app can launch from `./scripts/run-app.sh`, open `jazz.rocksdb`, and display rows. Core RocksDB access exists, but several SPEC.md MVP items are still incomplete or only scaffolded.

Verification baseline:

```bash
swift test
./scripts/build-app.sh
ROCKSDB_VIEWER_OPEN_PATH=/Users/omarezzat/Workspace/rocksdb-macos/jazz.rocksdb ROCKSDB_VIEWER_DEBUG_ROWS=1 .build/arm64-apple-macosx/debug/RocksDBViewer
swift run rocksdb-viewer-bench scan jazz.rocksdb --limit 49
```

## Phase A: Open Flow Correctness

Branch: `codex/open-flow-completion`

Goals:

- Make `Create if missing` functional and pass it into `DatabaseOpenRequest`.
- Keep sheet-local selected column family synchronized after discovery.
- Reopen recent databases directly from recent rows.
- Show open/discovery validation errors in the open sheet.
- Add lock/read-write warning messaging.
- Persist backup directory per recent database.

Acceptance:

- Tests cover create-if-missing, failed open not added to history, and recent reopen.
- Manual app flow can open `jazz.rocksdb` from Browse and from Recent.

## Phase B: True Streaming And Preview Safety

Branch: `codex/streaming-preview-safety`

Goals:

- Replace array-returning scan bridge with callback/batch delivery into Swift.
- Emit UI batches as RocksDB iterates, not after the whole limit is scanned.
- Keep retained row cap independent from scan limit.
- Add a preview-only exact lookup path that does not copy full values.
- Implement `Load Full Value` with explicit size warning.
- Make reverse prefix bounds correct for arbitrary bytes or document unsupported byte patterns.

Acceptance:

- Test proves first batch is delivered before full scan completion.
- Test proves exact lookup of large values retains only preview bytes until full load.
- Cancel test proves scan stops promptly.

## Phase C: Comparator Implementation

Branch: `codex/comparator-bridge`

Goals:

- Implement C++ comparator adapters for built-ins:
  - Bytewise.
  - Reverse bytewise.
  - Fixed-width signed integer.
  - Fixed-width unsigned integer.
  - UTF-8 lexical.
- Pass selected comparator profile into RocksDB open options.
- Add comparator sample-ordering preview UI.
- Implement custom comparator bundle loading or explicitly narrow MVP to supported C ABI bundles with a clear loader.

Acceptance:

- Tests create/open fixture DBs for each built-in comparator.
- Opening with comparator profile changes scan ordering where expected.
- Custom comparator validation has a real success path or a documented MVP deferral approved in `SPEC.md`.

## Phase D: Editing Completion

Branch: `codex/editing-completion`

Goals:

- Split key and value encoding controls.
- Load full key/value for edit where needed.
- Keep write controls disabled when a snapshot is selected.
- Add row-switch unsaved-change confirmation.
- Wire Delete keyboard shortcut.
- Refresh only affected rows when feasible.

Acceptance:

- Tests cover add, edit same key, rename key via `WriteBatch`, conflict, delete, read-only guard, snapshot guard.
- Manual app flow can add/edit/delete in a temp DB.

## Phase E: Backup And Restore Completion

Branch: `codex/backup-restore-completion`

Goals:

- Add bridge APIs for `GetBackupInfo()`, `VerifyBackup()`, and selected `RestoreDBFromBackup(id, ...)`.
- List existing backups from backup directory.
- Restore selected backup ID, not only latest.
- Persist backup location per database.
- Add operation progress callbacks where RocksDB exposes them; otherwise show coarse staged progress.
- Implement backup cancellation using `BackupEngine::StopBackup()` where possible.
- Strengthen restore confirmation with source backup, destination, and overwrite warning.

Acceptance:

- Tests create multiple backups and restore a selected older backup.
- UI lists backup IDs after app restart.
- Restore over currently open DB remains blocked.

## Phase F: UX, Accessibility, And Verification

Branch: `codex/ux-accessibility-verification`

Goals:

- Add accessibility labels to all primary controls.
- Make Command-F focus the search field.
- Verify keyboard shortcuts from `SPEC.md` section 17.
- Add app-level smoke automation for:
  - launch,
  - open DB,
  - visible rows,
  - search,
  - snapshot,
  - backup.
- Reduce launch instructions to one supported path: `./scripts/run-app.sh`.

Acceptance:

- Automated smoke test verifies app window plus visible row count.
- `swift test` passes.
- `./scripts/run-app.sh` opens a visible window.

## Phase G: Performance Harness

Branch: `codex/performance-harness`

Goals:

- Add deterministic fixture generator:
  - tiny,
  - small,
  - many-cf,
  - large-values,
  - comparator datasets.
- Expand benchmark commands:
  - open,
  - exact get,
  - scan,
  - cancel,
  - backup,
  - restore.
- Add XCTest performance tests for bridge and scan engine.
- Record memory/RSS checkpoints where possible.
- Address Homebrew RocksDB deployment-target warning by documenting or building a compatible local RocksDB.

Acceptance:

- Fixture generator can create at least `tiny`, `small`, and `large-values`.
- Benchmarks print stable machine-readable metrics.
- Performance gates from `SPEC.md` section 13.5 are either passing or explicitly marked as not yet met.

## Do Not Regress

- App launch through `.build/RocksDBViewer.app`.
- Opening `jazz.rocksdb` displays non-placeholder rows.
- History stores metadata only.
- SwiftUI/AppKit code never holds raw RocksDB pointers.
- Bridge owns DB, column family, iterator, snapshot, and backup lifetimes.
