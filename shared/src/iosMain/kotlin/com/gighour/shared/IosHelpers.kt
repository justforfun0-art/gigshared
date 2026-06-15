package com.gighour.shared

import com.gighour.shared.data.local.JobCache
import com.gighour.shared.data.local.db.DriverFactory
import com.gighour.shared.data.local.db.SqlDelightJobCache
import com.gighour.shared.data.local.db.createGighourDb
import com.gighour.shared.domain.model.Application
import com.gighour.shared.domain.model.AuthData
import com.gighour.shared.domain.model.EmployeeProfile
import com.gighour.shared.domain.model.Job
import com.gighour.shared.domain.model.PayoutPage
import com.gighour.shared.domain.model.PayoutStatus
import com.gighour.shared.domain.repository.ApplicationRepository
import com.gighour.shared.domain.repository.AuthRepository
import com.gighour.shared.domain.repository.JobRepository
import com.gighour.shared.domain.repository.NotificationsPage
import com.gighour.shared.domain.repository.NotificationRepository
import com.gighour.shared.domain.repository.OtpSendResult
import com.gighour.shared.domain.repository.PayoutRepository
import com.gighour.shared.domain.repository.ProfileRepository
import kotlinx.coroutines.Dispatchers

/**
 * Small Swift-facing conveniences. Two things don't bridge cleanly to
 * Objective-C / Swift and are smoothed over here:
 *
 *  1. Kotlin default arguments don't survive the ObjC export, and internal
 *     coroutine types (Dispatchers) aren't exported — so building a
 *     SqlDelightJobCache from Swift would force naming a CoroutineDispatcher.
 *     [makeJobCache] supplies the default dispatcher internally.
 *
 *  2. Kotlin `Result<T>` boxes to an opaque value over ObjC, so Swift can't call
 *     `.getOrNull()`. The `*OrThrow` wrappers unwrap it into a normal throwing
 *     suspend function (→ Swift `async throws`), which is what Swift wants.
 *
 * For a fuller solution across ALL repos, add SKIE (skie.touchlab.co) — it
 * generates typed Result + AsyncSequence wrappers and makes these unnecessary.
 */

/** Build the SQLite-backed job cache without naming a dispatcher from Swift. */
fun makeJobCache(driverFactory: DriverFactory): JobCache =
    SqlDelightJobCache(createGighourDb(driverFactory), ioDispatcher = Dispatchers.Default)

/** [JobRepository.getJobs] as a plain throwing suspend (unwraps Kotlin Result). */
@Throws(Throwable::class)
suspend fun JobRepository.getJobsOrThrow(
    filter: com.gighour.shared.domain.model.JobFilter? = null,
    page: Int = 1,
    limit: Int = 20,
): List<Job> = getJobs(filter, page, limit).getOrThrow()

/** [AuthRepository.sendOtp] unwrapped to a throwing suspend (→ Swift async throws). */
@Throws(Throwable::class)
suspend fun AuthRepository.sendOtpOrThrow(phone: String): OtpSendResult =
    sendOtp(phone).getOrThrow()

/** [AuthRepository.verifyOtp] unwrapped to a throwing suspend (→ Swift async throws). */
@Throws(Throwable::class)
suspend fun AuthRepository.verifyOtpOrThrow(phone: String, otp: String): AuthData =
    verifyOtp(phone, otp).getOrThrow()

/** [ApplicationRepository.getEmployeeApplications] as a throwing suspend. */
@Throws(Throwable::class)
suspend fun ApplicationRepository.getEmployeeApplicationsOrThrow(employeeId: String): List<Application> =
    getEmployeeApplications(employeeId).getOrThrow()

/** [ApplicationRepository.withdrawApplication] as a throwing suspend. */
@Throws(Throwable::class)
suspend fun ApplicationRepository.withdrawApplicationOrThrow(applicationId: String): Application =
    withdrawApplication(applicationId).getOrThrow()

/** [ApplicationRepository.applyToJob] as a throwing suspend. */
@Throws(Throwable::class)
suspend fun ApplicationRepository.applyToJobOrThrow(jobId: String, employeeId: String): Application =
    applyToJob(jobId, employeeId).getOrThrow()

/** [PayoutRepository.getHistory] as a throwing suspend (default = all statuses). */
@Throws(Throwable::class)
suspend fun PayoutRepository.getHistoryOrThrow(
    status: PayoutStatus? = null,
    limit: Int = 50,
    offset: Int = 0,
): PayoutPage = getHistory(status, limit, offset).getOrThrow()

/** [ProfileRepository.getEmployeeProfile] as a throwing suspend (nullable result). */
@Throws(Throwable::class)
suspend fun ProfileRepository.getEmployeeProfileOrThrow(userId: String): EmployeeProfile? =
    getEmployeeProfile(userId).getOrThrow()

/** [NotificationRepository.getNotifications] as a throwing suspend. */
@Throws(Throwable::class)
suspend fun NotificationRepository.getNotificationsOrThrow(
    limit: Int = 20,
    offset: Int = 0,
): NotificationsPage = getNotifications(limit, offset).getOrThrow()

// ---- Employer-side ----

/** [JobRepository.getEmployerJobs] as a throwing suspend. */
@Throws(Throwable::class)
suspend fun JobRepository.getEmployerJobsOrThrow(employerId: String): List<Job> =
    getEmployerJobs(employerId).getOrThrow()

/**
 * Post a new job from just the form fields — builds the (37-arg) [Job]
 * Kotlin-side so Swift needn't. `id` is server-assigned (sent empty); status is
 * left to the backend's approval flow.
 */
@Throws(Throwable::class)
suspend fun JobRepository.createJobOrThrow(
    employerId: String,
    title: String,
    description: String,
    location: String,
    salaryRange: String?,
    jobDate: String?,
    startTime: String?,
    endTime: String?,
    numPositions: Int,
    skillsRequired: List<String>,
    state: String?,
    district: String?,
): Job = createJob(
    Job(
        id = "",
        employerId = employerId,
        title = title,
        description = description,
        location = location,
        salaryRange = salaryRange,
        skillsRequired = skillsRequired,
        jobDate = jobDate,
        startTime = startTime,
        endTime = endTime,
        numPositions = numPositions,
        state = state,
        district = district,
    ),
).getOrThrow()

/** [ApplicationRepository.getApplicationsForJob] as a throwing suspend. */
@Throws(Throwable::class)
suspend fun ApplicationRepository.getApplicationsForJobOrThrow(jobId: String): List<Application> =
    getApplicationsForJob(jobId).getOrThrow()

/** [ApplicationRepository.selectApplicant] as a throwing suspend. */
@Throws(Throwable::class)
suspend fun ApplicationRepository.selectApplicantOrThrow(applicationId: String): Application =
    selectApplicant(applicationId).getOrThrow()

/** [ApplicationRepository.rejectApplicant] as a throwing suspend. */
@Throws(Throwable::class)
suspend fun ApplicationRepository.rejectApplicantOrThrow(applicationId: String, reason: String?): Application =
    rejectApplicant(applicationId, reason).getOrThrow()

/** [ApplicationRepository.generateStartOtp] as a throwing suspend (returns the OTP). */
@Throws(Throwable::class)
suspend fun ApplicationRepository.generateStartOtpOrThrow(applicationId: String): String =
    generateStartOtp(applicationId).getOrThrow()

/** [ApplicationRepository.generateCompletionOtp] as a throwing suspend (returns the OTP). */
@Throws(Throwable::class)
suspend fun ApplicationRepository.generateCompletionOtpOrThrow(applicationId: String): String =
    generateCompletionOtp(applicationId).getOrThrow()
