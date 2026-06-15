package com.gighour.shared.data.repository

import com.gighour.shared.domain.repository.ReferralInfo
import com.gighour.shared.domain.repository.ReferralRepository
import com.gighour.shared.util.Logger
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Ported from Gigand (Supabase-only repo). android.util.Log → [Logger]; the
 * column projection, filter, and zero-defaults are unchanged.
 */
class ReferralRepositoryImpl(
    private val supabaseClient: SupabaseClient,
) : ReferralRepository {

    @Serializable
    private data class ReferralRow(
        @SerialName("referral_code") val referralCode: String? = null,
        @SerialName("referral_count") val referralCount: Int? = null,
    )

    override suspend fun getReferralInfo(userId: String): Result<ReferralInfo> {
        return try {
            val row = supabaseClient.from("users")
                .select(Columns.list("referral_code, referral_count")) {
                    filter { eq("user_id", userId) }
                    limit(1L)
                }
                .decodeSingleOrNull<ReferralRow>()
            Result.success(
                ReferralInfo(
                    referralCode = row?.referralCode.orEmpty(),
                    referralCount = row?.referralCount ?: 0,
                )
            )
        } catch (e: Exception) {
            Logger.e(TAG, "getReferralInfo failed", e)
            Result.failure(e)
        }
    }

    companion object {
        private const val TAG = "ReferralRepository"
    }
}
