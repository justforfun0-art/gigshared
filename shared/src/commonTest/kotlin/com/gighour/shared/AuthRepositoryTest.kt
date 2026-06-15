package com.gighour.shared

import com.gighour.shared.data.BackendConfig
import com.gighour.shared.data.local.SecureTokenStore
import com.gighour.shared.data.local.SessionStore
import com.gighour.shared.data.remote.ApiClient
import com.gighour.shared.data.remote.AuthApi
import com.gighour.shared.data.remote.HttpResult
import com.gighour.shared.data.remote.SendOtpRequest
import com.gighour.shared.data.remote.SendOtpResponse
import com.gighour.shared.data.remote.SupabaseTokenResponse
import com.gighour.shared.data.remote.UserResponse
import com.gighour.shared.data.remote.VerifyOtpRequest
import com.gighour.shared.data.remote.VerifyOtpResponse
import com.gighour.shared.data.repository.AuthRepositoryImpl
import com.gighour.shared.domain.model.AuthData
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class AuthRepositoryTest {

    // ---- In-memory SessionStore ----
    private class FakeSessionStore : SessionStore {
        var saved: AuthData? = null
        var sbToken: String? = null
        override val authDataFlow: Flow<AuthData?> = MutableStateFlow(null)
        override suspend fun saveAuthData(authData: AuthData) { saved = authData }
        override suspend fun updateUserType(userType: String) {}
        override suspend fun setProfileComplete(isComplete: Boolean) {}
        override suspend fun getToken(): String? = saved?.token
        override suspend fun getUserId(): String? = saved?.userId
        override suspend fun getUserType(): String? = saved?.userType
        override suspend fun getSupabaseToken(): String? = sbToken
        override suspend fun setSupabaseToken(token: String?) { sbToken = token }
        override fun getCachedSupabaseToken(): String? = sbToken
        override suspend fun clearAuthData() { saved = null; sbToken = null }
    }

    private fun stubClient() = ApiClient(
        BackendConfig("https://x", "k", "https://x/api/"),
        object : SecureTokenStore {
            override suspend fun getSupabaseToken(): String? = null
            override suspend fun setSupabaseToken(token: String?) {}
            override suspend fun getAuthToken(): String? = null
            override suspend fun setAuthToken(token: String?) {}
            override suspend fun getUserId(): String? = null
            override suspend fun hasCachedSupabaseToken(): Boolean = false
            override suspend fun clear() {}
        },
    )

    private inner class FakeAuthApi(
        val sendResult: HttpResult<SendOtpResponse>? = null,
        val verifyResult: HttpResult<VerifyOtpResponse>? = null,
        val sbToken: String? = "sb-123",
    ) : AuthApi(stubClient()) {
        override suspend fun sendOtp(request: SendOtpRequest) = sendResult!!
        override suspend fun verifyOtp(request: VerifyOtpRequest) = verifyResult!!
        override suspend fun getSupabaseToken() = SupabaseTokenResponse(token = sbToken)
    }

    @Test
    fun verifyOtp_success_savesSessionAndMapsAuthData() = runTest {
        val store = FakeSessionStore()
        val api = FakeAuthApi(
            verifyResult = HttpResult(
                200, true,
                VerifyOtpResponse(
                    success = true,
                    token = "tok-1",
                    user = UserResponse("u1", "+910000000000", "EMPLOYEE", isNewUser = false),
                ),
            ),
        )
        val repo = AuthRepositoryImpl(api, store)
        val result = repo.verifyOtp("+910000000000", "123456")

        assertTrue(result.isSuccess)
        val data = result.getOrThrow()
        assertEquals("u1", data.userId)
        assertEquals("tok-1", data.token)
        assertTrue(data.isProfileComplete) // !isNewUser
        // Session was durably saved (the NonCancellable write).
        assertNotNull(store.saved)
        assertEquals("u1", store.saved!!.userId)
        // Best-effort sb-token refresh ran.
        assertEquals("sb-123", store.sbToken)
    }

    @Test
    fun verifyOtp_newUser_isProfileIncomplete() = runTest {
        val store = FakeSessionStore()
        val api = FakeAuthApi(
            verifyResult = HttpResult(
                200, true,
                VerifyOtpResponse(
                    success = true, token = "t",
                    user = UserResponse("u2", "+91", null, isNewUser = true),
                ),
            ),
        )
        val data = AuthRepositoryImpl(api, store).verifyOtp("+91", "1").getOrThrow()
        assertFalse(data.isProfileComplete)
    }

    @Test
    fun verifyOtp_400_surfacesServerMessage_elseFallback() = runTest {
        val store = FakeSessionStore()
        // Server provided an explicit error message.
        val withMsg = AuthRepositoryImpl(
            FakeAuthApi(verifyResult = HttpResult(400, false, VerifyOtpResponse(success = false, error = "Too many attempts"))),
            store,
        ).verifyOtp("+91", "0")
        assertTrue(withMsg.isFailure)
        assertEquals("Too many attempts", withMsg.exceptionOrNull()?.message)
        assertNull(store.saved) // nothing persisted on failure

        // No message + 400 → the canned OTP fallback string.
        val fallback = AuthRepositoryImpl(
            FakeAuthApi(verifyResult = HttpResult(400, false, VerifyOtpResponse(success = false))),
            FakeSessionStore(),
        ).verifyOtp("+91", "0")
        assertEquals("Invalid or expired OTP. Please try again.", fallback.exceptionOrNull()?.message)
    }

    @Test
    fun sendOtp_failureBody_surfacesRateLimitDetails() = runTest {
        val api = FakeAuthApi(
            sendResult = HttpResult(
                429, false,
                SendOtpResponse(success = false, method = "sms", error = "Rate limited", retryAfter = 60, fallbackAvailable = true),
            ),
        )
        val result = AuthRepositoryImpl(api, FakeSessionStore()).sendOtp("+91")
        // Gigand returns Result.success with a failed OtpSendResult carrying the details.
        assertTrue(result.isSuccess)
        val otp = result.getOrThrow()
        assertFalse(otp.success)
        assertEquals("Rate limited", otp.error)
        assertEquals(60, otp.retryAfter)
        assertTrue(otp.fallbackAvailable)
    }
}
