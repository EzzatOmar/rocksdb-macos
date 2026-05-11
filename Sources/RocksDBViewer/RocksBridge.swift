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
