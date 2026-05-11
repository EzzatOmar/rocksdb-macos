import CRocksBridge
import Foundation

final class Counter {
    var rows: UInt64 = 0
}

let rowCallback: RDBScanRowCallback = { _, _, _, _, _, _, context in
    guard let context else { return }
    Unmanaged<Counter>.fromOpaque(context).takeUnretainedValue().rows += 1
}

func throwIfNeeded(_ status: RDBStatus) throws {
    defer { rdb_status_free(status) }
    guard status.code != 0 else { return }
    throw NSError(domain: "RocksDBViewerBench", code: Int(status.code), userInfo: [
        NSLocalizedDescriptionKey: status.message.map { String(cString: $0) } ?? "Unknown RocksDB error"
    ])
}

func usage() -> Never {
    print("""
    Usage:
      swift run rocksdb-viewer-bench open <db-path>
      swift run rocksdb-viewer-bench scan <db-path> [--lower key] [--upper key] [--limit n]
    """)
    exit(2)
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { usage() }

do {
    switch command {
    case "open":
        guard args.count >= 2 else { usage() }
        let start = ContinuousClock.now
        let result = args[1].withCString { pathPointer in
            rdb_open_database(RDBOpenConfig(path: pathPointer, read_only: true, create_if_missing: false, selected_column_family: nil))
        }
        try throwIfNeeded(result.status)
        guard let database = result.database else {
            throw NSError(domain: "RocksDBViewerBench", code: 1, userInfo: [NSLocalizedDescriptionKey: "No database handle returned"])
        }
        rdb_close_database(database)
        print("open_ms=\(start.duration(to: .now).milliseconds)")

    case "scan":
        guard args.count >= 2 else { usage() }
        let path = args[1]
        var lower = Data()
        var upper = Data()
        var limit = 100_000
        var index = 2
        while index < args.count {
            switch args[index] {
            case "--lower":
                index += 1
                guard index < args.count else { usage() }
                lower = Data(args[index].utf8)
            case "--upper":
                index += 1
                guard index < args.count else { usage() }
                upper = Data(args[index].utf8)
            case "--limit":
                index += 1
                guard index < args.count, let parsed = Int(args[index]) else { usage() }
                limit = parsed
            default:
                usage()
            }
            index += 1
        }

        let openResult = path.withCString { pathPointer in
            rdb_open_database(RDBOpenConfig(path: pathPointer, read_only: true, create_if_missing: false, selected_column_family: nil))
        }
        try throwIfNeeded(openResult.status)
        guard let database = openResult.database else {
            throw NSError(domain: "RocksDBViewerBench", code: 1, userInfo: [NSLocalizedDescriptionKey: "No database handle returned"])
        }
        defer { rdb_close_database(database) }

        let counter = Counter()
        let counterPointer = Unmanaged.passUnretained(counter).toOpaque()
        let start = ContinuousClock.now
        let status = "default".withCString { cfPointer in
            lower.withUnsafeBytes { lowerBytes in
                upper.withUnsafeBytes { upperBytes in
                    let config = RDBScanConfig(
                        column_family: cfPointer,
                        mode: RDB_SCAN_RANGE,
                        exact_key: nil,
                        exact_key_count: 0,
                        lower_bound: lowerBytes.bindMemory(to: UInt8.self).baseAddress,
                        lower_bound_count: lowerBytes.count,
                        upper_bound: upperBytes.bindMemory(to: UInt8.self).baseAddress,
                        upper_bound_count: upperBytes.count,
                        prefix: nil,
                        prefix_count: 0,
                        limit: limit,
                        preview_byte_limit: 4096,
                        reverse: false,
                        snapshot: nil
                    )
                    return rdb_scan(database, config, rowCallback, counterPointer, nil, nil)
                }
            }
        }
        try throwIfNeeded(status)
        let duration = start.duration(to: .now)
        print("rows=\(counter.rows) elapsed_ms=\(duration.milliseconds)")

    default:
        usage()
    }
} catch {
    fputs("error: \(error.localizedDescription)\n", stderr)
    exit(1)
}

private extension Duration {
    var milliseconds: Int64 {
        let components = components
        return components.seconds * 1_000 + Int64(components.attoseconds / 1_000_000_000_000_000)
    }
}
