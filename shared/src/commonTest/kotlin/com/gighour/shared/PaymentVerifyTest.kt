package com.gighour.shared

import com.gighour.shared.data.BackendConfig
import com.gighour.shared.data.local.SecureTokenStore
import com.gighour.shared.data.local.SessionStore
import com.gighour.shared.data.remote.ApiClient
import com.gighour.shared.data.remote.CreateOrderRequest
import com.gighour.shared.data.remote.CreateOrderResponse
import com.gighour.shared.data.remote.HttpResult
import com.gighour.shared.data.remote.PaymentsApi
import com.gighour.shared.data.remote.VerifyOrderResponse
import com.gighour.shared.data.repository.PaymentRepositoryImpl
import com.gighour.shared.domain.model.AuthData
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class PaymentVerifyTest {

    // A minimal SupabaseClient WITHOUT the Auth module — Auth's
    // SettingsSessionManager can't init in a plain JVM unit test. verifyPayment /
    // createOrder never touch this client, so postgrest-only is enough to satisfy
    // the ctor.
    private val supabase = io.github.jan.supabase.createSupabaseClient(
        supabaseUrl = "https://x.supabase.co",
        supabaseKey = "anon",
    ) {
        install(io.github.jan.supabase.postgrest.Postgrest)
    }

    private val session = object : SessionStore {
        override val authDataFlow: Flow<AuthData?> = MutableStateFlow(null)
        override suspend fun saveAuthData(authData: AuthData) {}
        override suspend fun updateUserType(userType: String) {}
        override suspend fun setProfileComplete(isComplete: Boolean) {}
        override suspend fun getToken(): String? = null
        override suspend fun getUserId(): String? = null
        override suspend fun getUserType(): String? = null
        override suspend fun getSupabaseToken(): String? = null
        override suspend fun setSupabaseToken(token: String?) {}
        override fun getCachedSupabaseToken(): String? = null
        override suspend fun clearAuthData() {}
    }

    private fun apiVerifying(result: HttpResult<VerifyOrderResponse>) =
        object : PaymentsApi(ApiClient(BackendConfig("https://x", "k", "https://x/api/"), object : SecureTokenStore {
            override suspend fun getSupabaseToken(): String? = null
            override suspend fun setSupabaseToken(token: String?) {}
            override suspend fun getAuthToken(): String? = null
            override suspend fun setAuthToken(token: String?) {}
            override suspend fun getUserId(): String? = null
            override suspend fun hasCachedSupabaseToken(): Boolean = false
            override suspend fun clear() {}
        })) {
            override suspend fun verifyOrder(orderId: String) = result
            override suspend fun createOrder(request: CreateOrderRequest) =
                HttpResult(200, true, CreateOrderResponse(success = true))
        }

    @Test
    fun verifyPayment_isPaid_onlyWhenOrderStatusPaid_notSuccessAlone() = runTest {
        // order_status == PAID → paid.
        val paid = PaymentRepositoryImpl(
            apiVerifying(HttpResult(200, true, VerifyOrderResponse(orderStatus = "PAID", paymentStatus = "SUCCESS", cfPaymentId = "cf1"))),
            supabase, session,
        ).verifyPayment("o1").getOrThrow()
        assertTrue(paid.success)
        assertEquals("cf1", paid.transactionId)

        // paymentStatus SUCCESS but order not yet PAID → MUST be false
        // (the loosened gate was the double-charge bug — project_payment_flow_audit).
        val notSettled = PaymentRepositoryImpl(
            apiVerifying(HttpResult(200, true, VerifyOrderResponse(orderStatus = "ACTIVE", paymentStatus = "SUCCESS"))),
            supabase, session,
        ).verifyPayment("o2").getOrThrow()
        assertFalse(notSettled.success)
    }

    @Test
    fun verifyPayment_nonSuccessHttp_fails() = runTest {
        val result = PaymentRepositoryImpl(
            apiVerifying(HttpResult(500, false, VerifyOrderResponse(error = "boom"))),
            supabase, session,
        ).verifyPayment("o3")
        assertTrue(result.isFailure)
        assertEquals("boom", result.exceptionOrNull()?.message)
    }
}
