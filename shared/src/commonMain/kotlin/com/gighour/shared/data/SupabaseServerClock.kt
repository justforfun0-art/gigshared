package com.gighour.shared.data

import com.gighour.shared.util.Logger
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import kotlin.concurrent.Volatile
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant
import kotlinx.datetime.LocalDate
import kotlinx.datetime.LocalDateTime
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull

/**
 * Multiplatform [ServerClock] — port of Gigand's ServerTimeService. The whole
 * offset mechanism was already platform-agnostic (a Supabase RPC + arithmetic),
 * so this lives in commonMain and serves BOTH Android and iOS; only java.time →
 * kotlinx-datetime and System.currentTimeMillis → Clock.System changed.
 *
 * ANTI-TAMPER CONTRACT (project_server_time_no_device_fallback): the returned
 * time is server time, computed as `deviceClock + cachedOffset`, where the
 * offset was measured against the server at sync. The device clock is only the
 * tick source between syncs — a user moving it forward moves both terms, so the
 * derived server time is unaffected. Crucially: when NOT synced, the throwing
 * accessors throw and the OrNull accessors return null — we NEVER fabricate a
 * device-clock time. Callers block (awaitSync) or show a warning.
 */
class SupabaseServerClock(
    private val supabaseClient: SupabaseClient,
) : ServerClock {

    private val kolkata = TimeZone.of("Asia/Kolkata")
    private val mutex = Mutex()

    @Volatile private var offsetMillis: Long = 0L
    @Volatile private var isCached: Boolean = false

    private val _isSynced = MutableStateFlow(false)
    val isSynced: StateFlow<Boolean> = _isSynced.asStateFlow()

    /**
     * Fetch server time via the `get_server_time` RPC and cache the
     * device↔server offset (round-trip midpoint reduces latency bias, matching
     * web). Returns true on success; never throws — a failed sync preserves any
     * previously-cached offset.
     */
    suspend fun syncServerTime(): Boolean = mutex.withLock {
        try {
            val deviceBefore = Clock.System.now().toEpochMilliseconds()
            val result = supabaseClient.postgrest.rpc("get_server_time")
            val deviceAfter = Clock.System.now().toEpochMilliseconds()

            val serverInstant = parseServerTime(result.data) ?: run {
                Logger.e(TAG, "syncServerTime: unparseable payload ${result.data}")
                return@withLock false
            }
            val deviceMid = (deviceBefore + deviceAfter) / 2
            offsetMillis = serverInstant.toEpochMilliseconds() - deviceMid
            isCached = true
            _isSynced.value = true
            true
        } catch (e: Exception) {
            Logger.e(TAG, "syncServerTime failed: ${e.message}")
            false
        }
    }

    /** RPC returns a single timestamptz, usually a JSON string literal. */
    private fun parseServerTime(raw: String): Instant? {
        val trimmed = raw.trim()
        if (trimmed.isEmpty() || trimmed == "null") return null
        val iso = runCatching {
            when (val el = Json.parseToJsonElement(trimmed)) {
                is JsonPrimitive -> el.contentOrNull
                else -> firstStringValue(el.toString())
            }
        }.getOrNull() ?: trimmed.trim('"')
        return iso?.let { runCatching { Instant.parse(it) }.getOrNull() }
    }

    private fun firstStringValue(text: String): String? {
        val start = text.indexOf('"')
        if (start == -1) return null
        val end = text.indexOf('"', start + 1)
        if (end == -1) return null
        return text.substring(start + 1, end)
    }

    private fun nowInstantOrNull(): Instant? =
        if (isCached) Instant.fromEpochMilliseconds(Clock.System.now().toEpochMilliseconds() + offsetMillis) else null

    private fun nowInstant(): Instant =
        nowInstantOrNull() ?: throw ServerTimeUnavailableException()

    fun isOffsetCached(): Boolean = isCached

    // ---- ServerClock ----

    override suspend fun awaitSync() {
        if (isCached) return
        if (!syncServerTime()) {
            // Block until some sync (e.g. a retry loop elsewhere) lands; the
            // StateFlow flips true exactly once cached.
            _isSynced.first { it }
        }
    }

    override suspend fun serverToday(): LocalDate =
        nowInstant().toLocalDateTime(kolkata).date

    override suspend fun serverNowInIndia(): LocalDateTime =
        nowInstant().toLocalDateTime(kolkata)

    override suspend fun serverNowInIndiaOrNull(): LocalDateTime? =
        nowInstantOrNull()?.toLocalDateTime(kolkata)

    override suspend fun serverNowMillis(): Long =
        nowInstant().toEpochMilliseconds()

    override suspend fun serverNowMillisOrNull(): Long? =
        nowInstantOrNull()?.toEpochMilliseconds()

    companion object {
        private const val TAG = "ServerClock"
    }
}

/** Thrown by the non-null [SupabaseServerClock] accessors before the first sync. */
class ServerTimeUnavailableException(
    message: String = "Server time has not been synced yet",
) : Exception(message)
