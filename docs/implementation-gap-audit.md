# SPEC.md To Code Gap Audit

Date: 2026-05-12

Current branch: `codex/docs-gap-plan`

## What Exists

- SwiftPM package with app executable and benchmark executable.
- AppKit-backed macOS app bundle scripts:
  - `scripts/build-app.sh`
  - `scripts/run-app.sh`
- RocksDB bridge for:
  - open read-only/read-write
  - list/open column families
  - get
  - iterator scan
  - put/delete/write-batch key change
  - snapshot create/release
  - latest backup create/restore
- App model can open `jazz.rocksdb` and populate rows.
- Tests cover open, scan, snapshots, backup/restore, history, comparator registry basics, byte previews, and app-model open.

## Major Gaps Against SPEC.md

### Open Flow

Spec references: `SPEC.md` 9.2, 11.1, 14.

- `Create if missing` exists in UI but is disabled and is not passed through from the sheet.
- Read-write lock warning is not implemented.
- Column-family discovery result does not reliably update the sheet-local selected column family.
- Recent database rows are selectable but do not directly reopen the DB.
- Open errors are shown only in the operation log, not as actionable sheet validation.
- Open mode and comparator profile are persisted in history, but backup location is not persisted per database.

### Comparators

Spec references: `SPEC.md` 5.1, 6.2, 9.6, 12.5, 15.

- Built-in comparator profiles are UI metadata only; the bridge always opens RocksDB with default comparator options.
- Reverse bytewise, fixed-width signed integer, fixed-width unsigned integer, and UTF-8 lexical comparators are not implemented as RocksDB `Comparator` instances.
- Custom comparator bundle loading is scaffolded as a validation failure and cannot open a DB.
- Comparator sample ordering is not shown in a comparator dialog.
- Custom comparator identity is not verified against a loaded comparator implementation.

### Scanning And Memory

Spec references: `SPEC.md` 7.3, 9.1, 9.3, 12.3, 12.4, 18.2, 18.3.

- The C++ bridge scans into a Swift array before the async stream emits batches. This is bounded by the request limit, but it is not true incremental streaming.
- UI has no scroll-triggered incremental fetch. It performs a bounded scan and displays the result.
- Cancellation is checked during C++ iteration, but UI updates only after bridge scan returns.
- Exact lookup goes through `rdb_get`, which copies the full value before Swift truncates. This violates the large-value preview rule.
- `Load Full Value` exists but is disabled.
- `sequenceIndex` is scan-local, not a stable global row identity.
- Prefix reverse seek uses `prefix + 0xff`, which is not a robust arbitrary-byte prefix upper bound.

### Editing

Spec references: `SPEC.md` 9.4, 10, 11.4, 12.6.

- Add/edit sheet uses one encoding selection for both key and value.
- Existing rows are edited from previews. Full key/value load is not implemented, so large or truncated values cannot be edited correctly.
- JSON editing validates JSON but does not pretty-print or preserve binary mode semantics.
- Unsaved edit confirmation exists for cancel, but not for switching selected rows while the sheet is open.
- Delete command from keyboard is not wired.
- Snapshot views are intended read-only, but write controls are only guarded by open mode, not by selected snapshot state.

### Snapshots

Spec references: `SPEC.md` 9.5, 11.3, 12.4.

- Snapshot handles are implemented and scans can read from a snapshot.
- Active query count is not tracked.
- Snapshot release while scans are active is protected by actor serialization, but the UI does not explain or show retained active scans.
- Snapshot names are auto-generated only and cannot be edited.

### Backup And Restore

Spec references: `SPEC.md` 9.5, 10, 11.5, 11.6, 12.7.

- Backup creation works through `BackupEngine`.
- Restore latest works through `BackupEngineReadOnly`.
- Existing backups are not listed from `GetBackupInfo()`.
- Restore can only restore latest, not a selected backup ID.
- Backup list size/status fields are placeholders for current-run backups only.
- Backup directory is not persisted per database.
- Backup and restore progress callbacks are not wired.
- Cancel for backup/restore is not implemented.
- Backup verification is not exposed.
- Restore confirmation is generic and lacks source backup details.

### UI And Accessibility

Spec references: `SPEC.md` 8, 9, 16, 17.

- The app now launches reliably as `.build/RocksDBViewer.app`.
- Toolbar and panels exist, but several controls are placeholders or disabled.
- Accessibility labels are incomplete outside the toolbar.
- Keyboard shortcuts are partially implemented through AppKit menu items.
- Delete key shortcut is missing.
- Standard focus behavior for Command-F is section switching, not field focus.
- UI has not been verified with automated interaction beyond window existence and app-model open tests.

### Performance And Tooling

Spec references: `SPEC.md` 12, 13, 19.

- Benchmark target can open and scan.
- Fixture generator is missing.
- No perf tests for open latency, first-row latency, exact lookup percentiles, retained memory, or scan cancellation latency.
- No UI automation target for scroll/cancel behavior.
- RocksDB is linked from Homebrew using unsafe flags and currently warns that the dylib was built for a newer macOS than the package deployment target.

## Highest-Risk Technical Debt

- The bridge does not implement true streaming; it returns an array after C++ scan completes.
- Exact lookup copies full values.
- Comparator profiles do not affect RocksDB open behavior.
- Backup/restore UI does not reflect existing backup state.
- App launch requires bundled script because a bare SwiftPM GUI executable is unreliable for AppKit/SwiftUI window activation.
