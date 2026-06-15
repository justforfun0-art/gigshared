package com.gighour.shared.data.remote

import io.ktor.client.call.body
import io.ktor.client.request.patch
import io.ktor.client.request.post
import io.ktor.client.request.put
import io.ktor.client.request.setBody
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Ktor port of Gigand's Retrofit MessagesApi. The Next.js secure routes run
 * side effects the direct Supabase inserts skip (push/in-app/WhatsApp
 * notifications + last_message_at), so sends go through here:
 *  - POST  secure/messages              → sendMessage
 *  - PUT   secure/messages              → getOrCreateConversation
 *  - PATCH secure/messages              → markAsRead
 *  - POST  secure/messages/contact-admin → contactAdmin
 */
class MessagesApi(private val client: ApiClient) {

    suspend fun sendMessage(request: SendMessageRequest): SendMessageResponse {
        val resp = client.http.post(client.urlFor("secure/messages")) {
            client.applyAuth(this)
            setBody(request)
        }
        client.captureRotatedSbToken(resp)
        return resp.body()
    }

    suspend fun getOrCreateConversation(request: CreateConversationRequest): CreateConversationResponse {
        val resp = client.http.put(client.urlFor("secure/messages")) {
            client.applyAuth(this)
            setBody(request)
        }
        client.captureRotatedSbToken(resp)
        return resp.body()
    }

    suspend fun markAsRead(request: MarkMessagesReadRequest): MarkMessagesReadResponse {
        val resp = client.http.patch(client.urlFor("secure/messages")) {
            client.applyAuth(this)
            setBody(request)
        }
        client.captureRotatedSbToken(resp)
        return resp.body()
    }

    suspend fun contactAdmin(request: ContactAdminRequest): ContactAdminResponse {
        val resp = client.http.post(client.urlFor("secure/messages/contact-admin")) {
            client.applyAuth(this)
            setBody(request)
        }
        client.captureRotatedSbToken(resp)
        return resp.body()
    }
}

@Serializable
data class SendMessageRequest(
    val conversationId: String,
    val receiverId: String,
    val message: String,
)

@Serializable
data class SendMessageResponse(
    val success: Boolean = false,
    val data: SendMessageData? = null,
    val error: String? = null,
)

@Serializable
data class SendMessageData(
    val id: String = "",
    @SerialName("conversation_id") val conversationId: String = "",
    @SerialName("sender_id") val senderId: String = "",
    @SerialName("receiver_id") val receiverId: String? = null,
    val message: String = "",
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("is_read") val isRead: Boolean = false,
)

@Serializable
data class CreateConversationRequest(
    val employerId: String,
    val employeeId: String,
    val jobId: String? = null,
)

@Serializable
data class CreateConversationResponse(
    val success: Boolean = false,
    val data: CreateConversationData? = null,
    val error: String? = null,
)

@Serializable
data class CreateConversationData(
    val id: String = "",
    @SerialName("employer_id") val employerId: String = "",
    @SerialName("employee_id") val employeeId: String = "",
    @SerialName("job_id") val jobId: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
)

@Serializable
data class MarkMessagesReadRequest(
    val conversationId: String,
)

@Serializable
data class MarkMessagesReadResponse(
    val success: Boolean = false,
    val error: String? = null,
)

@Serializable
data class ContactAdminRequest(
    val message: String,
)

@Serializable
data class ContactAdminResponse(
    @SerialName("conversation_id") val conversationId: String? = null,
    val error: String? = null,
)
