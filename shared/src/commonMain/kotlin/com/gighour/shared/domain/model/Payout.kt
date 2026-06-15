package com.gighour.shared.domain.model

data class Payout(
    val id: String,
    val amount: Double,
    val currency: String,
    val payoutMode: String?,
    val status: PayoutStatus,
    val utr: String?,
    val failureReason: String?,
    val scheduledFor: String?,
    val createdAt: String?,
    val processedAt: String?,
    val completedAt: String?,
    val jobTitle: String?,
    val beneficiary: PayoutBeneficiary?
)

data class PayoutBeneficiary(
    val type: AccountType?,
    val name: String?,
    val bankName: String?,
    val upiId: String?
)

data class PayoutSummary(
    val totalPayouts: Int = 0,
    val totalAmount: Double = 0.0,
    val pendingAmount: Double = 0.0,
    val scheduledCount: Int = 0,
    val processingCount: Int = 0,
    val successCount: Int = 0,
    val failedCount: Int = 0
)

data class PayoutPage(
    val payouts: List<Payout>,
    val summary: PayoutSummary,
    val hasMore: Boolean
)

enum class PayoutStatus {
    SCHEDULED, PROCESSING, SUCCESS, FAILED, REVERSED, CANCELLED, UNKNOWN;

    companion object {
        fun fromString(value: String?): PayoutStatus = when (value?.uppercase()) {
            "SCHEDULED" -> SCHEDULED
            "PROCESSING" -> PROCESSING
            "SUCCESS" -> SUCCESS
            "FAILED" -> FAILED
            "REVERSED" -> REVERSED
            "CANCELLED" -> CANCELLED
            else -> UNKNOWN
        }
    }
}
