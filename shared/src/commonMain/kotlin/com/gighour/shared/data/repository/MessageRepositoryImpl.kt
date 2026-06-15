package com.gighour.shared.data.repository

import com.gighour.shared.data.remote.ContactAdminRequest
import com.gighour.shared.data.remote.CreateConversationRequest
import com.gighour.shared.data.remote.MessagesApi
import com.gighour.shared.data.remote.SendMessageRequest
import com.gighour.shared.domain.model.ConversationRow
import com.gighour.shared.domain.model.ConversationSummary
import com.gighour.shared.domain.model.MessageRow
import com.gighour.shared.domain.model.ParticipantInfo
import com.gighour.shared.domain.repository.MessageRepository
import com.gighour.shared.util.Logger
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.filter.FilterOperator
import io.github.jan.supabase.realtime.PostgresAction
import io.github.jan.supabase.realtime.channel
import io.github.jan.supabase.realtime.postgresChangeFlow
import io.github.jan.supabase.realtime.realtime
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.map
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * KMP port of Gigand's MessageRepository. Reads come straight from Supabase
 * (conversations / messages tables, RLS-scoped); sends go through the secure
 * API so notification side effects fire; new messages stream via realtime.
 */
class MessageRepositoryImpl(
    private val supabaseClient: SupabaseClient,
    private val messagesApi: MessagesApi,
) : MessageRepository {

    private val json = Json { ignoreUnknownKeys = true }

    override suspend fun getConversations(userId: String): Result<List<ConversationRow>> = try {
        val rows = supabaseClient.from("conversations")
            .select {
                filter {
                    or {
                        eq("employee_id", userId)
                        eq("employer_id", userId)
                    }
                }
            }
            .decodeList<ConversationRow>()
        Result.success(rows)
    } catch (e: Exception) {
        Result.failure(e)
    }

    override suspend fun getOrCreateConversation(
        employeeId: String,
        employerId: String,
        jobId: String?,
    ): Result<ConversationRow> {
        if (employeeId.isBlank() || employerId.isBlank() || employeeId == employerId) {
            return Result.failure(IllegalArgumentException("Invalid participants"))
        }
        return try {
            val response = messagesApi.getOrCreateConversation(
                CreateConversationRequest(employerId = employerId, employeeId = employeeId, jobId = jobId)
            )
            if (!response.success || response.data == null) {
                val fallback = findExistingConversation(employeeId, employerId, jobId)
                return if (fallback != null) Result.success(fallback)
                else Result.failure(IllegalStateException(response.error ?: "Failed to open conversation"))
            }
            val d = response.data!!
            Result.success(
                ConversationRow(
                    id = d.id, employeeId = d.employeeId, employerId = d.employerId,
                    jobId = d.jobId, createdAt = d.createdAt,
                )
            )
        } catch (e: Exception) {
            Logger.e(TAG, "getOrCreateConversation failed", e)
            val fallback = findExistingConversation(employeeId, employerId, jobId)
            if (fallback != null) Result.success(fallback) else Result.failure(e)
        }
    }

    private suspend fun findExistingConversation(
        employeeId: String, employerId: String, jobId: String?,
    ): ConversationRow? = try {
        supabaseClient.from("conversations")
            .select {
                filter {
                    eq("employee_id", employeeId)
                    eq("employer_id", employerId)
                    if (jobId != null) eq("job_id", jobId)
                }
                limit(1L)
            }
            .decodeList<ConversationRow>()
            .firstOrNull()
    } catch (e: Exception) {
        Logger.e(TAG, "findExistingConversation failed", e)
        null
    }

    override suspend fun getMessages(conversationId: String): Result<List<MessageRow>> = try {
        val rows = supabaseClient.from("messages")
            .select { filter { eq("conversation_id", conversationId) } }
            .decodeList<MessageRow>()
        Result.success(rows)
    } catch (e: Exception) {
        Result.failure(e)
    }

    override suspend fun sendMessage(
        conversationId: String, senderId: String, content: String, receiverId: String?,
    ): Result<MessageRow> = try {
        val resolved = receiverId ?: resolveReceiverId(conversationId, senderId)
            ?: return Result.failure(IllegalStateException("Couldn't resolve receiver for conversation"))
        val response = messagesApi.sendMessage(
            SendMessageRequest(conversationId = conversationId, receiverId = resolved, message = content)
        )
        if (!response.success || response.data == null) {
            Result.failure(IllegalStateException(response.error ?: "Failed to send message"))
        } else {
            val d = response.data!!
            Result.success(
                MessageRow(
                    id = d.id, conversationId = d.conversationId, senderId = d.senderId,
                    content = d.message, createdAt = d.createdAt, isRead = d.isRead,
                )
            )
        }
    } catch (e: Exception) {
        Logger.e(TAG, "sendMessage failed", e)
        Result.failure(e)
    }

    private suspend fun resolveReceiverId(conversationId: String, senderId: String): String? = try {
        val row = supabaseClient.from("conversations")
            .select { filter { eq("id", conversationId) }; limit(1L) }
            .decodeList<ConversationRow>()
            .firstOrNull()
        when (senderId) {
            row?.employeeId -> row.employerId
            row?.employerId -> row.employeeId
            else -> null
        }
    } catch (e: Exception) {
        Logger.e(TAG, "resolveReceiverId failed", e)
        null
    }

    override fun observeMessages(conversationId: String): Flow<MessageRow> = try {
        val channel = supabaseClient.channel("messages-$conversationId")
        channel.postgresChangeFlow<PostgresAction.Insert>(schema = "public") {
            table = "messages"
            filter("conversation_id", FilterOperator.EQ, conversationId)
        }.map { action ->
            json.decodeFromJsonElement(MessageRow.serializer(), action.record)
        }
    } catch (e: Exception) {
        Logger.e(TAG, "observeMessages failed: ${e.message}")
        emptyFlow()
    }

    override suspend fun getConversationSummaries(
        conversationIds: List<String>, viewerUserId: String,
    ): Map<String, ConversationSummary> {
        if (conversationIds.isEmpty()) return emptyMap()
        return try {
            val rows = supabaseClient.from("messages")
                .select(Columns.list("conversation_id, sender_id, message, created_at, is_read")) {
                    filter { isIn("conversation_id", conversationIds) }
                }
                .decodeList<MessageRow>()
            rows.groupBy { it.conversationId }.mapValues { (convId, msgs) ->
                val latest = msgs.maxByOrNull { it.createdAt ?: "" }
                ConversationSummary(
                    conversationId = convId,
                    lastMessage = latest?.content.orEmpty(),
                    lastMessageAt = latest?.createdAt,
                    unreadCount = msgs.count { !it.isRead && it.senderId != viewerUserId },
                )
            }
        } catch (e: Exception) {
            Logger.e(TAG, "getConversationSummaries failed", e)
            emptyMap()
        }
    }

    override suspend fun getParticipantInfo(userIds: List<String>): Map<String, ParticipantInfo> {
        if (userIds.isEmpty()) return emptyMap()
        val unique = userIds.toSet().toList()
        val out = mutableMapOf<String, ParticipantInfo>()
        try {
            supabaseClient.from("employee_profiles")
                .select(Columns.list("user_id, name, profile_photo_url")) {
                    filter { isIn("user_id", unique) }
                }
                .decodeList<ParticipantNameRow>()
                .forEach { row ->
                    val name = row.name?.takeIf { it.isNotBlank() } ?: return@forEach
                    out[row.userId] = ParticipantInfo(name, row.profilePhotoUrl?.takeIf { it.isNotBlank() })
                }
        } catch (e: Exception) {
            Logger.e(TAG, "getParticipantInfo(employee) failed", e)
        }
        val missing = unique.filter { it !in out }
        if (missing.isNotEmpty()) {
            try {
                supabaseClient.from("employer_profiles")
                    .select(Columns.list("user_id, company_name")) {
                        filter { isIn("user_id", missing) }
                    }
                    .decodeList<EmployerNameRow>()
                    .forEach { row ->
                        val name = row.companyName?.takeIf { it.isNotBlank() } ?: return@forEach
                        out[row.userId] = ParticipantInfo(name, null)
                    }
            } catch (e: Exception) {
                Logger.e(TAG, "getParticipantInfo(employer) failed", e)
            }
        }
        return out
    }

    override suspend fun contactAdmin(message: String): Result<String> = try {
        val response = messagesApi.contactAdmin(ContactAdminRequest(message = message))
        val conversationId = response.conversationId
        if (conversationId.isNullOrBlank()) {
            Result.failure(IllegalStateException(response.error ?: "Failed to send"))
        } else {
            Result.success(conversationId)
        }
    } catch (e: Exception) {
        Result.failure(e)
    }

    override suspend fun markAsRead(conversationId: String, userId: String) {
        try {
            supabaseClient.from("messages").update(mapOf("is_read" to true)) {
                filter {
                    eq("conversation_id", conversationId)
                    neq("sender_id", userId)
                    eq("is_read", false)
                }
            }
        } catch (_: Exception) {
        }
    }

    @Serializable
    private data class ParticipantNameRow(
        @SerialName("user_id") val userId: String,
        val name: String? = null,
        @SerialName("profile_photo_url") val profilePhotoUrl: String? = null,
    )

    @Serializable
    private data class EmployerNameRow(
        @SerialName("user_id") val userId: String,
        @SerialName("company_name") val companyName: String? = null,
    )

    private companion object {
        const val TAG = "MessageRepository"
    }
}
