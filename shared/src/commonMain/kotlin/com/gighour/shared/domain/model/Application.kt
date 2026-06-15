package com.gighour.shared.domain.model

import kotlinx.datetime.LocalDateTime
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class Application(
    val id: String,
    @SerialName("job_id") val jobId: String,
    @SerialName("employee_id") val employeeId: String,
    val status: ApplicationStatus,
    @SerialName("applied_at") val appliedAt: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("rejection_reason") val rejectionReason: String? = null,
    @SerialName("payment_status") val paymentStatus: String? = null,
    @SerialName("payment_transaction_id") val paymentTransactionId: String? = null,
    @SerialName("payment_amount") val paymentAmount: Double? = null,
    @SerialName("payment_date") val paymentDate: String? = null,
    @SerialName("order_id") val orderId: String? = null,
    // Joined data
    val job: Job? = null,
    @SerialName("employee_profiles") val employeeProfile: EmployeeProfile? = null
)

/**
 * The status to *display* for this application, accounting for expiry that the
 * stored row may not yet reflect. The web app computes expiry at display time
 * (job start_time + grace) rather than relying on the DB status, and the
 * backend cron only ever writes EXPIRED for APPLIED/SELECTED — so ACCEPTED /
 * SHORTLISTED / OTP_REQUESTED rows on a passed job keep their old status in the
 * DB. Mirroring the web here makes the History / Applications tabs show EXPIRED
 * consistently.
 *
 * A row is shown as EXPIRED when:
 *   - its current status is still "pending" (not terminal, not in-flight work,
 *     not already expired), and
 *   - the joined job is past its start-time + grace ([Job.isExpired]).
 *
 * Falls back to the stored status when the job isn't loaded or isn't expired.
 * [nowInIndia] should come from the server clock in Asia/Kolkata (wall-clock
 * [LocalDateTime]); pass null when server time isn't synced yet — we then leave
 * the status untouched rather than risk a wrong call against the device clock.
 */
fun Application.effectiveStatus(nowInIndia: LocalDateTime?): ApplicationStatus {
    val current = status
    if (nowInIndia == null) return current
    // Terminal and in-flight states are authoritative — never override them.
    if (current.isTerminal()) return current
    if (current in IN_FLIGHT_WORK_STATUSES) return current
    val expired = job?.isExpired(nowInIndia) ?: return current
    return if (expired) ApplicationStatus.EXPIRED else current
}
