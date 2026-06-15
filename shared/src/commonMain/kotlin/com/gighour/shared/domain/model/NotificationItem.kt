package com.gighour.shared.domain.model

/**
 * A single in-app notification row.
 *
 * In Gigand this currently lives inside the Compose UI file
 * (ui/shared/notifications/NotificationsScreen.kt) but it is a pure data class
 * with no Android deps, so it's hoisted into the shared domain layer here. When
 * Gigand's :app is wired to depend on :shared, the UI-local copy should be
 * deleted and this one imported instead (the grouping/formatting helpers in the
 * screen stay Android-side).
 */
data class NotificationItem(
    val id: String,
    val title: String,
    val message: String,
    val type: NotificationType,
    val isRead: Boolean,
    val timeAgo: String,
    val createdAt: String
)

enum class NotificationType {
    JOB_APPLICATION,
    APPLICATION_STATUS,
    PAYMENT,
    MESSAGE,
    SYSTEM
}
