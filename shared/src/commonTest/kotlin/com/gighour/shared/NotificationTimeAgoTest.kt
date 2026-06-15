package com.gighour.shared

import com.gighour.shared.data.ServerClock
import com.gighour.shared.data.remote.NotificationDto
import com.gighour.shared.data.remote.NotificationsApi
import com.gighour.shared.data.remote.NotificationsListResponse
import com.gighour.shared.data.repository.NotificationRepositoryImpl
import com.gighour.shared.domain.model.NotificationType
import kotlinx.coroutines.test.runTest
import kotlinx.datetime.Instant
import kotlinx.datetime.LocalDate
import kotlinx.datetime.LocalDateTime
import kotlin.test.Test
import kotlin.test.assertEquals

class NotificationTimeAgoTest {

    // Fixed "now" = 2026-06-15T12:00:00Z
    private val nowMs = Instant.parse("2026-06-15T12:00:00Z").toEpochMilliseconds()

    private val clock = object : ServerClock {
        override suspend fun awaitSync() {}
        override suspend fun serverToday(): LocalDate = LocalDate(2026, 6, 15)
        override suspend fun serverNowInIndia(): LocalDateTime = LocalDateTime(2026, 6, 15, 17, 30)
        override suspend fun serverNowInIndiaOrNull(): LocalDateTime = serverNowInIndia()
        override suspend fun serverNowMillis(): Long = nowMs
        override suspend fun serverNowMillisOrNull(): Long = nowMs
    }

    private fun dto(type: String?, createdAt: String?) = NotificationDto(
        id = "n1", type = type, title = "t", message = "m", is_read = false, created_at = createdAt,
    )

    @Test
    fun getNotifications_mapsTimeAgoThresholds_andTypes() = runTest {
        val stubApi = StubNotificationsApi(
            NotificationsListResponse(
                success = true,
                hasMore = false,
                notifications = listOf(
                    dto("PAYMENT_RECEIVED", "2026-06-15T11:59:30Z"),  // 30s → Just now
                    dto("new_message", "2026-06-15T11:30:00Z"),       // 30m → 30m ago
                    dto("SELECTED", "2026-06-15T09:00:00Z"),          // 3h → 3h ago
                    dto("NEW_JOB", "2026-06-13T12:00:00Z"),           // 2d → 2d ago
                    dto("something_random", "2026-06-01T12:00:00Z"),  // 14d → 2w ago
                ),
            ),
        )
        val repo = NotificationRepositoryImpl(stubApi, clock)
        val page = repo.getNotifications(50, 0).getOrThrow()
        val items = page.items

        assertEquals("Just now", items[0].timeAgo)
        assertEquals(NotificationType.PAYMENT, items[0].type)

        assertEquals("30m ago", items[1].timeAgo)
        assertEquals(NotificationType.MESSAGE, items[1].type)

        assertEquals("3h ago", items[2].timeAgo)
        assertEquals(NotificationType.APPLICATION_STATUS, items[2].type)

        assertEquals("2d ago", items[3].timeAgo)
        assertEquals(NotificationType.JOB_APPLICATION, items[3].type)

        assertEquals("2w ago", items[4].timeAgo)
        assertEquals(NotificationType.SYSTEM, items[4].type)
    }
}

/** Stub that returns a canned list without touching the network. */
private class StubNotificationsApi(
    private val response: NotificationsListResponse,
) : NotificationsApi(client = stubClient()) {
    override suspend fun getNotifications(limit: Int, offset: Int): NotificationsListResponse = response
}

private fun stubClient() = com.gighour.shared.data.remote.ApiClient(
    com.gighour.shared.data.BackendConfig("https://x", "k", "https://x/api/"),
    object : com.gighour.shared.data.local.SecureTokenStore {
        override suspend fun getSupabaseToken(): String? = null
        override suspend fun setSupabaseToken(token: String?) {}
        override suspend fun getAuthToken(): String? = null
        override suspend fun setAuthToken(token: String?) {}
        override suspend fun getUserId(): String? = null
        override suspend fun hasCachedSupabaseToken(): Boolean = false
        override suspend fun clear() {}
    },
)
