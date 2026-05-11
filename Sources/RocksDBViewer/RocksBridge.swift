import CRocksBridge
import Foundation

struct RocksBridgeError: LocalizedError, Equatable {
    var code: Int32
    var message: String

    var errorDescription: String? { message }
}

final class RocksDatabaseHandle: @unchecked Sendable {
    fileprivate var pointer: OpaquePointer?

    fileprivate init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    deinit {
        close()
    }

    func close() {
        if let pointer {
            rdb_close_database(pointer)
            self.pointer = nil
        }
    }
}

final class RocksSnapshotHandle: @unchecked Sendable {
    fileprivate var pointer: OpaquePointer?
    let bridgeID: UInt64

    fileprivate init(pointer: OpaquePointer, bridgeID: UInt64) {
        self.pointer = pointer
        self.bridgeID = bridgeID
    }

    deinit {
        release()
    }

    func release() {
        if let pointer {
            rdb_release_snapshot(pointer)
            self.pointer = nil
        }
    }
}

enum RocksBridge {
    static func listColumnFamilies(path: String) throws -> [String] {
        var status = rdb_status_ok()
        let array = path.withCString { pathPointer in
            rdb_list_column_families(pathPointer, &status)
        }
        defer {
            rdb_status_free(status)
            rdb_string_array_free(array)
        }
        try throwIfNeeded(status)
        return strings(from: array)
    }

    static func open(path: String, readOnly: Bool, createIfMissing: Bool, selectedColumnFamily: String?) throws -> RocksDatabaseHandle {
        var config = RDBOpenConfig(path: nil, read_only: readOnly, create_if_missing: createIfMissing, selected_column_family: nil)
        let result = path.withCString { pathPointer in
            selectedColumnFamily.withOptionalCString { selectedPointer in
                config.path = pathPointer
                config.selected_column_family = selectedPointer
                return rdb_open_database(config)
            }
        }
        defer { rdb_status_free(result.status) }
        try throwIfNeeded(result.status)
        guard let database = result.database else {
            throw RocksBridgeError(code: 1, message: "RocksDB did not return a database handle.")
        }
        return RocksDatabaseHandle(pointer: database)
    }

    static func columnFamilies(database: RocksDatabaseHandle) -> [String] {
        guard let pointer = database.pointer else { return [] }
        let array = rdb_database_column_families(pointer)
        defer { rdb_string_array_free(array) }
        return strings(from: array)
    }

    static func createSnapshot(database: RocksDatabaseHandle) throws -> RocksSnapshotHandle {
        guard let pointer = database.pointer else {
            throw RocksBridgeError(code: 1, message: "Database is not open.")
        }
        let result = rdb_create_snapshot(pointer)
        defer { rdb_status_free(result.status) }
        try throwIfNeeded(result.status)
        guard let snapshot = result.snapshot else {
            throw RocksBridgeError(code: 1, message: "RocksDB did not return a snapshot handle.")
        }
        return RocksSnapshotHandle(pointer: snapshot, bridgeID: result.snapshot_id)
    }

    static func get(database: RocksDatabaseHandle, columnFamily: String, key: Data) throws -> Data? {
        guard let pointer = database.pointer else {
            throw RocksBridgeError(code: 1, message: "Database is not open.")
        }
        let result = columnFamily.withCString { cfPointer in
            key.withUnsafeBytes { keyBytes in
                rdb_get(pointer, cfPointer, keyBytes.bindMemory(to: UInt8.self).baseAddress, keyBytes.count)
            }
        }
        defer {
            rdb_status_free(result.status)
            rdb_owned_bytes_free(result.value)
        }
        try throwIfNeeded(result.status)
        guard result.found else { return nil }
        return Data(bytes: result.value.data, count: result.value.count)
    }

    static func scan(database: RocksDatabaseHandle, snapshot: RocksSnapshotHandle?, request: ScanRequest, isCancelled: @escaping @Sendable () -> Bool = { false }) throws -> [KeyValueRow] {
        guard let pointer = database.pointer else {
            throw RocksBridgeError(code: 1, message: "Database is not open.")
        }

        let collector = ScanCollector(columnFamily: request.columnFamily, displayMode: .utf8)
        let cancelBox = CancelBox(isCancelled: isCancelled)
        let collectorPointer = Unmanaged.passUnretained(collector).toOpaque()
        let cancelPointer = Unmanaged.passUnretained(cancelBox).toOpaque()

        let status = request.withRDBScanConfig { config in
            var config = config
            config.snapshot = snapshot?.pointer
            return rdb_scan(pointer, config, scanRowCallback, collectorPointer, scanCancelCallback, cancelPointer)
        }
        defer { rdb_status_free(status) }
        try throwIfNeeded(status)
        return collector.rows
    }

    static func put(database: RocksDatabaseHandle, columnFamily: String, key: Data, value: Data) throws {
        try writeStatus(database: database, columnFamily: columnFamily) { pointer, cfPointer in
            key.withUnsafeBytes { keyBytes in
                value.withUnsafeBytes { valueBytes in
                    rdb_put(pointer, cfPointer, keyBytes.bindMemory(to: UInt8.self).baseAddress, keyBytes.count, valueBytes.bindMemory(to: UInt8.self).baseAddress, valueBytes.count)
                }
            }
        }
    }

    static func delete(database: RocksDatabaseHandle, columnFamily: String, key: Data) throws {
        try writeStatus(database: database, columnFamily: columnFamily) { pointer, cfPointer in
            key.withUnsafeBytes { keyBytes in
                rdb_delete(pointer, cfPointer, keyBytes.bindMemory(to: UInt8.self).baseAddress, keyBytes.count)
            }
        }
    }

    static func writeKeyChange(database: RocksDatabaseHandle, columnFamily: String, oldKey: Data, newKey: Data, value: Data) throws {
        try writeStatus(database: database, columnFamily: columnFamily) { pointer, cfPointer in
            oldKey.withUnsafeBytes { oldKeyBytes in
                newKey.withUnsafeBytes { newKeyBytes in
                    value.withUnsafeBytes { valueBytes in
                        rdb_write_key_change(
                            pointer,
                            cfPointer,
                            oldKeyBytes.bindMemory(to: UInt8.self).baseAddress,
                            oldKeyBytes.count,
                            newKeyBytes.bindMemory(to: UInt8.self).baseAddress,
                            newKeyBytes.count,
                            valueBytes.bindMemory(to: UInt8.self).baseAddress,
                            valueBytes.count
                        )
                    }
                }
            }
        }
    }

    static func createBackup(database: RocksDatabaseHandle, backupDirectory: String) throws -> UInt32 {
        guard let pointer = database.pointer else {
            throw RocksBridgeError(code: 1, message: "Database is not open.")
        }
        var backupID: UInt32 = 0
        let status = backupDirectory.withCString { backupPointer in
            rdb_create_backup(pointer, backupPointer, &backupID)
        }
        defer { rdb_status_free(status) }
        try throwIfNeeded(status)
        return backupID
    }

    static func restoreLatestBackup(backupDirectory: String, destinationDirectory: String) throws {
        let status = backupDirectory.withCString { backupPointer in
            destinationDirectory.withCString { destinationPointer in
                rdb_restore_latest_backup(backupPointer, destinationPointer)
            }
        }
        defer { rdb_status_free(status) }
        try throwIfNeeded(status)
    }

    private static func writeStatus(database: RocksDatabaseHandle, columnFamily: String, body: (OpaquePointer, UnsafePointer<CChar>?) -> RDBStatus) throws {
        guard let pointer = database.pointer else {
            throw RocksBridgeError(code: 1, message: "Database is not open.")
        }
        let status = columnFamily.withCString { cfPointer in
            body(pointer, cfPointer)
        }
        defer { rdb_status_free(status) }
        try throwIfNeeded(status)
    }

    private static func throwIfNeeded(_ status: RDBStatus) throws {
        guard status.code != 0 else { return }
        let message = status.message.map { String(cString: $0) } ?? "Unknown RocksDB error."
        throw RocksBridgeError(code: status.code, message: message)
    }

    private static func strings(from array: RDBStringArray) -> [String] {
        guard let values = array.values else { return [] }
        return (0..<array.count).compactMap { index in
            values[index].map { String(cString: $0) }
        }
    }
}

private final class ScanCollector {
    let columnFamily: String
    let displayMode: ValueDisplayMode
    var rows: [KeyValueRow] = []

    init(columnFamily: String, displayMode: ValueDisplayMode) {
        self.columnFamily = columnFamily
        self.displayMode = displayMode
    }
}

private final class CancelBox {
    let isCancelled: @Sendable () -> Bool

    init(isCancelled: @escaping @Sendable () -> Bool) {
        self.isCancelled = isCancelled
    }
}

private let scanCancelCallback: RDBCancelCallback = { context in
    guard let context else { return false }
    return Unmanaged<CancelBox>.fromOpaque(context).takeUnretainedValue().isCancelled()
}

private let scanRowCallback: RDBScanRowCallback = { keyPointer, keyCount, valuePointer, valueCount, valuePreviewCount, sequenceIndex, context in
    guard let context, let keyPointer else { return }
    let collector = Unmanaged<ScanCollector>.fromOpaque(context).takeUnretainedValue()
    let keyData = Data(bytes: keyPointer, count: keyCount)
    let valueData: Data
    if let valuePointer, valuePreviewCount > 0 {
        valueData = Data(bytes: valuePointer, count: valuePreviewCount)
    } else {
        valueData = Data()
    }
    let row = KeyValueRow(
        id: StableRowID(columnFamily: collector.columnFamily, sequenceIndex: sequenceIndex, keyDigest: stableDigest(keyData)),
        keyPreview: BytePreview(bytes: keyData, totalSize: keyCount, preferredDisplay: .utf8, limit: BytePreview.defaultLimit),
        valuePreview: BytePreview(bytes: valueData, totalSize: valueCount, preferredDisplay: collector.displayMode, limit: BytePreview.defaultLimit),
        keySize: keyCount,
        valueSize: valueCount,
        sequenceIndex: sequenceIndex,
        source: .live
    )
    collector.rows.append(row)
}

private func stableDigest(_ data: Data) -> UInt64 {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in data {
        hash ^= UInt64(byte)
        hash &*= 1_099_511_628_211
    }
    return hash
}

private extension ScanRequest {
    func withRDBScanConfig<Result>(_ body: (RDBScanConfig) -> Result) -> Result {
        let exact = mode == .exact ? lowerBound : nil
        return columnFamily.withCString { cfPointer in
            exact.withOptionalUnsafeBytes { exactPointer, exactCount in
                lowerBound.withOptionalUnsafeBytes { lowerPointer, lowerCount in
                    upperBound.withOptionalUnsafeBytes { upperPointer, upperCount in
                        prefix.withOptionalUnsafeBytes { prefixPointer, prefixCount in
                            let config = RDBScanConfig(
                                column_family: cfPointer,
                                mode: rdbMode,
                                exact_key: exactPointer,
                                exact_key_count: exactCount,
                                lower_bound: lowerPointer,
                                lower_bound_count: lowerCount,
                                upper_bound: upperPointer,
                                upper_bound_count: upperCount,
                                prefix: prefixPointer,
                                prefix_count: prefixCount,
                                limit: limit,
                                preview_byte_limit: previewByteLimit,
                                reverse: direction == .reverse,
                                snapshot: nil
                            )
                            return body(config)
                        }
                    }
                }
            }
        }
    }

    var rdbMode: RDBScanMode {
        switch mode {
        case .exact: RDB_SCAN_EXACT
        case .prefix: RDB_SCAN_PREFIX
        case .range: RDB_SCAN_RANGE
        }
    }
}

private extension Optional where Wrapped == Data {
    func withOptionalUnsafeBytes<Result>(_ body: (UnsafePointer<UInt8>?, Int) -> Result) -> Result {
        switch self {
        case .some(let data):
            return data.withUnsafeBytes { buffer in
                body(buffer.bindMemory(to: UInt8.self).baseAddress, buffer.count)
            }
        case .none:
            return body(nil, 0)
        }
    }
}

private extension Optional where Wrapped == String {
    func withOptionalCString<Result>(_ body: (UnsafePointer<CChar>?) -> Result) -> Result {
        switch self {
        case .some(let string):
            return string.withCString(body)
        case .none:
            return body(nil)
        }
    }
}
