#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="RocksDBViewer"
VOLUME_NAME="RocksDB Viewer"
DMG_NAME="RocksDBViewer.dmg"
CONFIGURATION="${CONFIGURATION:-release}"
APP_DIR="$(CONFIGURATION="$CONFIGURATION" "$ROOT_DIR/scripts/build-app.sh")"
DIST_DIR="$ROOT_DIR/dist"
STAGING_DIR="$ROOT_DIR/.build/dmg-staging"
STAGED_APP="$STAGING_DIR/$APP_NAME.app"
FRAMEWORKS_DIR="$STAGED_APP/Contents/Frameworks"
EXECUTABLE="$STAGED_APP/Contents/MacOS/$APP_NAME"
DMG_PATH="$DIST_DIR/$DMG_NAME"

ROCKSDB_LIB="/opt/homebrew/opt/rocksdb/lib/librocksdb.11.dylib"
GFLAGS_LIB="/opt/homebrew/opt/gflags/lib/libgflags.2.3.dylib"
SNAPPY_LIB="/opt/homebrew/opt/snappy/lib/libsnappy.1.dylib"
LZ4_LIB="/opt/homebrew/opt/lz4/lib/liblz4.1.dylib"
ZSTD_LIB="/opt/homebrew/opt/zstd/lib/libzstd.1.dylib"

copy_dylib() {
  local source="$1"
  local destination="$FRAMEWORKS_DIR/$(basename "$source")"
  if [[ ! -f "$source" ]]; then
    echo "Missing dependency: $source" >&2
    exit 1
  fi
  cp -L "$source" "$destination"
  chmod u+w "$destination"
}

rewrite_dependency() {
  local binary="$1"
  local old_path="$2"
  local new_name="$3"
  install_name_tool -change "$old_path" "@executable_path/../Frameworks/$new_name" "$binary"
}

rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR" "$DIST_DIR"
cp -R "$APP_DIR" "$STAGED_APP"
mkdir -p "$FRAMEWORKS_DIR"

copy_dylib "$ROCKSDB_LIB"
copy_dylib "$GFLAGS_LIB"
copy_dylib "$SNAPPY_LIB"
copy_dylib "$LZ4_LIB"
copy_dylib "$ZSTD_LIB"

ROCKSDB_STAGED="$FRAMEWORKS_DIR/$(basename "$ROCKSDB_LIB")"
GFLAGS_STAGED="$FRAMEWORKS_DIR/$(basename "$GFLAGS_LIB")"
SNAPPY_STAGED="$FRAMEWORKS_DIR/$(basename "$SNAPPY_LIB")"
LZ4_STAGED="$FRAMEWORKS_DIR/$(basename "$LZ4_LIB")"
ZSTD_STAGED="$FRAMEWORKS_DIR/$(basename "$ZSTD_LIB")"

install_name_tool -id "@executable_path/../Frameworks/$(basename "$ROCKSDB_LIB")" "$ROCKSDB_STAGED"
install_name_tool -id "@executable_path/../Frameworks/$(basename "$GFLAGS_LIB")" "$GFLAGS_STAGED"
install_name_tool -id "@executable_path/../Frameworks/$(basename "$SNAPPY_LIB")" "$SNAPPY_STAGED"
install_name_tool -id "@executable_path/../Frameworks/$(basename "$LZ4_LIB")" "$LZ4_STAGED"
install_name_tool -id "@executable_path/../Frameworks/$(basename "$ZSTD_LIB")" "$ZSTD_STAGED"

rewrite_dependency "$EXECUTABLE" "$ROCKSDB_LIB" "$(basename "$ROCKSDB_LIB")"
rewrite_dependency "$ROCKSDB_STAGED" "$GFLAGS_LIB" "$(basename "$GFLAGS_LIB")"
rewrite_dependency "$ROCKSDB_STAGED" "$SNAPPY_LIB" "$(basename "$SNAPPY_LIB")"
rewrite_dependency "$ROCKSDB_STAGED" "$LZ4_LIB" "$(basename "$LZ4_LIB")"
rewrite_dependency "$ROCKSDB_STAGED" "$ZSTD_LIB" "$(basename "$ZSTD_LIB")"

ln -s /Applications "$STAGING_DIR/Applications"

codesign --force --sign - "$FRAMEWORKS_DIR"/*.dylib >/dev/null
codesign --force --deep --sign - "$STAGED_APP" >/dev/null
codesign --verify --deep --strict --verbose=2 "$STAGED_APP" >&2

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

echo "$DMG_PATH"
