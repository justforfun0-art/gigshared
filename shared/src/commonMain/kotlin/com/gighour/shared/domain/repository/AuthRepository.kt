package com.gighour.shared.domain.repository

import com.gighour.shared.domain.model.AuthData
import kotlinx.coroutines.flow.Flow

interface AuthRepository {
    suspend fun sendOtp(phone: String): Result<OtpSendResult>
    suspend fun verifyOtp(phone: String, otp: String): Result<AuthData>
    suspend fun logout()
    fun getAuthState(): Flow<AuthData?>
    suspend fun getToken(): String?
    suspend fun getUserId(): String?
    suspend fun updateUserType(userType: String)
    suspend fun setProfileComplete(isComplete: Boolean)
    suspend fun refreshSupabaseToken(): String?

    /**
     * True when a Supabase access token is already cached in memory (restored
     * from a previous session). Lets callers skip awaiting a fresh token mint
     * on app restart, while still gating the first RLS-bound query on a fresh
     * login — where no token exists yet and querying early returns 0 rows.
     */
    fun hasCachedSupabaseToken(): Boolean
}

data class OtpSendResult(
    val success: Boolean,
    val method: String,
    val message: String? = null,
    val error: String? = null,
    val retryAfter: Int? = null,
    val fallbackAvailable: Boolean = false
)
