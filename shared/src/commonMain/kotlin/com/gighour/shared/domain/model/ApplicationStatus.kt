package com.gighour.shared.domain.model

import kotlinx.serialization.Serializable

/**
 * Ported from Gigand's Application.kt — the pure enum + helpers move verbatim
 * (only the package changed). The `Application` data class itself and the
 * `effectiveStatus()` function are deferred to Tier-2 because they depend on
 * [Job] / java.time (→ kotlinx-datetime).
 */
@Serializable
enum class ApplicationStatus {
    APPLIED,
    SHORTLISTED,
    REJECTED,
    HIRED,
    COMPLETED,
    WITHDRAWN,
    NOT_INTERESTED,
    SELECTED,
    ACCEPTED,
    OTP_REQUESTED,
    WORK_IN_PROGRESS,
    COMPLETION_PENDING,
    PAYMENT_PENDING,
    REJECTED_ONCE,
    REJECTED_AND_RESHOWN,
    NO_SHOW,
    POSITION_FILLED,
    EXPIRED,
    JOB_CANCELLED;

    companion object {
        fun fromString(value: String?): ApplicationStatus {
            return when (value?.uppercase()) {
                "APPLIED" -> APPLIED
                "SHORTLISTED" -> SHORTLISTED
                "REJECTED" -> REJECTED
                "HIRED" -> HIRED
                "COMPLETED" -> COMPLETED
                "WITHDRAWN" -> WITHDRAWN
                "NOT_INTERESTED" -> NOT_INTERESTED
                "SELECTED" -> SELECTED
                "ACCEPTED" -> ACCEPTED
                "OTP_REQUESTED" -> OTP_REQUESTED
                "WORK_IN_PROGRESS" -> WORK_IN_PROGRESS
                "COMPLETION_PENDING" -> COMPLETION_PENDING
                "PAYMENT_PENDING" -> PAYMENT_PENDING
                "REJECTED_ONCE" -> REJECTED_ONCE
                "REJECTED_AND_RESHOWN" -> REJECTED_AND_RESHOWN
                "NO_SHOW" -> NO_SHOW
                "POSITION_FILLED" -> POSITION_FILLED
                "EXPIRED" -> EXPIRED
                "JOB_CANCELLED" -> JOB_CANCELLED
                else -> APPLIED
            }
        }
    }

    fun toDisplayString(): String {
        return when (this) {
            APPLIED -> "Applied"
            SHORTLISTED -> "Shortlisted"
            REJECTED -> "Rejected"
            HIRED -> "Hired"
            COMPLETED -> "Completed"
            WITHDRAWN -> "Withdrawn"
            NOT_INTERESTED -> "Not Interested"
            SELECTED -> "Selected"
            ACCEPTED -> "Accepted"
            OTP_REQUESTED -> "OTP Requested"
            WORK_IN_PROGRESS -> "Work in Progress"
            COMPLETION_PENDING -> "Completion Pending"
            PAYMENT_PENDING -> "Payment Pending"
            REJECTED_ONCE -> "Rejected Once"
            REJECTED_AND_RESHOWN -> "Reshown"
            NO_SHOW -> "No Show"
            POSITION_FILLED -> "Position Filled"
            EXPIRED -> "Expired"
            JOB_CANCELLED -> "Job cancelled by employer"
        }
    }

    fun isActive(): Boolean {
        return this in listOf(
            APPLIED,
            SHORTLISTED,
            SELECTED,
            ACCEPTED,
            OTP_REQUESTED,
            WORK_IN_PROGRESS,
            COMPLETION_PENDING,
            PAYMENT_PENDING
        )
    }

    fun isTerminal(): Boolean {
        return this in listOf(
            COMPLETED,
            REJECTED,
            WITHDRAWN,
            NO_SHOW,
            POSITION_FILLED,
            NOT_INTERESTED,
            EXPIRED,
            JOB_CANCELLED
        )
    }
}
