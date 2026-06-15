package com.gighour.shared.domain.repository

import com.gighour.shared.domain.model.NotificationItem

data class NotificationsPage(
    val items: List<NotificationItem>,
    val hasMore: Boolean
)

interface NotificationRepository {
    suspend fun getNotifications(limit: Int = 20, offset: Int = 0): Result<NotificationsPage>
    suspend fun markAsRead(notificationId: String): Result<Unit>
    suspend fun markAllAsRead(): Result<Unit>
    suspend fun delete(notificationId: String): Result<Unit>
}
