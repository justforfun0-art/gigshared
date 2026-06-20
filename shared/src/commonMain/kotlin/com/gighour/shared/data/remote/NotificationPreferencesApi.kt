package com.gighour.shared.data.remote

import io.ktor.client.call.body
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Ktor port of Gigand's Retrofit NotificationPreferencesApi. Single upsert route
 * `secure/notification-preferences`; the server returns the saved preferences.
 */
open class NotificationPreferencesApi(private val client: ApiClient) {

    open suspend fun upsert(request: NotificationPreferencesRequest): NotificationPreferencesResponse {
        val resp = client.http.post(client.urlFor("secure/notification-preferences")) {
            client.applyAuth(this)
            setBody(request)
        }
        client.captureRotatedSbToken(resp)
        return resp.body()
    }
}

@Serializable
data class NotificationPreferencesRequest(
    @SerialName("push_enabled") val pushEnabled: Boolean? = null,
    @SerialName("in_app_enabled") val inAppEnabled: Boolean? = null,
    @SerialName("whatsapp_enabled") val whatsappEnabled: Boolean? = null,
    @SerialName("email_enabled") val emailEnabled: Boolean? = null,
    @SerialName("job_alerts_enabled") val jobAlertsEnabled: Boolean? = null,
    @SerialName("application_updates_enabled") val applicationUpdatesEnabled: Boolean? = null,
    @SerialName("payment_updates_enabled") val paymentUpdatesEnabled: Boolean? = null,
    @SerialName("messages_enabled") val messagesEnabled: Boolean? = null,
    @SerialName("marketing_enabled") val marketingEnabled: Boolean? = null,
)

@Serializable
data class NotificationPreferencesResponse(
    val preferences: NotificationPreferencesData? = null,
    val error: String? = null,
)

@Serializable
data class NotificationPreferencesData(
    val id: String? = null,
    @SerialName("user_id") val userId: String? = null,
    @SerialName("push_enabled") val pushEnabled: Boolean = true,
    @SerialName("in_app_enabled") val inAppEnabled: Boolean = true,
    @SerialName("whatsapp_enabled") val whatsappEnabled: Boolean = true,
    @SerialName("email_enabled") val emailEnabled: Boolean = false,
    @SerialName("job_alerts_enabled") val jobAlertsEnabled: Boolean = true,
    @SerialName("application_updates_enabled") val applicationUpdatesEnabled: Boolean = true,
    @SerialName("payment_updates_enabled") val paymentUpdatesEnabled: Boolean = true,
    @SerialName("messages_enabled") val messagesEnabled: Boolean = true,
    @SerialName("marketing_enabled") val marketingEnabled: Boolean = false,
)
