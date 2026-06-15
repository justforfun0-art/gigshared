package com.gighour.shared.data

import kotlinx.datetime.LocalDate
import kotlinx.datetime.LocalDateTime

/**
 * Server-synced clock — the shared abstraction over Gigand's
 * ServerTimeService. The sync mechanism (NTP-ish handshake + the foreground
 * service that keeps it fresh) stays per-platform; only the *values* cross into
 * shared code.
 *
 * ANTI-TAMPER CONTRACT (carried over from project_server_time_no_device_fallback):
 * implementations must NEVER fall back to the device clock. The `…OrNull`
 * variants return null when not yet synced; the throwing/awaiting variants
 * block until synced. Repos use the OrNull variants on offline/cache paths so a
 * worker can't tamper their timing, and never silently trust device time.
 */
interface ServerClock {
    /** Suspend until the clock has synced with the server at least once. */
    suspend fun awaitSync()

    /** Today's date in India (Asia/Kolkata), after [awaitSync]. */
    suspend fun serverToday(): LocalDate

    /** Wall-clock now in India; throws/awaits if unsynced. */
    suspend fun serverNowInIndia(): LocalDateTime

    /** Wall-clock now in India, or null if not yet synced (never device time). */
    suspend fun serverNowInIndiaOrNull(): LocalDateTime?

    /** Server epoch millis, after [awaitSync]. Used for cache timestamping. */
    suspend fun serverNowMillis(): Long

    /**
     * Server epoch millis, or null if not yet synced. ONLY for display-only
     * relative-time formatting ("3h ago"), where the caller is permitted to
     * fall back to a device clock — never for anything that gates work timing,
     * payment, or expiry. Mirrors Gigand's serverNowMillisOrNull().
     */
    suspend fun serverNowMillisOrNull(): Long?
}
