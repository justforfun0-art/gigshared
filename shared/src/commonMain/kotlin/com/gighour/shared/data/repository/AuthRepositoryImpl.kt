package com.gighour.shared.data.repository

import com.gighour.shared.data.local.SecureTokenStore
import com.gighour.shared.data.local.SessionStore
import com.gighour.shared.data.remote.AuthApi
import com.gighour.shared.data.remote.SendOtpRequest
import com.gighour.shared.data.remote.VerifyOtpRequest
import com.gighour.shared.domain.model.AuthData
import com.gighour.shared.domain.repository.AuthRepository
import com.gighour.shared.domain.repository.OtpSendResult
import com.gighour.shared.util.Logger
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.withContext

/**
 * KMP port of Gigand's AuthRepositoryImpl. AuthPreferences → [SessionStore];
 * Retrofit AuthApi → Ktor [AuthApi]; android.util.Log → [Logger].
 *
 * Transport change: Retrofit threw HttpException on non-2xx and the repo
 * re-parsed errorBody() with Gson. Ktor returns the decoded body even on
 * non-2xx (expectSuccess=false), so the rate-limit/error message is already in
 * `result.body` — we read it directly and use `result.statusCode` only for the
 * `400 → "Invalid or expired OTP"` fallback string.
 *
 * PRESERVED FROM THE AUTH AUDIT (do not remove):
 *  - verifyOtp saves the session inside withContext(NonCancellable): the
 *    caller's viewModelScope is torn down the moment verify succeeds and the
 *    OTP screen navigates away; a cancellable write could abort mid-commit,
 *    leaving the user "logged out" on next launch (project_employer_login_5554).
 *  - the post-save token refresh is best-effort and may be cancelled safely.
 */
class AuthRepositoryImpl(
    private val authApi: AuthApi,
    private val sessionStore: SessionStore,
    // The HTTP/Supabase layer reads its bearer + Supabase JWT from a SECOND
    // store (SecureTokenStore), separate from the SessionStore. verifyOtp must
    // populate it too, or every authenticated secure-API call (earnings,
    // payouts, dashboard stats) goes out with no token and returns empty.
    private val secureTokenStore: SecureTokenStore? = null,
) : AuthRepository {

    override suspend fun sendOtp(phone: String): Result<OtpSendResult> {
        return try {
            val result = authApi.sendOtp(SendOtpRequest(phone))
            val response = result.body
            if (response.success) {
                Result.success(
                    OtpSendResult(
                        success = true,
                        method = response.method ?: "whatsapp",
                        message = response.message,
                    )
                )
            } else {
                // Backend returns rate-limit details (e.g. 429) in the body —
                // surface that instead of dropping it as a generic failure.
                Result.success(
                    OtpSendResult(
                        success = false,
                        method = response.method ?: "whatsapp",
                        error = response.error ?: "Failed to send OTP",
                        retryAfter = response.retryAfter,
                        fallbackAvailable = response.fallbackAvailable ?: false,
                    )
                )
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    override suspend fun verifyOtp(phone: String, otp: String): Result<AuthData> {
        return try {
            val result = authApi.verifyOtp(VerifyOtpRequest(phone, otp))
            val response = result.body
            if (response.success && response.user != null && response.token != null) {
                val authData = AuthData(
                    userId = response.user.userId,
                    phone = response.user.phone,
                    userType = response.user.userType,
                    token = response.token,
                    isProfileComplete = !response.user.isNewUser,
                )
                // Persist inside NonCancellable — see class KDoc / audit note.
                withContext(NonCancellable) {
                    sessionStore.saveAuthData(authData)
                    // Also seed the SecureTokenStore the HTTP/Supabase layer reads
                    // from, so authenticated secure-API calls carry the bearer +
                    // user_id cookie (without this, earnings/payouts/dashboard
                    // come back empty).
                    secureTokenStore?.setAuthToken(response.token)
                    secureTokenStore?.setUserId(response.user.userId)
                }
                // Best-effort; the session is already durably saved above.
                refreshSupabaseToken()
                Result.success(authData)
            } else {
                // Wrong/expired OTP → 400 with {success:false,error:…}. Surface
                // the server message; fall back per status code as Gigand did.
                val message = response.error?.takeIf { it.isNotBlank() }
                    ?: if (result.statusCode == 400) "Invalid or expired OTP. Please try again."
                    else "Verification failed. Please try again."
                Result.failure(Exception(message))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    override suspend fun refreshSupabaseToken(): String? {
        return try {
            val token = authApi.getSupabaseToken().token
            sessionStore.setSupabaseToken(token)
            // Mirror into the SecureTokenStore the ApiClient/Supabase client read,
            // so PostgREST RLS (auth.uid()) resolves on user-scoped queries.
            secureTokenStore?.setSupabaseToken(token)
            token
        } catch (e: Exception) {
            Logger.e(TAG, "refreshSupabaseToken failed: ${e.message}")
            null
        }
    }

    override fun hasCachedSupabaseToken(): Boolean =
        !sessionStore.getCachedSupabaseToken().isNullOrBlank()

    override suspend fun logout() {
        sessionStore.clearAuthData()
        secureTokenStore?.clear()
    }

    override fun getAuthState(): Flow<AuthData?> = sessionStore.authDataFlow

    override suspend fun getToken(): String? = sessionStore.getToken()

    override suspend fun getUserId(): String? = sessionStore.getUserId()

    override suspend fun updateUserType(userType: String) = sessionStore.updateUserType(userType)

    override suspend fun setProfileComplete(isComplete: Boolean) =
        sessionStore.setProfileComplete(isComplete)

    companion object {
        private const val TAG = "AuthRepository"
    }
}
