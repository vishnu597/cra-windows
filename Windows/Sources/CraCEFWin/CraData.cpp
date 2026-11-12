// Another browser's and Cra's own Chromium data, for importing passwords and sign-ins
// (CraCEFWin.h, MARK: Stored data): DPAPI for the keys Chromium browsers wrap, and Windows' own
// SQLite (winsqlite3, in Windows since 10) for Login Data and Cookies. Nothing here touches CEF.
#include "CraCEFWin.h"

#include <windows.h>
#include <wincrypt.h>  // CryptUnprotectData (dpapi.h)
#include <winsqlite/winsqlite3.h>

#include <cstdlib>
#include <cstring>

uint8_t *cra_dpapi_unprotect(const uint8_t *data, size_t length, size_t *out_length) {
    if (out_length) *out_length = 0;
    if (!data || length == 0 || length > 0xFFFFFFFFu) return nullptr;
    DATA_BLOB in = {static_cast<DWORD>(length), const_cast<BYTE *>(data)};
    DATA_BLOB out = {0, nullptr};
    if (!CryptUnprotectData(&in, nullptr, nullptr, nullptr, nullptr, CRYPTPROTECT_UI_FORBIDDEN, &out)) return nullptr;
    uint8_t *copy = static_cast<uint8_t *>(std::malloc(out.cbData ? out.cbData : 1));
    if (copy) {
        std::memcpy(copy, out.pbData, out.cbData);
        if (out_length) *out_length = out.cbData;
    }
    SecureZeroMemory(out.pbData, out.cbData);
    LocalFree(out.pbData);
    return copy;
}

void cra_data_free(void *buffer) { std::free(buffer); }

static sqlite3 *DB(CraSQLite *db) { return reinterpret_cast<sqlite3 *>(db); }
static sqlite3_stmt *Statement(CraSQLiteStatement *s) { return reinterpret_cast<sqlite3_stmt *>(s); }

CraSQLite *cra_sqlite_open(const char *path, int create) {
    sqlite3 *db = nullptr;
    int flags = SQLITE_OPEN_READWRITE | (create ? SQLITE_OPEN_CREATE : 0);
    if (sqlite3_open_v2(path, &db, flags, nullptr) != SQLITE_OK) {
        sqlite3_close(db);
        return nullptr;
    }
    sqlite3_busy_timeout(db, 500);
    return reinterpret_cast<CraSQLite *>(db);
}

void cra_sqlite_close(CraSQLite *db) { sqlite3_close(DB(db)); }

int cra_sqlite_exec(CraSQLite *db, const char *sql) {
    return sqlite3_exec(DB(db), sql, nullptr, nullptr, nullptr) == SQLITE_OK ? 1 : 0;
}

CraSQLiteStatement *cra_sqlite_prepare(CraSQLite *db, const char *sql) {
    sqlite3_stmt *statement = nullptr;
    if (sqlite3_prepare_v2(DB(db), sql, -1, &statement, nullptr) != SQLITE_OK) {
        sqlite3_finalize(statement);
        return nullptr;
    }
    return reinterpret_cast<CraSQLiteStatement *>(statement);
}

int cra_sqlite_step(CraSQLiteStatement *statement) {
    switch (sqlite3_step(Statement(statement))) {
    case SQLITE_ROW: return 1;
    case SQLITE_DONE: return 0;
    default: return -1;
    }
}

void cra_sqlite_finalize(CraSQLiteStatement *statement) { sqlite3_finalize(Statement(statement)); }
int cra_sqlite_column_count(CraSQLiteStatement *statement) { return sqlite3_column_count(Statement(statement)); }
const char *cra_sqlite_column_name(CraSQLiteStatement *statement, int column) { return sqlite3_column_name(Statement(statement), column); }
int cra_sqlite_column_type(CraSQLiteStatement *statement, int column) { return sqlite3_column_type(Statement(statement), column); }
int64_t cra_sqlite_column_int64(CraSQLiteStatement *statement, int column) { return sqlite3_column_int64(Statement(statement), column); }
double cra_sqlite_column_double(CraSQLiteStatement *statement, int column) { return sqlite3_column_double(Statement(statement), column); }
const char *cra_sqlite_column_text(CraSQLiteStatement *statement, int column) {
    return reinterpret_cast<const char *>(sqlite3_column_text(Statement(statement), column));
}
const void *cra_sqlite_column_blob(CraSQLiteStatement *statement, int column) { return sqlite3_column_blob(Statement(statement), column); }
int cra_sqlite_column_bytes(CraSQLiteStatement *statement, int column) { return sqlite3_column_bytes(Statement(statement), column); }

int cra_sqlite_bind_int64(CraSQLiteStatement *statement, int index, int64_t value) {
    return sqlite3_bind_int64(Statement(statement), index, value) == SQLITE_OK ? 1 : 0;
}
int cra_sqlite_bind_double(CraSQLiteStatement *statement, int index, double value) {
    return sqlite3_bind_double(Statement(statement), index, value) == SQLITE_OK ? 1 : 0;
}
int cra_sqlite_bind_text(CraSQLiteStatement *statement, int index, const char *value) {
    return sqlite3_bind_text(Statement(statement), index, value, -1, SQLITE_TRANSIENT) == SQLITE_OK ? 1 : 0;
}
int cra_sqlite_bind_blob(CraSQLiteStatement *statement, int index, const void *value, int length) {
    // A zero-length blob, not NULL: SQLite binds NULL for a null pointer.
    static const char empty = 0;
    return sqlite3_bind_blob(Statement(statement), index, length > 0 ? value : &empty, length, SQLITE_TRANSIENT) == SQLITE_OK ? 1 : 0;
}
int cra_sqlite_bind_null(CraSQLiteStatement *statement, int index) {
    return sqlite3_bind_null(Statement(statement), index) == SQLITE_OK ? 1 : 0;
}
