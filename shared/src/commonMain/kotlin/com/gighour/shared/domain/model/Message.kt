package com.gighour.shared.domain.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** A 1:1 conversation between an employee and an employer (optionally per-job). */
@Serializable
data class ConversationRow(
    val id: String,
    @SerialName("employee_id") val employeeId: String,
    @SerialName("employer_id") val employerId: String,
    @SerialName("job_id") val jobId: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null,
)

/** One chat message row (the `message` column is exposed as [content]). */
@Serializable
data class MessageRow(
    val id: String = "",
    @SerialName("conversation_id") val conversationId: String = "",
    @SerialName("sender_id") val senderId: String = "",
    @SerialName("message") val content: String = "",
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("is_read") val isRead: Boolean = false,
)

/** Display name (+ optional avatar) for a conversation participant. */
data class ParticipantInfo(
    val name: String,
    val photoUrl: String? = null,
)

/**
 * Per-conversation summary for the inbox list: latest message preview, when it
 * was sent, and the unread count for the viewing user.
 */
data class ConversationSummary(
    val conversationId: String,
    val lastMessage: String,
    val lastMessageAt: String?,
    val unreadCount: Int,
)
