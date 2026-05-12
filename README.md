# RocksDB Viewer

Native macOS RocksDB browser built with SwiftPM.

## Start The App

Build and launch the app bundle:

```bash
./scripts/run-app.sh
```

The script builds `RocksDBViewer` with SwiftPM, wraps it in `.build/RocksDBViewer.app`, ad-hoc signs the bundle, and opens it with Launch Services.

For CLI smoke checks:

```bash
swift test
swift run rocksdb-viewer-bench open jazz.rocksdb
swift run rocksdb-viewer-bench scan jazz.rocksdb --limit 10
```

`swift run RocksDBViewer` still builds the executable, but the app bundle path is preferred because SwiftPM's bare GUI executable does not provide the bundle metadata AppKit expects for reliable window activation.
