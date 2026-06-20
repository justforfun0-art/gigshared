package com.gighour.shared.domain.repository

import com.gighour.shared.domain.model.NotificationItem

data class NotificationsPage(
    val items: List<NotificationItem>,
    val hasMore: Boolean
)

/** The worker's notification-channel + category toggles (Android NotificationPreferences). */
data class NotificationPreferences(
    val pushEnabled: Boolean = true,
    val inAppEnabled: Boolean = true,
    val whatsappEnabled: Boolean = true,
    val emailEnabled: Boolean = false,
    val jobAlertsEnabled: Boolean = true,
    val applicationUpdatesEnabled: Boolean = true,
    val paymentUpdatesEnabled: Boolean = true,
    val messagesEnabled: Boolean = true,
    val marketingEnabled: Boolean = false,
)

interface NotificationRepository {
    suspend fun getNotifications(limit: Int = 20, offset: Int = 0): Result<NotificationsPage>
    suspend fun markAsRead(notificationId: String): Result<Unit>
    suspend fun markAllAsRead(): Result<Unit>
    suspend fun delete(notificationId: String): Result<Unit>

    /**
     * Upsert the worker's notification preferences (Android upsert pattern — the
     * server returns the saved set). [current] is the full desired state; any
     * field can change.
     */
    suspend fun saveNotificationPreferences(prefs: NotificationPreferences): Result<NotificationPreferences>
}
