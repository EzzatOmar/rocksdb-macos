#include "CRocksBridge.h"

#include <rocksdb/db.h>
#include <rocksdb/options.h>
#include <rocksdb/slice.h>
#include <rocksdb/write_batch.h>

#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <map>
#include <memory>
#include <string>
#include <vector>

struct RDBDatabase {
    std::unique_ptr<rocksdb::DB> db;
    std::vector<rocksdb::ColumnFamilyHandle *> handles;
    std::map<std::string, rocksdb::ColumnFamilyHandle *> handle_by_name;
    std::string path;
    bool read_only = true;
};

static char *rdb_strdup(const std::string &value) {
    char *copy = static_cast<char *>(std::malloc(value.size() + 1));
    if (copy == nullptr) {
        return nullptr;
    }
    std::memcpy(copy, value.c_str(), value.size() + 1);
    return copy;
}

static RDBStatus rdb_status_from(const rocksdb::Status &status) {
    if (status.ok()) {
        return rdb_status_ok();
    }
    return RDBStatus{static_cast<int32_t>(status.code()), rdb_strdup(status.ToString())};
}

static rocksdb::ColumnFamilyHandle *rdb_find_handle(RDBDatabase *database, const char *column_family) {
    if (database == nullptr) {
        return nullptr;
    }
    std::string name = column_family == nullptr || std::strlen(column_family) == 0
        ? rocksdb::kDefaultColumnFamilyName
        : std::string(column_family);
    auto it = database->handle_by_name.find(name);
    if (it == database->handle_by_name.end()) {
        return nullptr;
    }
    return it->second;
}

RDBStatus rdb_status_ok(void) {
    return RDBStatus{0, nullptr};
}

void rdb_status_free(RDBStatus status) {
    if (status.message != nullptr) {
        std::free(status.message);
    }
}

RDBStringArray rdb_list_column_families(const char *path, RDBStatus *status) {
    if (path == nullptr || std::strlen(path) == 0) {
        if (status != nullptr) {
            *status = RDBStatus{1, rdb_strdup("Database path is empty.")};
        }
        return RDBStringArray{nullptr, 0};
    }

    rocksdb::Options options;
    std::vector<std::string> names;
    rocksdb::Status rocks_status = rocksdb::DB::ListColumnFamilies(options, path, &names);
    if (!rocks_status.ok()) {
        if (status != nullptr) {
            *status = rdb_status_from(rocks_status);
        }
        return RDBStringArray{nullptr, 0};
    }

    char **values = static_cast<char **>(std::calloc(names.size(), sizeof(char *)));
    if (values == nullptr && !names.empty()) {
        if (status != nullptr) {
            *status = RDBStatus{1, rdb_strdup("Unable to allocate column family list.")};
        }
        return RDBStringArray{nullptr, 0};
    }
    for (size_t i = 0; i < names.size(); ++i) {
        values[i] = rdb_strdup(names[i]);
    }
    if (status != nullptr) {
        *status = rdb_status_ok();
    }
    return RDBStringArray{values, names.size()};
}

void rdb_string_array_free(RDBStringArray array) {
    for (size_t i = 0; i < array.count; ++i) {
        std::free(array.values[i]);
    }
    std::free(array.values);
}

RDBOpenResult rdb_open_database(RDBOpenConfig config) {
    if (config.path == nullptr || std::strlen(config.path) == 0) {
        return RDBOpenResult{nullptr, RDBStatus{1, rdb_strdup("Database path is empty.")}};
    }

    rocksdb::DBOptions db_options;
    db_options.create_if_missing = config.create_if_missing;
    db_options.create_missing_column_families = false;
    rocksdb::ColumnFamilyOptions cf_options;

    RDBStatus cf_status = rdb_status_ok();
    RDBStringArray cf_array = rdb_list_column_families(config.path, &cf_status);
    std::vector<std::string> names;
    if (cf_status.code == 0) {
        for (size_t i = 0; i < cf_array.count; ++i) {
            names.emplace_back(cf_array.values[i]);
        }
        rdb_string_array_free(cf_array);
    } else {
        rdb_status_free(cf_status);
        names.push_back(rocksdb::kDefaultColumnFamilyName);
    }
    if (names.empty()) {
        names.push_back(rocksdb::kDefaultColumnFamilyName);
    }

    std::vector<rocksdb::ColumnFamilyDescriptor> descriptors;
    descriptors.reserve(names.size());
    for (const std::string &name : names) {
        descriptors.emplace_back(name, cf_options);
    }

    std::unique_ptr<rocksdb::DB> opened_db;
    std::vector<rocksdb::ColumnFamilyHandle *> handles;
    rocksdb::Status open_status = config.read_only
        ? rocksdb::DB::OpenForReadOnly(db_options, config.path, descriptors, &handles, &opened_db)
        : rocksdb::DB::Open(db_options, config.path, descriptors, &handles, &opened_db);
    if (!open_status.ok()) {
        return RDBOpenResult{nullptr, rdb_status_from(open_status)};
    }

    auto database = std::make_unique<RDBDatabase>();
    database->db = std::move(opened_db);
    database->handles = handles;
    database->path = config.path;
    database->read_only = config.read_only;
    for (size_t i = 0; i < names.size() && i < handles.size(); ++i) {
        database->handle_by_name[names[i]] = handles[i];
    }

    return RDBOpenResult{database.release(), rdb_status_ok()};
}

void rdb_close_database(RDBDatabase *database) {
    if (database == nullptr) {
        return;
    }
    for (rocksdb::ColumnFamilyHandle *handle : database->handles) {
        if (handle != nullptr) {
            database->db->DestroyColumnFamilyHandle(handle);
        }
    }
    delete database;
}

RDBStringArray rdb_database_column_families(RDBDatabase *database) {
    if (database == nullptr) {
        return RDBStringArray{nullptr, 0};
    }

    std::vector<std::string> names;
    names.reserve(database->handle_by_name.size());
    for (const auto &entry : database->handle_by_name) {
        names.push_back(entry.first);
    }
    std::sort(names.begin(), names.end());

    char **values = static_cast<char **>(std::calloc(names.size(), sizeof(char *)));
    if (values == nullptr && !names.empty()) {
        return RDBStringArray{nullptr, 0};
    }
    for (size_t i = 0; i < names.size(); ++i) {
        values[i] = rdb_strdup(names[i]);
    }
    return RDBStringArray{values, names.size()};
}

const char *rdb_database_path(RDBDatabase *database) {
    return database == nullptr ? nullptr : database->path.c_str();
}

bool rdb_database_is_read_only(RDBDatabase *database) {
    return database == nullptr || database->read_only;
}

RDBGetResult rdb_get(RDBDatabase *database, const char *column_family, const uint8_t *key, size_t key_count) {
    if (database == nullptr) {
        return RDBGetResult{false, RDBOwnedBytes{nullptr, 0}, RDBStatus{1, rdb_strdup("Database is not open.")}};
    }
    rocksdb::ColumnFamilyHandle *handle = rdb_find_handle(database, column_family);
    if (handle == nullptr) {
        return RDBGetResult{false, RDBOwnedBytes{nullptr, 0}, RDBStatus{1, rdb_strdup("Column family not found.")}};
    }

    std::string value;
    rocksdb::Status status = database->db->Get(rocksdb::ReadOptions(), handle, rocksdb::Slice(reinterpret_cast<const char *>(key), key_count), &value);
    if (status.IsNotFound()) {
        return RDBGetResult{false, RDBOwnedBytes{nullptr, 0}, rdb_status_ok()};
    }
    if (!status.ok()) {
        return RDBGetResult{false, RDBOwnedBytes{nullptr, 0}, rdb_status_from(status)};
    }

    uint8_t *bytes = static_cast<uint8_t *>(std::malloc(value.size()));
    if (bytes == nullptr && !value.empty()) {
        return RDBGetResult{false, RDBOwnedBytes{nullptr, 0}, RDBStatus{1, rdb_strdup("Unable to allocate value.")}};
    }
    if (!value.empty()) {
        std::memcpy(bytes, value.data(), value.size());
    }
    return RDBGetResult{true, RDBOwnedBytes{bytes, value.size()}, rdb_status_ok()};
}

RDBStatus rdb_put(RDBDatabase *database, const char *column_family, const uint8_t *key, size_t key_count, const uint8_t *value, size_t value_count) {
    if (database == nullptr) {
        return RDBStatus{1, rdb_strdup("Database is not open.")};
    }
    if (database->read_only) {
        return RDBStatus{1, rdb_strdup("Database is open read-only.")};
    }
    rocksdb::ColumnFamilyHandle *handle = rdb_find_handle(database, column_family);
    if (handle == nullptr) {
        return RDBStatus{1, rdb_strdup("Column family not found.")};
    }
    rocksdb::Status status = database->db->Put(
        rocksdb::WriteOptions(),
        handle,
        rocksdb::Slice(reinterpret_cast<const char *>(key), key_count),
        rocksdb::Slice(reinterpret_cast<const char *>(value), value_count)
    );
    return rdb_status_from(status);
}

RDBStatus rdb_delete(RDBDatabase *database, const char *column_family, const uint8_t *key, size_t key_count) {
    if (database == nullptr) {
        return RDBStatus{1, rdb_strdup("Database is not open.")};
    }
    if (database->read_only) {
        return RDBStatus{1, rdb_strdup("Database is open read-only.")};
    }
    rocksdb::ColumnFamilyHandle *handle = rdb_find_handle(database, column_family);
    if (handle == nullptr) {
        return RDBStatus{1, rdb_strdup("Column family not found.")};
    }
    return rdb_status_from(database->db->Delete(rocksdb::WriteOptions(), handle, rocksdb::Slice(reinterpret_cast<const char *>(key), key_count)));
}

RDBStatus rdb_write_key_change(RDBDatabase *database, const char *column_family, const uint8_t *old_key, size_t old_key_count, const uint8_t *new_key, size_t new_key_count, const uint8_t *value, size_t value_count) {
    if (database == nullptr) {
        return RDBStatus{1, rdb_strdup("Database is not open.")};
    }
    if (database->read_only) {
        return RDBStatus{1, rdb_strdup("Database is open read-only.")};
    }
    rocksdb::ColumnFamilyHandle *handle = rdb_find_handle(database, column_family);
    if (handle == nullptr) {
        return RDBStatus{1, rdb_strdup("Column family not found.")};
    }
    rocksdb::WriteBatch batch;
    batch.Delete(handle, rocksdb::Slice(reinterpret_cast<const char *>(old_key), old_key_count));
    batch.Put(handle, rocksdb::Slice(reinterpret_cast<const char *>(new_key), new_key_count), rocksdb::Slice(reinterpret_cast<const char *>(value), value_count));
    return rdb_status_from(database->db->Write(rocksdb::WriteOptions(), &batch));
}

void rdb_owned_bytes_free(RDBOwnedBytes bytes) {
    std::free(bytes.data);
}
