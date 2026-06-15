package com.gighour.shared.domain.repository

import com.gighour.shared.domain.model.ConversationRow
import com.gighour.shared.domain.model.ConversationSummary
import com.gighour.shared.domain.model.MessageRow
import com.gighour.shared.domain.model.ParticipantInfo
import kotlinx.coroutines.flow.Flow

/** Messaging — conversations + chat between employee/employer (KMP port of Gigand's MessageRepository). */
interface MessageRepository {
    /** Conversations where [userId] is either participant. */
    suspend fun getConversations(userId: String): Result<List<ConversationRow>>

    /** Find or create the 1:1 conversation for this employee/employer(/job) tuple. */
    suspend fun getOrCreateConversation(
        employeeId: String,
        employerId: String,
        jobId: String? = null,
    ): Result<ConversationRow>

    suspend fun getMessages(conversationId: String): Result<List<MessageRow>>

    /** Send via the secure API (so notification side effects fire). receiverId derived if null. */
    suspend fun sendMessage(
        conversationId: String,
        senderId: String,
        content: String,
        receiverId: String? = null,
    ): Result<MessageRow>

    /** Live new-message inserts for a conversation (Supabase realtime). */
    fun observeMessages(conversationId: String): Flow<MessageRow>

    /** Per-conversation preview + unread count for the inbox list. */
    suspend fun getConversationSummaries(
        conversationIds: List<String>,
        viewerUserId: String,
    ): Map<String, ConversationSummary>

    /** Display name (+ avatar) for a batch of participant user-ids. */
    suspend fun getParticipantInfo(userIds: List<String>): Map<String, ParticipantInfo>

    /** Send a support message to the platform admin; returns the conversation id. */
    suspend fun contactAdmin(message: String): Result<String>

    /** Mark all messages NOT sent by [userId] in a conversation as read. */
    suspend fun markAsRead(conversationId: String, userId: String)
}
