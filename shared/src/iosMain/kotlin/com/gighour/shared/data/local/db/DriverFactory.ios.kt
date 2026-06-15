package com.gighour.shared.data.local.db

import app.cash.sqldelight.db.SqlDriver
import app.cash.sqldelight.driver.native.NativeSqliteDriver
import com.gighour.shared.db.GighourDb

actual class DriverFactory {
    actual fun createDriver(): SqlDriver =
        NativeSqliteDriver(GighourDb.Schema, "gighour_cache.db")
}
