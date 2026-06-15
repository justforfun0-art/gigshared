package com.gighour.shared.data.local.db

import app.cash.sqldelight.db.SqlDriver
import com.gighour.shared.db.GighourDb

/**
 * Per-platform SQLDelight driver. Android needs a Context to open the DB, so the
 * actual is a class with a constructor; iOS uses the in-process native driver.
 */
expect class DriverFactory {
    fun createDriver(): SqlDriver
}

/** Builds the generated [GighourDb] from a platform [DriverFactory]. */
fun createGighourDb(factory: DriverFactory): GighourDb = GighourDb(factory.createDriver())
