import Foundation

struct DatabaseOpenRequest: Sendable, Equatable {
    var path: String
    var mode: OpenMode
    var createIfMissing: Bool
    var selectedColumnFamily: String?
}

struct DatabaseMetadata: Sendable, Equatable {
    var path: String
    var openMode: OpenMode
    var columnFamilies: [String]
    var selectedColumnFamily: String
}

actor DatabaseSession {
    private var handle: RocksDatabaseHandle?
    private var metadata: DatabaseMetadata?
    private var snapshots: [UUID: RocksSnapshotHandle] = [:]

    var currentMetadata: DatabaseMetadata? {
        metadata
    }

    func discoverColumnFamilies(path: String) throws -> [String] {
        try RocksBridge.listColumnFamilies(path: path)
    }

    func open(_ request: DatabaseOpenRequest) throws -> DatabaseMetadata {
        close()
        let database = try RocksBridge.open(
            path: request.path,
            readOnly: request.mode == .readOnly,
            createIfMissing: request.createIfMissing,
            selectedColumnFamily: request.selectedColumnFamily
        )
        let families = RocksBridge.columnFamilies(database: database)
        let selected = request.selectedColumnFamily.flatMap { families.contains($0) ? $0 : nil }
            ?? families.first
            ?? "default"
        let nextMetadata = DatabaseMetadata(path: request.path, openMode: request.mode, columnFamilies: families, selectedColumnFamily: selected)
        handle = database
        metadata = nextMetadata
        return nextMetadata
    }

    func close() {
        for snapshot in snapshots.values {
            snapshot.release()
        }
        snapshots.removeAll()
        handle?.close()
        handle = nil
        metadata = nil
    }

    func get(columnFamily: String, key: Data) throws -> Data? {
        guard let handle else {
            throw RocksBridgeError(code: 1, message: "Database is not open.")
        }
        return try RocksBridge.get(database: handle, columnFamily: columnFamily, key: key)
    }

    func scanRows(_ request: ScanRequest, isCancelled: @escaping @Sendable () -> Bool = { false }) throws -> [KeyValueRow] {
        guard let handle else {
            throw RocksBridgeError(code: 1, message: "Database is not open.")
        }
        let snapshot = request.snapshotID.flatMap { snapshots[$0] }
        return try RocksBridge.scan(database: handle, snapshot: snapshot, request: request, isCancelled: isCancelled)
    }

    nonisolated func scan(_ request: ScanRequest, batchSize: Int = 256) -> AsyncThrowingStream<[KeyValueRow], Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let rows = try await scanRows(request, isCancelled: { Task.isCancelled })
                    var index = rows.startIndex
                    while index < rows.endIndex {
                        let end = rows.index(index, offsetBy: batchSize, limitedBy: rows.endIndex) ?? rows.endIndex
                        continuation.yield(Array(rows[index..<end]))
                        index = end
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func put(columnFamily: String, key: Data, value: Data) throws {
        guard let handle, metadata?.openMode == .readWrite else {
            throw RocksBridgeError(code: 1, message: "Database is open read-only.")
        }
        try RocksBridge.put(database: handle, columnFamily: columnFamily, key: key, value: value)
    }

    func delete(columnFamily: String, key: Data) throws {
        guard let handle, metadata?.openMode == .readWrite else {
            throw RocksBridgeError(code: 1, message: "Database is open read-only.")
        }
        try RocksBridge.delete(database: handle, columnFamily: columnFamily, key: key)
    }

    func writeKeyChange(columnFamily: String, oldKey: Data, newKey: Data, value: Data) throws {
        guard let handle, metadata?.openMode == .readWrite else {
            throw RocksBridgeError(code: 1, message: "Database is open read-only.")
        }
        try RocksBridge.writeKeyChange(database: handle, columnFamily: columnFamily, oldKey: oldKey, newKey: newKey, value: value)
    }

    func createSnapshot(id: UUID) throws {
        guard let handle else {
            throw RocksBridgeError(code: 1, message: "Database is not open.")
        }
        snapshots[id] = try RocksBridge.createSnapshot(database: handle)
    }

    func releaseSnapshot(id: UUID) {
        snapshots[id]?.release()
        snapshots[id] = nil
    }

    func createBackup(backupDirectory: String) throws -> UInt32 {
        guard let handle else {
            throw RocksBridgeError(code: 1, message: "Database is not open.")
        }
        return try RocksBridge.createBackup(database: handle, backupDirectory: backupDirectory)
    }

    func restoreLatestBackup(backupDirectory: String, destinationDirectory: String) throws {
        if let metadata, URL(fileURLWithPath: metadata.path).standardizedFileURL == URL(fileURLWithPath: destinationDirectory).standardizedFileURL {
            throw RocksBridgeError(code: 1, message: "Cannot restore over the currently open database. Close it first or choose another destination.")
        }
        try RocksBridge.restoreLatestBackup(backupDirectory: backupDirectory, destinationDirectory: destinationDirectory)
    }
}
