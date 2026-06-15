package com.gighour.shared.data.remote

import io.ktor.client.call.body
import io.ktor.client.request.get
import io.ktor.client.request.parameter
import kotlinx.serialization.Serializable

/**
 * Ktor port of Gigand's Retrofit PayoutsHistoryApi. Route `payouts/history`.
 */
class PayoutsHistoryApi(private val client: ApiClient) {

    suspend fun history(
        status: String? = null,
        limit: Int = 50,
        offset: Int = 0,
    ): PayoutHistoryResponse {
        val resp = client.http.get(client.urlFor("payouts/history")) {
            client.applyAuth(this)
            status?.let { parameter("status", it) }
            parameter("limit", limit)
            parameter("offset", offset)
        }
        client.captureRotatedSbToken(resp)
        return resp.body()
    }
}

@Serializable
data class PayoutHistoryResponse(
    val success: Boolean? = null,
    val payouts: List<PayoutDto> = emptyList(),
    val summary: PayoutSummaryDto? = null,
    val pagination: PayoutPaginationDto? = null,
    val error: String? = null,
)

@Serializable
data class PayoutDto(
    val id: String,
    val amount: String? = null,
    val currency: String? = null,
    val payoutMode: String? = null,
    val status: String,
    val utr: String? = null,
    val failureReason: String? = null,
    val scheduledFor: String? = null,
    val createdAt: String? = null,
    val processedAt: String? = null,
    val completedAt: String? = null,
    val jobTitle: String? = null,
    val beneficiary: PayoutBeneficiaryDto? = null,
)

@Serializable
data class PayoutBeneficiaryDto(
    val type: String? = null,
    val name: String? = null,
    val bankName: String? = null,
    val upiId: String? = null,
)

@Serializable
data class PayoutSummaryDto(
    val totalPayouts: Int = 0,
    val totalAmount: Double = 0.0,
    val pendingAmount: Double = 0.0,
    val scheduledCount: Int = 0,
    val processingCount: Int = 0,
    val successCount: Int = 0,
    val failedCount: Int = 0,
)

@Serializable
data class PayoutPaginationDto(
    val limit: Int = 0,
    val offset: Int = 0,
    val hasMore: Boolean = false,
)
