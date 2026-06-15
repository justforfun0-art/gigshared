package com.gighour.shared.data.repository

import com.gighour.shared.data.local.SessionStore
import com.gighour.shared.data.remote.CreateOrderRequest
import com.gighour.shared.data.remote.PaymentsApi
import com.gighour.shared.domain.model.EmployerPaymentSummary
import com.gighour.shared.domain.model.PaymentOrder
import com.gighour.shared.domain.model.PaymentVerifyResult
import com.gighour.shared.domain.repository.PaymentRepository
import com.gighour.shared.util.Logger
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.datetime.Clock

/**
 * KMP port of Gigand's PaymentRepositoryImpl. AuthPreferences → [SessionStore];
 * Retrofit PaymentsApi → Ktor [PaymentsApi]; System.currentTimeMillis →
 * kotlinx.datetime.Clock; SecurityException → IllegalStateException.
 *
 * PRESERVED FROM THE PAYMENT AUDIT (do not loosen — project_payment_flow_audit):
 *  - verifyPayment gates STRICTLY on order_status == PAID (NOT `|| paymentStatus
 *    == SUCCESS`), matching the web callback — a looser gate could mark a job
 *    COMPLETED before the order fully settles;
 *  - getEmployerPaymentSummary enforces session==requested employer id;
 *  - phone normalized to the last 10 digits; email validated/synthesized.
 */
class PaymentRepositoryImpl(
    private val paymentsApi: PaymentsApi,
    private val supabaseClient: SupabaseClient,
    private val sessionStore: SessionStore,
) : PaymentRepository {

    override suspend fun createOrder(
        applicationId: String,
        amount: Double,
        employerId: String,
        employeeId: String,
        customerName: String,
        customerPhone: String,
        customerEmail: String?,
    ): Result<PaymentOrder> = runCatching {
        val orderId = generateOrderId(applicationId)
        // Server validates customerPhone as exactly 10 digits (no +91).
        val phoneDigits = customerPhone.filter { it.isDigit() }.takeLast(10)
        val email = customerEmail?.takeIf { it.isNotBlank() && EMAIL_REGEX.matches(it) }
            ?: "$phoneDigits@gighour.com"

        val result = paymentsApi.createOrder(
            CreateOrderRequest(
                orderId = orderId,
                orderAmount = amount,
                customerName = customerName,
                customerEmail = email,
                customerPhone = phoneDigits,
                applicationId = applicationId,
                employerId = employerId,
                employeeId = employeeId,
            )
        )

        if (!result.isSuccessful) {
            throw Exception(
                result.body.error?.takeIf { it.isNotBlank() }
                    ?: "Failed to create payment order (HTTP ${result.statusCode})"
            )
        }

        val body = result.body
        if (body.success != true) throw Exception(body.error ?: "Failed to create payment order")

        PaymentOrder(
            orderId = body.orderId ?: throw Exception("Invalid response: missing orderId"),
            paymentSessionId = body.paymentSessionId
                ?: throw Exception("Invalid response: missing paymentSessionId"),
            paymentLink = body.paymentLink
                ?: throw Exception("Invalid response: missing paymentLink"),
        )
    }

    override suspend fun verifyPayment(orderId: String): Result<PaymentVerifyResult> = runCatching {
        val result = paymentsApi.verifyOrder(orderId)

        if (!result.isSuccessful) {
            throw Exception(
                result.body.error?.takeIf { it.isNotBlank() }
                    ?: "Failed to verify payment (HTTP ${result.statusCode})"
            )
        }

        val body = result.body
        val orderStatus = body.orderStatus
        val paymentStatus = body.paymentStatus
        // Gate STRICTLY on order_status == PAID, matching the web callback. A
        // looser `|| paymentStatus == SUCCESS` could mark a job COMPLETED before
        // the order fully settled — see project_payment_flow_audit.
        val isPaid = orderStatus.equals("PAID", ignoreCase = true)

        PaymentVerifyResult(
            success = isPaid,
            orderStatus = orderStatus,
            paymentStatus = paymentStatus,
            transactionId = body.cfPaymentId,
        )
    }

    override suspend fun getEmployerPaymentSummary(
        employerId: String,
    ): Result<List<EmployerPaymentSummary>> = runCatching {
        val sessionUserId = sessionStore.getUserId()
        if (sessionUserId != null && sessionUserId != employerId) {
            Logger.e(TAG, "getEmployerPaymentSummary: employerId mismatch — session=$sessionUserId requested=$employerId")
            throw IllegalStateException("Employer ID does not match authenticated session")
        }
        supabaseClient.from("employer_payment_summary")
            .select {
                filter { eq("employer_id", employerId) }
                order("work_session_updated_at", Order.DESCENDING)
            }
            .decodeList<EmployerPaymentSummary>()
    }

    private fun generateOrderId(applicationId: String): String {
        val timestamp = Clock.System.now().toEpochMilliseconds()
        val shortAppId = applicationId.take(8)
        return "ORD_${timestamp}_$shortAppId"
    }

    companion object {
        private const val TAG = "PaymentRepository"
        private val EMAIL_REGEX =
            Regex("^[a-zA-Z0-9._%+\\-]+@[a-zA-Z0-9.\\-]+\\.[a-zA-Z]{2,}$")
    }
}
