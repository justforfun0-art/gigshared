package com.gighour.shared.data.remote

import io.ktor.client.call.body
import io.ktor.client.request.delete
import io.ktor.client.request.get
import io.ktor.client.request.parameter
import io.ktor.client.request.patch
import io.ktor.client.request.setBody
import kotlinx.serialization.Serializable

/**
 * Ktor port of Gigand's Retrofit NotificationsApi. Routes under
 * `secure/notifications`. The Retrofit @HTTP(DELETE, hasBody=false) maps to a
 * plain Ktor delete with the id/clearAll as query params.
 */
open class NotificationsApi(private val client: ApiClient) {

    open suspend fun getNotifications(limit: Int = 50, offset: Int = 0): NotificationsListResponse {
        val resp = client.http.get(client.urlFor("secure/notifications")) {
            client.applyAuth(this)
            parameter("limit", limit)
            parameter("offset", offset)
        }
        client.captureRotatedSbToken(resp)
        return resp.body()
    }

    suspend fun markAsRead(request: MarkReadRequest): NotificationsActionResponse {
        val resp = client.http.patch(client.urlFor("secure/notifications")) {
            client.applyAuth(this)
            setBody(request)
        }
        client.captureRotatedSbToken(resp)
        return resp.body()
    }

    suspend fun deleteNotification(notificationId: String): NotificationsActionResponse {
        val resp = client.http.delete(client.urlFor("secure/notifications")) {
            client.applyAuth(this)
            parameter("notificationId", notificationId)
        }
        client.captureRotatedSbToken(resp)
        return resp.body()
    }

    suspend fun clearAll(clearAll: Boolean = true): NotificationsActionResponse {
        val resp = client.http.delete(client.urlFor("secure/notifications")) {
            client.applyAuth(this)
            parameter("clearAll", clearAll)
        }
        client.captureRotatedSbToken(resp)
        return resp.body()
    }
}

@Serializable
data class NotificationsListResponse(
    val success: Boolean = false,
    val notifications: List<NotificationDto> = emptyList(),
    val hasMore: Boolean = false,
    val error: String? = null,
)

@Serializable
data class NotificationsActionResponse(
    val success: Boolean = false,
    val error: String? = null,
)

@Serializable
data class MarkReadRequest(
    val notificationIds: List<String>? = null,
    val markAllRead: Boolean? = null,
)

@Serializable
data class NotificationDto(
    val id: String,
    val user_id: String? = null,
    val type: String? = null,
    val title: String? = null,
    val message: String? = null,
    val related_id: String? = null,
    val action_url: String? = null,
    val is_read: Boolean = false,
    val read_at: String? = null,
    val created_at: String? = null,
)
