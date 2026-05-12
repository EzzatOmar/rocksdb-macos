# RocksDB Notes For This App

These notes are distilled from official RocksDB documentation and headers downloaded into `docs/upstream/`.

## Source Material

- Official wiki: `docs/upstream/rocksdb-basic-operations.md`
- Official wiki: `docs/upstream/rocksdb-column-families.md`
- Official wiki: `docs/upstream/rocksdb-iterator.md`
- Official wiki: `docs/upstream/rocksdb-snapshot.md`
- Official wiki: `docs/upstream/rocksdb-backup.md`
- Official source header: `docs/upstream/rocksdb-db.h`
- Official source header: `docs/upstream/rocksdb-backup_engine.h`

Canonical upstream locations:

- https://github.com/facebook/rocksdb/wiki/Basic-Operations
- https://github.com/facebook/rocksdb/wiki/Column-Families
- https://github.com/facebook/rocksdb/wiki/Iterator
- https://github.com/facebook/rocksdb/wiki/Snapshot
- https://github.com/facebook/rocksdb/wiki/How-to-backup-RocksDB
- https://github.com/facebook/rocksdb/blob/main/include/rocksdb/db.h
- https://github.com/facebook/rocksdb/blob/main/include/rocksdb/utilities/backup_engine.h

## Data Model Facts

- RocksDB stores arbitrary byte-array keys and values.
- Keys are sorted by the database comparator.
- The default comparator is bytewise lexicographic order.
- A custom comparator is part of the database contract. Opening with incompatible comparator behavior can make scans and reads incorrect.
- Each key belongs to exactly one column family. If no column family is named, the key belongs to `default`.

## Opening Databases

- A database maps to one filesystem directory.
- Normal read-write open takes the database lock.
- A DB can be opened read-only for read operations.
- Read-write open with column families must name all existing column families. Missing one is an invalid argument.
- Read-only open can open a subset of column families.
- `DB::ListColumnFamilies` is the discovery API.
- Column-family handles are owned resources. They must be destroyed before destroying the DB.

Implications for this app:

- Open flow should discover column families before open when possible.
- Read-write open must use all discovered column families, not only the selected one.
- UI should surface lock/open errors clearly.
- The Swift UI must never retain raw `DB*` or `ColumnFamilyHandle*`; the bridge owns them.

## Reads And Scans

- Exact lookup uses `DB::Get(ReadOptions, ColumnFamilyHandle, key, value)`.
- Iteration uses `DB::NewIterator(ReadOptions, ColumnFamilyHandle)`.
- Iterators are initially invalid until positioned.
- Forward scans use `Seek()` followed by `Next()`.
- Reverse scans use `SeekForPrev()` or `SeekToLast()` followed by `Prev()`.
- Iterator status must be checked after iteration.
- `ReadOptions` carries snapshot and scan options such as bounds.
- `MultiGet` exists for batched exact lookups, including across column families.

Implications for this app:

- Scans must stream bounded batches into Swift.
- The bridge should own iterator lifetime and check iterator status before reporting completion.
- Reverse range behavior must be explicit about inclusive/exclusive bounds.
- UI retained rows should be capped independently from the RocksDB iterator limit.
- Large values should be copied only up to the preview limit unless the user explicitly loads the full value.

## Writes

- `Put`, `Delete`, and `Write` mutate a database.
- `WriteBatch` applies multiple edits atomically and in order.
- Key rename must be modeled as delete old key plus put new key in one `WriteBatch`.
- Write options can request synchronous persistence; default writes are not fully synced to storage before returning.
- Within one process, `DB` is thread-safe. Objects such as iterators and write batches need their own synchronization if shared.

Implications for this app:

- Write controls must be disabled for read-only sessions and snapshot views.
- Key changes must use `WriteBatch`.
- Save failure must not optimistically mutate UI state.
- A future advanced write-options UI can expose sync/WAL choices, but MVP should use conservative defaults and clear errors.

## Snapshots

- A snapshot is a point-in-time read view.
- Snapshots do not persist across DB restarts.
- Create with `DB::GetSnapshot()`.
- Read through a snapshot by setting `ReadOptions::snapshot`.
- Release with `DB::ReleaseSnapshot()`.
- Many long-lived snapshots can slow flush/compaction because RocksDB must preserve visible historical versions.

Implications for this app:

- Snapshot handles are in-memory only and must be released when the DB closes.
- Active scans should retain the snapshot they use until completion or cancellation.
- UI should show snapshot age and active query count.
- Snapshot views are read-only.

## Backups And Restores

- Backup uses `BackupEngine`.
- Backup directories are managed by RocksDB and contain metadata plus copied/shared DB files.
- Backups are normally incremental because table files can be shared between backups.
- `CreateNewBackup()` can return the new integer backup ID.
- `GetBackupInfo()` lists backup IDs, timestamps, sizes, and optional file details.
- `VerifyBackup()` checks expected backup file sizes and can optionally verify checksums.
- Restore should use `BackupEngineReadOnly` when no backup mutation is needed.
- `RestoreDBFromBackup(id, db_dir, wal_dir)` restores a selected backup.
- `RestoreDBFromLatestBackup(db_dir, wal_dir)` restores the newest non-corrupt backup.
- Restore computes checksums and aborts on mismatch.
- Backup engine open time grows with the number of backups in a directory.

Implications for this app:

- Backup UI should list backup IDs from `GetBackupInfo()`, not only backups created during the current run.
- Restore UI should allow choosing a specific backup ID, not only latest.
- Restore over the currently open DB path must be blocked.
- Backup and restore should run off the main actor.
- Progress should come from RocksDB callbacks or coarse operation state.
- Backup verification should be exposed before restore.

## Comparators

- The comparator defines key ordering.
- Custom comparator code must provide stable ordering and a stable name/identifier.
- Comparator changes require reopening the DB.
- Comparator behavior must remain compatible across key-format evolution.

Implications for this app:

- Built-in comparator profiles can be UI-level profiles only when the bridge actually supplies equivalent RocksDB comparator instances.
- Current app support for non-bytewise profiles is not complete until those comparators are wired into `DB::Open`.
- Custom bundle loading needs an adapter layer from the Swift-facing plugin protocol to a C++ `rocksdb::Comparator`.

## Minimal App Rules

- Keep RocksDB objects inside the bridge/session layer.
- Use byte buffers deliberately; avoid converting binary data to strings except for previews.
- Keep scan batches bounded.
- Keep UI row retention bounded.
- Treat backup, restore, delete, and write-mode open as safety-sensitive operations.
