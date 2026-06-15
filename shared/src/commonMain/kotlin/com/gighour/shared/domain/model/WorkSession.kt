package com.gighour.shared.domain.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class WorkSession(
    val id: String,
    @SerialName("application_id") val applicationId: String,
    @SerialName("job_id") val jobId: String,
    @SerialName("employee_id") val employeeId: String,
    @SerialName("employer_id") val employerId: String,
    val otp: String,
    @SerialName("otp_expiry") val otpExpiry: String,
    @SerialName("otp_used_at") val otpUsedAt: String? = null,
    @SerialName("work_start_time") val workStartTime: String? = null,
    @SerialName("work_end_time") val workEndTime: String? = null,
    @SerialName("work_duration_minutes") val workDurationMinutes: Int? = null,
    val status: String? = null,
    @SerialName("completion_otp") val completionOtp: String? = null,
    @SerialName("completion_otp_expiry") val completionOtpExpiry: String? = null,
    @SerialName("completion_otp_used_at") val completionOtpUsedAt: String? = null,
    @SerialName("hourly_rate_used") val hourlyRateUsed: Double? = null,
    @SerialName("total_wages_calculated") val totalWagesCalculated: Double? = null,
    @SerialName("elapsed_seconds") val elapsedSeconds: Long? = null,
    @SerialName("order_id") val orderId: String? = null,
    @SerialName("applied_at") val appliedAt: String? = null,
    @SerialName("selected_at") val selectedAt: String? = null,
    @SerialName("accepted_at") val acceptedAt: String? = null,
    @SerialName("work_in_progress_at") val workInProgressAt: String? = null,
    @SerialName("completion_pending_at") val completionPendingAt: String? = null,
    @SerialName("payment_pending_at") val paymentPendingAt: String? = null,
    @SerialName("completed_at") val completedAt: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null
)

@Serializable
data class Earnings(
    val totalEarnings: Double = 0.0,
    val pendingPayments: Double = 0.0,
    val completedJobs: Int = 0,
    val monthlyEarnings: List<MonthlyEarning> = emptyList(),
    val recentTransactions: List<Transaction> = emptyList()
)

@Serializable
data class MonthlyEarning(
    val month: String,
    val year: Int,
    val amount: Double
)

@Serializable
data class Transaction(
    val id: String,
    val amount: Double,
    val status: String,
    val date: String,
    val jobTitle: String,
    val employerName: String
)
