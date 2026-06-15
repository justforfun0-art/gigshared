package com.gighour.shared.domain.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Row from the `employer_payment_summary` Postgres view. Pre-joins work
 * sessions, applications, jobs, employee profiles, and payment_intents so the
 * Payments tab can render every card + the 4-tile stats from a single query
 * (replaces the old N+1 application → work-session fetch loop).
 *
 * Mirrors what the webapp's `PaymentsPage` consumes; field names are kept
 * snake_case via [SerialName] so they round-trip through PostgREST directly.
 *
 * Status mapping in the UI:
 *   application_status == COMPLETED → "Paid" (green)
 *   anything else                   → "Pending" (amber)
 */
@Serializable
data class EmployerPaymentSummary(
    @SerialName("work_session_id") val workSessionId: String? = null,
    @SerialName("application_id") val applicationId: String,
    @SerialName("job_id") val jobId: String? = null,
    @SerialName("employee_id") val employeeId: String? = null,
    @SerialName("employer_id") val employerId: String? = null,
    @SerialName("total_wages_calculated") val totalWagesCalculated: Double? = null,
    @SerialName("hourly_rate_used") val hourlyRateUsed: Double? = null,
    @SerialName("work_duration_minutes") val workDurationMinutes: Int? = null,
    @SerialName("work_session_status") val workSessionStatus: String? = null,
    @SerialName("work_session_created_at") val workSessionCreatedAt: String? = null,
    @SerialName("work_session_updated_at") val workSessionUpdatedAt: String? = null,
    @SerialName("payment_pending_at") val paymentPendingAt: String? = null,
    @SerialName("completed_at") val completedAt: String? = null,
    @SerialName("work_start_time") val workStartTime: String? = null,
    @SerialName("work_end_time") val workEndTime: String? = null,
    @SerialName("order_id") val orderId: String? = null,
    @SerialName("application_status") val applicationStatus: String? = null,
    @SerialName("payment_amount") val paymentAmount: Double? = null,
    @SerialName("payment_transaction_id") val paymentTransactionId: String? = null,
    @SerialName("payment_date") val paymentDate: String? = null,
    @SerialName("job_title") val jobTitle: String? = null,
    @SerialName("salary_range") val salaryRange: String? = null,
    @SerialName("job_location") val jobLocation: String? = null,
    @SerialName("employee_name") val employeeName: String? = null
)
