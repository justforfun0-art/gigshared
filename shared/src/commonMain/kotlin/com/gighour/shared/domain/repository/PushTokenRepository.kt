package com.gighour.shared.domain.repository

/**
 * Registers a device's push token so the backend can deliver notifications.
 * iOS mirrors Android's `user_fcm_tokens` upsert (platform = "ios"); the server
 * send-path keys off this row regardless of platform.
 */
interface PushTokenRepository {
    suspend fun registerToken(userId: String, token: String, platform: String): Result<Unit>
}
