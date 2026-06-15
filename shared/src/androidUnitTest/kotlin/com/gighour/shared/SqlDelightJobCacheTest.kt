package com.gighour.shared

import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import com.gighour.shared.data.local.db.SqlDelightJobCache
import com.gighour.shared.db.GighourDb
import com.gighour.shared.domain.model.Job
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Exercises SqlDelightJobCache against an in-memory JVM SQLite DB (this test set
 * runs on the Android target's JVM). Verifies the lossless JSON round-trip,
 * is_active filtering, LIKE search, and the cleanup. Lives in androidUnitTest
 * because the JDBC driver is JVM-only; the cache code itself is commonMain.
 */
class SqlDelightJobCacheTest {

    private fun newCache(): SqlDelightJobCache {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        GighourDb.Schema.create(driver)
        return SqlDelightJobCache(GighourDb(driver), ioDispatcher = Dispatchers.Unconfined)
    }

    private fun job(
        id: String,
        title: String = "Cook",
        active: Boolean = true,
        skills: List<String> = listOf("a, b with comma", "c"),
    ) = Job(
        id = id,
        employerId = "e1",
        title = title,
        description = "desc $title",
        location = "L",
        isActive = active,
        createdAt = "2026-06-${id.takeLast(2).padStart(2, '0')}",
        skillsRequired = skills,
    )

    @Test
    fun upsert_then_getById_and_getAll_roundTrips_losslessly() = runTest {
        val cache = newCache()
        val j = job("01", skills = listOf("welding, advanced", "lifting"))
        cache.upsertAll(listOf(j), cachedAtMillis = 1000)

        val byId = cache.getById("01")
        assertEquals(j, byId) // full lossless round-trip incl. comma-containing skill
        // Gigand's Room comma-join would have split "welding, advanced" — we don't.
        assertTrue(byId!!.skillsRequired.contains("welding, advanced"))

        assertEquals(1, cache.getAll().size)
        assertNull(cache.getById("missing"))
    }

    @Test
    fun getAll_excludesInactive_andOrdersByCreatedDesc() = runTest {
        val cache = newCache()
        cache.upsertAll(
            listOf(job("01"), job("03"), job("02", active = false)),
            cachedAtMillis = 1,
        )
        val all = cache.getAll()
        assertEquals(2, all.size) // inactive excluded
        assertEquals(listOf("03", "01"), all.map { it.id }) // created_at DESC
    }

    @Test
    fun search_matchesTitleOrDescription() = runTest {
        val cache = newCache()
        cache.upsertAll(listOf(job("01", title = "Welder"), job("02", title = "Cook")), cachedAtMillis = 1)
        assertEquals(listOf("01"), cache.search("weld").map { it.id })
        assertEquals(2, cache.search("desc").size) // matches description on both
    }

    @Test
    fun deleteOlderThan_andClear() = runTest {
        val cache = newCache()
        cache.upsertAll(listOf(job("01")), cachedAtMillis = 100)
        cache.upsertAll(listOf(job("02")), cachedAtMillis = 5000)
        cache.deleteOlderThan(1000)
        assertEquals(listOf("02"), cache.getAll().map { it.id })
        cache.clear()
        assertTrue(cache.getAll().isEmpty())
    }
}
