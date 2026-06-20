package com.gighour.shared.data.repository

import com.gighour.shared.domain.repository.PushTokenRepository
import com.gighour.shared.util.Logger
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import kotlinx.datetime.Clock
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Upserts the device push token into `user_fcm_tokens`, mirroring Android's
 * GigHourMessagingService.sendTokenToBackend. One row per (user_id, platform).
 */
class PushTokenRepositoryImpl(
    private val supabaseClient: SupabaseClient,
) : PushTokenRepository {

    override suspend fun registerToken(userId: String, token: String, platform: String): Result<Unit> {
        return try {
            supabaseClient.from("user_fcm_tokens").upsert(
                FcmTokenRow(
                    userId = userId,
                    fcmToken = token,
                    platform = platform,
                    isValid = true,
                    updatedAt = Clock.System.now().toString(),
                ),
            ) {
                onConflict = "user_id,platform"
            }
            Result.success(Unit)
        } catch (e: Exception) {
            Logger.e(TAG, "registerToken failed", e)
            Result.failure(e)
        }
    }

    @Serializable
    private data class FcmTokenRow(
        @SerialName("user_id") val userId: String,
        @SerialName("fcm_token") val fcmToken: String,
        val platform: String,
        @SerialName("is_valid") val isValid: Boolean = true,
        @SerialName("updated_at") val updatedAt: String,
    )

    private companion object {
        const val TAG = "PushTokenRepo"
    }
}
