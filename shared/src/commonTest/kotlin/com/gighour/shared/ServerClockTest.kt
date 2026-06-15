package com.gighour.shared

import com.gighour.shared.data.ServerTimeUnavailableException
import com.gighour.shared.data.SupabaseServerClock
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.postgrest.Postgrest
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull

class ServerClockTest {

    private fun clock() = SupabaseServerClock(
        createSupabaseClient("https://x.supabase.co", "anon") { install(Postgrest) },
    )

    /**
     * The anti-tamper invariant (project_server_time_no_device_fallback): before
     * a successful sync, the OrNull accessors must return null and the throwing
     * ones must throw — NEVER fabricate a device-clock time.
     */
    @Test
    fun beforeSync_orNull_isNull_and_throwing_throws() = runTest {
        val c = clock()
        assertFalse(c.isOffsetCached())
        assertNull(c.serverNowMillisOrNull())
        assertNull(c.serverNowInIndiaOrNull())
        assertFailsWith<ServerTimeUnavailableException> { c.serverNowMillis() }
        assertFailsWith<ServerTimeUnavailableException> { c.serverNowInIndia() }
        assertFailsWith<ServerTimeUnavailableException> { c.serverToday() }
    }
}
