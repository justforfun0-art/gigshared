package com.gighour.shared.data.remote

import io.ktor.client.call.body
import io.ktor.client.request.get
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.http.isSuccess
import kotlinx.serialization.Serializable

/**
 * Ktor port of Gigand's Retrofit AuthApi. Routes `auth/otp/send`,
 * `auth/otp/verify`, `auth/sb-token`.
 *
 * Retrofit threw HttpException on non-2xx and the repo re-parsed errorBody().
 * Here ApiClient uses expectSuccess=false, so a 400/429 still returns a decodable
 * body — the API exposes the HTTP status alongside the parsed body
 * ([HttpResult]) so the repo can both read the server's error message AND
 * replicate the `code == 400 → "Invalid or expired OTP"` fallback.
 */
open class AuthApi(private val client: ApiClient) {

    open suspend fun sendOtp(request: SendOtpRequest): HttpResult<SendOtpResponse> {
        val resp = client.http.post(client.urlFor("auth/otp/send")) {
            client.applyAuth(this)
            setBody(request)
        }
        client.captureRotatedSbToken(resp)
        return HttpResult(resp.status.value, resp.status.isSuccess(), resp.body())
    }

    open suspend fun verifyOtp(request: VerifyOtpRequest): HttpResult<VerifyOtpResponse> {
        val resp = client.http.post(client.urlFor("auth/otp/verify")) {
            client.applyAuth(this)
            setBody(request)
        }
        client.captureRotatedSbToken(resp)
        return HttpResult(resp.status.value, resp.status.isSuccess(), resp.body())
    }

    open suspend fun getSupabaseToken(): SupabaseTokenResponse {
        val resp = client.http.get(client.urlFor("auth/sb-token")) {
            client.applyAuth(this)
        }
        client.captureRotatedSbToken(resp)
        return resp.body()
    }
}

/** A decoded body plus the HTTP status, so auth callers can branch on the code. */
data class HttpResult<T>(
    val statusCode: Int,
    val isSuccessful: Boolean,
    val body: T,
)

@Serializable
data class SupabaseTokenResponse(
    val token: String? = null,
)

@Serializable
data class SendOtpRequest(
    val phone: String,
)

@Serializable
data class SendOtpResponse(
    val success: Boolean = false,
    val method: String? = null,
    val message: String? = null,
    val error: String? = null,
    val retryAfter: Int? = null,
    val fallbackAvailable: Boolean? = null,
)

@Serializable
data class VerifyOtpRequest(
    val phone: String,
    val otp: String,
)

@Serializable
data class VerifyOtpResponse(
    val success: Boolean = false,
    val user: UserResponse? = null,
    val token: String? = null,
    val error: String? = null,
    val remainingAttempts: Int? = null,
)

@Serializable
data class UserResponse(
    val userId: String,
    val phone: String,
    val userType: String? = null,
    val isNewUser: Boolean = false,
)
