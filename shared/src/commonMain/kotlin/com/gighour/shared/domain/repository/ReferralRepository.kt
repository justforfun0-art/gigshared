package com.gighour.shared.domain.repository

interface ReferralRepository {
    suspend fun getReferralInfo(userId: String): Result<ReferralInfo>
}

data class ReferralInfo(
    val referralCode: String,
    val referralCount: Int
)
