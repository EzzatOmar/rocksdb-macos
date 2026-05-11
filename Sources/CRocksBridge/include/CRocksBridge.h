#ifndef C_ROCKS_BRIDGE_H
#define C_ROCKS_BRIDGE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct RDBDatabase RDBDatabase;

typedef struct {
    int32_t code;
    char *message;
} RDBStatus;

typedef struct {
    char **values;
    size_t count;
} RDBStringArray;

typedef struct {
    uint8_t *data;
    size_t count;
} RDBOwnedBytes;

typedef struct {
    const char *path;
    bool read_only;
    bool create_if_missing;
    const char *selected_column_family;
} RDBOpenConfig;

typedef struct {
    RDBDatabase *database;
    RDBStatus status;
} RDBOpenResult;

typedef struct {
    bool found;
    RDBOwnedBytes value;
    RDBStatus status;
} RDBGetResult;

typedef enum {
    RDB_SCAN_EXACT = 0,
    RDB_SCAN_PREFIX = 1,
    RDB_SCAN_RANGE = 2
} RDBScanMode;

typedef struct {
    const char *column_family;
    RDBScanMode mode;
    const uint8_t *exact_key;
    size_t exact_key_count;
    const uint8_t *lower_bound;
    size_t lower_bound_count;
    const uint8_t *upper_bound;
    size_t upper_bound_count;
    const uint8_t *prefix;
    size_t prefix_count;
    size_t limit;
    size_t preview_byte_limit;
    bool reverse;
} RDBScanConfig;

typedef bool (*RDBCancelCallback)(void *context);
typedef void (*RDBScanRowCallback)(const uint8_t *key, size_t key_count, const uint8_t *value, size_t value_count, size_t value_preview_count, uint64_t sequence_index, void *context);

RDBStatus rdb_status_ok(void);
void rdb_status_free(RDBStatus status);

RDBStringArray rdb_list_column_families(const char *path, RDBStatus *status);
void rdb_string_array_free(RDBStringArray array);

RDBOpenResult rdb_open_database(RDBOpenConfig config);
void rdb_close_database(RDBDatabase *database);

RDBStringArray rdb_database_column_families(RDBDatabase *database);
const char *rdb_database_path(RDBDatabase *database);
bool rdb_database_is_read_only(RDBDatabase *database);

RDBGetResult rdb_get(RDBDatabase *database, const char *column_family, const uint8_t *key, size_t key_count);
RDBStatus rdb_scan(RDBDatabase *database, RDBScanConfig config, RDBScanRowCallback callback, void *callback_context, RDBCancelCallback cancel_callback, void *cancel_context);
RDBStatus rdb_put(RDBDatabase *database, const char *column_family, const uint8_t *key, size_t key_count, const uint8_t *value, size_t value_count);
RDBStatus rdb_delete(RDBDatabase *database, const char *column_family, const uint8_t *key, size_t key_count);
RDBStatus rdb_write_key_change(RDBDatabase *database, const char *column_family, const uint8_t *old_key, size_t old_key_count, const uint8_t *new_key, size_t new_key_count, const uint8_t *value, size_t value_count);

void rdb_owned_bytes_free(RDBOwnedBytes bytes);

#ifdef __cplusplus
}
#endif

#endif
