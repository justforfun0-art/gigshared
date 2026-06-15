package com.gighour.shared.domain.repository

import com.gighour.shared.domain.model.EmployerPaymentSummary
import com.gighour.shared.domain.model.PaymentOrder
import com.gighour.shared.domain.model.PaymentVerifyResult

interface PaymentRepository {

    suspend fun createOrder(
        applicationId: String,
        amount: Double,
        employerId: String,
        employeeId: String,
        customerName: String,
        customerPhone: String,
        customerEmail: String? = null
    ): Result<PaymentOrder>

    suspend fun verifyPayment(orderId: String): Result<PaymentVerifyResult>

    /**
     * Loads every payment row (pending + completed) for an employer in one
     * query against the `employer_payment_summary` view. Replaces the old
     * applications → per-row work_sessions fetch loop.
     */
    suspend fun getEmployerPaymentSummary(employerId: String): Result<List<EmployerPaymentSummary>>
}
