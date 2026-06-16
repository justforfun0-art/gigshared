package com.gighour.shared.data.remote

import io.ktor.client.call.body
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Ktor port of Gigand's AssistantApi — the Gemini-backed free-form fallback.
 * POST secure/assistant; the server enforces the daily free-tier cap.
 */
class AssistantApi(private val client: ApiClient) {

    suspend fun chat(request: AssistantChatRequest): AssistantChatResponse {
        val resp = client.http.post(client.urlFor("secure/assistant")) {
            client.applyAuth(this)
            setBody(request)
        }
        client.captureRotatedSbToken(resp)
        return resp.body()
    }
}

@Serializable
data class AssistantChatRequest(
    val message: String,
    val userType: String,
    val context: AssistantContext? = null,
)

@Serializable
data class AssistantContext(
    val name: String? = null,
    val location: String? = null,
    val activeApplications: Int? = null,
    val totalEarnings: Double? = null,
    val skills: List<String>? = null,
    val completedCount: Int? = null,
    val openJobs: Int? = null,
    val pendingApplicants: Int? = null,
    val thisMonthEarnings: Double? = null,
    val pendingPayments: Double? = null,
    val nextAction: String? = null,
)

@Serializable
data class AssistantChatResponse(
    val success: Boolean? = null,
    val reply: String? = null,
    val error: String? = null,
    val code: String? = null,
)
