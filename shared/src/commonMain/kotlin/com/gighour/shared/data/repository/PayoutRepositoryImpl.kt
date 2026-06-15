package com.gighour.shared.data.repository

import com.gighour.shared.data.remote.PayoutBeneficiaryDto
import com.gighour.shared.data.remote.PayoutDto
import com.gighour.shared.data.remote.PayoutSummaryDto
import com.gighour.shared.data.remote.PayoutsHistoryApi
import com.gighour.shared.domain.model.AccountType
import com.gighour.shared.domain.model.Payout
import com.gighour.shared.domain.model.PayoutBeneficiary
import com.gighour.shared.domain.model.PayoutPage
import com.gighour.shared.domain.model.PayoutStatus
import com.gighour.shared.domain.model.PayoutSummary
import com.gighour.shared.domain.repository.PayoutRepository

/**
 * KMP port of Gigand's PayoutRepositoryImpl (Retrofit → Ktor). Body-success
 * check replaces Response.isSuccessful (see BeneficiaryRepositoryImpl note).
 * The amount-string→Double parse, currency default, and DTO→domain mappings
 * are unchanged.
 */
class PayoutRepositoryImpl(
    private val payoutsHistoryApi: PayoutsHistoryApi,
) : PayoutRepository {

    override suspend fun getHistory(
        status: PayoutStatus?,
        limit: Int,
        offset: Int,
    ): Result<PayoutPage> = runCatching {
        val body = payoutsHistoryApi.history(
            status = status?.takeIf { it != PayoutStatus.UNKNOWN }?.name,
            limit = limit,
            offset = offset,
        )
        if (body.success == false) throw Exception(body.error ?: "Failed to load payouts")
        PayoutPage(
            payouts = body.payouts.map { it.toDomain() },
            summary = body.summary?.toDomain() ?: PayoutSummary(),
            hasMore = body.pagination?.hasMore ?: false,
        )
    }

    private fun PayoutDto.toDomain(): Payout = Payout(
        id = id,
        amount = amount?.toDoubleOrNull() ?: 0.0,
        currency = currency ?: "INR",
        payoutMode = payoutMode,
        status = PayoutStatus.fromString(status),
        utr = utr,
        failureReason = failureReason,
        scheduledFor = scheduledFor,
        createdAt = createdAt,
        processedAt = processedAt,
        completedAt = completedAt,
        jobTitle = jobTitle,
        beneficiary = beneficiary?.toDomain(),
    )

    private fun PayoutBeneficiaryDto.toDomain(): PayoutBeneficiary = PayoutBeneficiary(
        type = type?.let { AccountType.fromString(it) },
        name = name,
        bankName = bankName,
        upiId = upiId,
    )

    private fun PayoutSummaryDto.toDomain(): PayoutSummary = PayoutSummary(
        totalPayouts = totalPayouts,
        totalAmount = totalAmount,
        pendingAmount = pendingAmount,
        scheduledCount = scheduledCount,
        processingCount = processingCount,
        successCount = successCount,
        failedCount = failedCount,
    )
}
