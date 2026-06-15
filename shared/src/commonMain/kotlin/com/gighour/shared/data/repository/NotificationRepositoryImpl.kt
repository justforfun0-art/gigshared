package com.gighour.shared.data.repository

import com.gighour.shared.data.ServerClock
import com.gighour.shared.data.remote.MarkReadRequest
import com.gighour.shared.data.remote.NotificationDto
import com.gighour.shared.data.remote.NotificationsApi
import com.gighour.shared.domain.model.NotificationItem
import com.gighour.shared.domain.model.NotificationType
import com.gighour.shared.domain.repository.NotificationRepository
import com.gighour.shared.domain.repository.NotificationsPage
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant

/**
 * KMP port of Gigand's NotificationRepositoryImpl. Changes:
 *  - ServerTimeService → [ServerClock]; ui NotificationItem/Type → shared domain
 *    model copies (hoisted earlier in the repo-interface port).
 *  - java.text.SimpleDateFormat / java.util.* ISO parsing → kotlinx.datetime
 *    [Instant.parse] (ISO-8601, handles offset and 'Z'), with a couple of
 *    tolerant fixups for offset-less / fractional-second strings.
 *  - The time-ago thresholds and the type-mapping table are unchanged.
 *
 * Anti-tamper note preserved: getNotifications blocks on awaitSync() so a real
 * server time exists; but formatTimeAgo is display-only and MAY fall back to the
 * device clock ([ServerClock.serverNowMillisOrNull] → Clock.System), exactly as
 * the original allowed for relative-time strings.
 */
class NotificationRepositoryImpl(
    private val api: NotificationsApi,
    private val serverClock: ServerClock,
) : NotificationRepository {

    override suspend fun getNotifications(limit: Int, offset: Int): Result<NotificationsPage> = runCatching {
        // formatTimeAgo() reads the clock; block on sync rather than fall back to
        // device time for the fetch path.
        serverClock.awaitSync()
        val response = api.getNotifications(limit, offset)
        if (!response.success && response.error != null) error(response.error)
        NotificationsPage(
            items = response.notifications.map { it.toItem() },
            hasMore = response.hasMore,
        )
    }

    override suspend fun markAsRead(notificationId: String): Result<Unit> = runCatching {
        val response = api.markAsRead(MarkReadRequest(notificationIds = listOf(notificationId)))
        if (!response.success && response.error != null) error(response.error)
    }

    override suspend fun markAllAsRead(): Result<Unit> = runCatching {
        val response = api.markAsRead(MarkReadRequest(markAllRead = true))
        if (!response.success && response.error != null) error(response.error)
    }

    override suspend fun delete(notificationId: String): Result<Unit> = runCatching {
        val response = api.deleteNotification(notificationId)
        if (!response.success && response.error != null) error(response.error)
    }

    private suspend fun NotificationDto.toItem(): NotificationItem = NotificationItem(
        id = id,
        title = title.orEmpty(),
        message = message.orEmpty(),
        type = mapType(type),
        isRead = is_read,
        timeAgo = formatTimeAgo(created_at),
        createdAt = created_at.orEmpty(),
    )

    private fun mapType(raw: String?): NotificationType {
        if (raw == null) return NotificationType.SYSTEM
        val upper = raw.uppercase()
        return when {
            upper.contains("PAYMENT") || upper.contains("PAYOUT") -> NotificationType.PAYMENT
            upper.contains("MESSAGE") || upper.contains("CHAT") -> NotificationType.MESSAGE
            upper == "APPLIED" || upper.contains("JOB_MATCH") || upper.contains("NEW_JOB") ->
                NotificationType.JOB_APPLICATION
            upper in APPLICATION_STATUS_TYPES -> NotificationType.APPLICATION_STATUS
            else -> NotificationType.SYSTEM
        }
    }

    private suspend fun formatTimeAgo(iso: String?): String {
        if (iso.isNullOrBlank()) return ""
        val parsedMs = parseIsoMillis(iso) ?: return ""
        // Display-only: device-clock fallback is acceptable for relative time.
        val nowMs = serverClock.serverNowMillisOrNull() ?: Clock.System.now().toEpochMilliseconds()
        val deltaMs = nowMs - parsedMs
        if (deltaMs < 0) return "Just now"
        val seconds = deltaMs / 1000
        if (seconds < 60) return "Just now"
        val minutes = seconds / 60
        if (minutes < 60) return "${minutes}m ago"
        val hours = minutes / 60
        if (hours < 24) return "${hours}h ago"
        val days = hours / 24
        if (days < 7) return "${days}d ago"
        if (days < 30) return "${days / 7}w ago"
        if (days < 365) return "${days / 30}mo ago"
        return "${days / 365}y ago"
    }

    /**
     * Parse an ISO-8601 timestamp to epoch millis. kotlinx.datetime's
     * Instant.parse accepts offset and 'Z' forms; for the offset-less pattern
     * the server sometimes emits (no zone), assume UTC by appending 'Z'.
     */
    private fun parseIsoMillis(iso: String): Long? {
        runCatching { return Instant.parse(iso).toEpochMilliseconds() }
        // Offset-less "yyyy-MM-ddTHH:mm:ss[.SSS]" → treat as UTC.
        runCatching { return Instant.parse(iso + "Z").toEpochMilliseconds() }
        return null
    }

    private companion object {
        val APPLICATION_STATUS_TYPES = setOf(
            "SELECTED", "SHORTLISTED", "ACCEPTED", "REJECTED",
            "OTP_REQUESTED", "OTP_GENERATED",
            "WORK_IN_PROGRESS", "COMPLETION_PENDING", "PAYMENT_PENDING",
            "COMPLETED", "HIRED", "WITHDRAWN", "EXPIRED", "NO_SHOW",
        )
    }
}
