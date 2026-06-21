package com.gighour.shared

import com.gighour.shared.data.local.JobCache
import com.gighour.shared.data.local.db.DriverFactory
import com.gighour.shared.data.local.db.SqlDelightJobCache
import com.gighour.shared.data.local.db.createGighourDb
import com.gighour.shared.domain.model.AccountType
import com.gighour.shared.domain.model.Application
import com.gighour.shared.domain.model.AuthData
import com.gighour.shared.domain.model.Beneficiary
import com.gighour.shared.domain.model.ConversationRow
import com.gighour.shared.domain.model.ConversationSummary
import com.gighour.shared.domain.model.EmployeeProfile
import com.gighour.shared.domain.model.EmployerPaymentSummary
import com.gighour.shared.domain.model.Job
import com.gighour.shared.domain.model.MessageRow
import com.gighour.shared.domain.model.ParticipantInfo
import com.gighour.shared.domain.model.PaymentOrder
import com.gighour.shared.domain.model.PaymentVerifyResult
import com.gighour.shared.domain.model.PayoutPage
import com.gighour.shared.domain.model.PayoutStatus
import com.gighour.shared.domain.model.WorkSession
import com.gighour.shared.domain.repository.ApplicationOdds
import com.gighour.shared.domain.repository.ApplicationRepository
import com.gighour.shared.domain.repository.AuthRepository
import com.gighour.shared.domain.repository.BeneficiaryRepository
import com.gighour.shared.domain.repository.CandidateRank
import com.gighour.shared.domain.repository.NoShowRisk
import com.gighour.shared.domain.repository.DashboardRepository
import com.gighour.shared.domain.repository.EmployeeDashboardStats
import com.gighour.shared.domain.repository.EmployerDashboardStats
import com.gighour.shared.domain.repository.JobRepository
import com.gighour.shared.domain.repository.MessageRepository
import com.gighour.shared.domain.repository.NotificationsPage
import com.gighour.shared.domain.repository.NotificationRepository
import com.gighour.shared.domain.repository.OtpSendResult
import com.gighour.shared.domain.repository.PaymentRepository
import com.gighour.shared.domain.repository.PayoutRepository
import com.gighour.shared.domain.repository.ProfileRepository
import com.gighour.shared.domain.repository.ReferralInfo
import com.gighour.shared.domain.repository.ReferralRepository
import com.gighour.shared.domain.repository.ScheduleConflict
import com.gighour.shared.domain.repository.UserRating
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

/**
 * Jobs scoped to a worker's district/state (Android parity: employees only see
 * jobs in their own district). Builds the [JobFilter] Kotlin-side so Swift
 * needn't name every field; passing a blank district falls back to unfiltered.
 */
@Throws(Throwable::class)
suspend fun JobRepository.getJobsForDistrictOrThrow(
    district: String?,
    state: String?,
    page: Int = 1,
    limit: Int = 20,
): List<Job> {
    val filter = if (!district.isNullOrBlank()) {
        com.gighour.shared.domain.model.JobFilter(state = state, district = district)
    } else null
    return getJobs(filter, page, limit).getOrThrow()
}

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

/**
 * [ApplicationRepository.getActiveEmployeeApplications] as a throwing suspend —
 * the worker's in-flight applications (SELECTED → PAYMENT_PENDING), filtered
 * server-side. Backs the Home dashboard's action-card carousel.
 */
@Throws(Throwable::class)
suspend fun ApplicationRepository.getActiveEmployeeApplicationsOrThrow(employeeId: String): List<Application> =
    getActiveEmployeeApplications(employeeId).getOrThrow()

/** [ApplicationRepository.getEmployerApplications] as a throwing suspend (applicants to the employer's jobs). */
@Throws(Throwable::class)
suspend fun ApplicationRepository.getEmployerApplicationsOrThrow(employerId: String): List<Application> =
    getEmployerApplications(employerId).getOrThrow()

/** [ApplicationRepository.withdrawApplication] as a throwing suspend. */
@Throws(Throwable::class)
suspend fun ApplicationRepository.withdrawApplicationOrThrow(applicationId: String): Application =
    withdrawApplication(applicationId).getOrThrow()

/** [ApplicationRepository.applyToJob] as a throwing suspend. */
@Throws(Throwable::class)
suspend fun ApplicationRepository.applyToJobOrThrow(jobId: String, employeeId: String): Application =
    applyToJob(jobId, employeeId).getOrThrow()

/** [ApplicationRepository.predictApplicationSuccess] as a throwing suspend (pre-apply hire odds). */
@Throws(Throwable::class)
suspend fun ApplicationRepository.predictApplicationSuccessOrThrow(jobId: String, workerId: String): ApplicationOdds =
    predictApplicationSuccess(jobId, workerId).getOrThrow()

/** [ApplicationRepository.checkScheduleConflict] as a throwing suspend (nullable). */
@Throws(Throwable::class)
suspend fun ApplicationRepository.checkScheduleConflictOrThrow(jobId: String, workerId: String): ScheduleConflict? =
    checkScheduleConflict(jobId, workerId).getOrThrow()

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

/** [ProfileRepository.getEmployerProfile] as a throwing suspend (nullable result). */
@Throws(Throwable::class)
suspend fun ProfileRepository.getEmployerProfileOrThrow(userId: String): com.gighour.shared.domain.model.EmployerProfile? =
    getEmployerProfile(userId).getOrThrow()

/** [ProfileRepository.getEmployeeRating] as a throwing suspend (average + count). */
@Throws(Throwable::class)
suspend fun ProfileRepository.getEmployeeRatingOrThrow(userId: String): UserRating =
    getEmployeeRating(userId).getOrThrow()

/** [PushTokenRepository.registerToken] as a throwing suspend (platform = "ios"). */
@Throws(Throwable::class)
suspend fun com.gighour.shared.domain.repository.PushTokenRepository.registerTokenOrThrow(
    userId: String,
    token: String,
) {
    registerToken(userId, token, "ios").getOrThrow()
}

/** [MatchRepository.matchScores] as a throwing suspend (jobId → 0..100 match %). */
@Throws(Throwable::class)
suspend fun com.gighour.shared.domain.repository.MatchRepository.matchScoresOrThrow(
    state: String?,
    district: String?,
    limit: Int,
): Map<String, Int> =
    matchScores(state, district, limit).getOrThrow()

/** [JobExtractRepository.extract] as a throwing suspend (AI Post-Job suggestions). */
@Throws(Throwable::class)
suspend fun com.gighour.shared.domain.repository.JobExtractRepository.extractJobOrThrow(
    text: String,
): com.gighour.shared.domain.repository.JobSuggestion =
    extract(text).getOrThrow()

/** [SavedSearchesRepository.list] as a throwing suspend. */
@Throws(Throwable::class)
suspend fun com.gighour.shared.domain.repository.SavedSearchesRepository.listSavedSearchesOrThrow(): List<com.gighour.shared.domain.repository.SavedSearch> =
    list().getOrThrow()

/** [SavedSearchesRepository.delete] as a throwing suspend. */
@Throws(Throwable::class)
suspend fun com.gighour.shared.domain.repository.SavedSearchesRepository.deleteSavedSearchOrThrow(id: String) {
    delete(id).getOrThrow()
}

/** [ProfileRepository.getEmployeeReviews] as a throwing suspend (newest-first, ≤10). */
@Throws(Throwable::class)
suspend fun ProfileRepository.getEmployeeReviewsOrThrow(
    userId: String
): List<com.gighour.shared.domain.repository.EmployeeReview> =
    getEmployeeReviews(userId).getOrThrow()

/** [ProfileRepository.createEmployerProfile] as a throwing suspend. */
@Throws(Throwable::class)
suspend fun ProfileRepository.createEmployerProfileOrThrow(
    profile: com.gighour.shared.domain.model.EmployerProfile
): com.gighour.shared.domain.model.EmployerProfile =
    createEmployerProfile(profile).getOrThrow()

/** [ProfileRepository.updateEmployerProfile] as a throwing suspend. */
@Throws(Throwable::class)
suspend fun ProfileRepository.updateEmployerProfileOrThrow(
    profile: com.gighour.shared.domain.model.EmployerProfile
): com.gighour.shared.domain.model.EmployerProfile =
    updateEmployerProfile(profile).getOrThrow()

/** [NotificationRepository.getNotifications] as a throwing suspend. */
@Throws(Throwable::class)
suspend fun NotificationRepository.getNotificationsOrThrow(
    limit: Int = 20,
    offset: Int = 0,
): NotificationsPage = getNotifications(limit, offset).getOrThrow()

/**
 * [JobRepository.getJobsForSwipe] as a throwing suspend — the relevance-ranked
 * deck for the Tinder-style swipe UI. Scoped to the worker's district/state
 * (Android parity) when a district is given; pass the userId so applied/skipped
 * jobs are excluded.
 */
@Throws(Throwable::class)
suspend fun JobRepository.getJobsForSwipeOrThrow(
    userId: String,
    district: String?,
    state: String?,
): List<Job> {
    val filter = if (!district.isNullOrBlank()) {
        com.gighour.shared.domain.model.JobFilter(state = state, district = district)
    } else null
    return getJobsForSwipe(userId, filter).getOrThrow()
}

// ---- Employer-side ----

/** [JobRepository.getEmployerJobs] as a throwing suspend. */
@Throws(Throwable::class)
suspend fun JobRepository.getEmployerJobsOrThrow(employerId: String): List<Job> =
    getEmployerJobs(employerId).getOrThrow()

/**
 * [JobRepository.deleteJob] as a throwing suspend. Throws
 * [com.gighour.shared.domain.repository.JobHasApplicantsException] when the job
 * has applicants — Swift catches it to show the "can't delete" message.
 */
@Throws(Throwable::class)
suspend fun JobRepository.deleteJobOrThrow(jobId: String) {
    deleteJob(jobId).getOrThrow()
}

/** True if the deletion failure was the has-applicants guard (Swift can't match Kotlin types). */
fun isJobHasApplicantsError(error: Throwable): Boolean =
    error is com.gighour.shared.domain.repository.JobHasApplicantsException

/**
 * [JobRepository.rankJobsForWorker] as a throwing suspend — the smart-feed
 * ordering (job ids best-first from the rank_jobs RPC). Empty on failure so the
 * feed falls back to its default order.
 */
@Throws(Throwable::class)
suspend fun JobRepository.rankJobsForWorkerOrThrow(workerId: String, limit: Int = 100): List<String> =
    rankJobsForWorker(workerId, limit).getOrThrow()

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
    mapLocation: String?,
    jobCategory: String?,
): Job = createJob(
    Job(
        id = "",
        employerId = employerId,
        title = title,
        description = description,
        location = location,
        salaryRange = salaryRange,
        skillsRequired = skillsRequired,
        jobCategory = jobCategory,
        jobDate = jobDate,
        startTime = startTime,
        endTime = endTime,
        numPositions = numPositions,
        state = state,
        district = district,
        workGoogleMapLocation = mapLocation,
    ),
).getOrThrow()

/** [JobRepository.searchJobs] as a throwing suspend (free-text, no filter). */
@Throws(Throwable::class)
suspend fun JobRepository.searchJobsOrThrow(query: String): List<Job> =
    searchJobs(query, null).getOrThrow()

/**
 * [JobRepository.updateJob] as a throwing suspend. Carries the editable fields
 * from the iOS edit form onto the existing [Job] (id required) and persists.
 */
@Throws(Throwable::class)
suspend fun JobRepository.updateJobOrThrow(
    jobId: String,
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
    jobCategory: String?,
    mapLocation: String?,
): Job = updateJob(
    Job(
        id = jobId,
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
        jobCategory = jobCategory,
        workGoogleMapLocation = mapLocation,
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

/** [ApplicationRepository.regenerateCompletionOtp] as a throwing suspend (returns a fresh OTP). */
@Throws(Throwable::class)
suspend fun ApplicationRepository.regenerateCompletionOtpOrThrow(applicationId: String): String =
    regenerateCompletionOtp(applicationId).getOrThrow()

// ---- Work-session OTP entry (item 3) ----

/**
 * [ApplicationRepository.verifyStartOtp] as a throwing suspend. The worker types
 * the start OTP the employer generated; on success the application advances to
 * WORK_IN_PROGRESS (returns the updated [Application]).
 */
@Throws(Throwable::class)
suspend fun ApplicationRepository.verifyStartOtpOrThrow(applicationId: String, otp: String): Application =
    verifyStartOtp(applicationId, otp).getOrThrow()

/**
 * [ApplicationRepository.verifyCompletionOtp] as a throwing suspend. The employer
 * types the completion code the worker read out; on success the application
 * advances to PAYMENT_PENDING / COMPLETED (returns the updated [Application]).
 */
@Throws(Throwable::class)
suspend fun ApplicationRepository.verifyCompletionOtpOrThrow(applicationId: String, otp: String): Application =
    verifyCompletionOtp(applicationId, otp).getOrThrow()

/** [ApplicationRepository.acceptSelection] as a throwing suspend (worker accepts a SELECTED offer). */
@Throws(Throwable::class)
suspend fun ApplicationRepository.acceptSelectionOrThrow(applicationId: String): Application =
    acceptSelection(applicationId).getOrThrow()

/** [ApplicationRepository.getApplicationById] as a throwing suspend (nullable — null if not found). */
@Throws(Throwable::class)
suspend fun ApplicationRepository.getApplicationByIdOrThrow(applicationId: String): Application? =
    getApplicationById(applicationId).getOrThrow()

/** [ApplicationRepository.getWorkSession] as a throwing suspend (nullable — null until a session exists). */
@Throws(Throwable::class)
suspend fun ApplicationRepository.getWorkSessionOrThrow(applicationId: String): WorkSession? =
    getWorkSession(applicationId).getOrThrow()

// ---- Profile editing + photo upload (item 2) ----

/** [ProfileRepository.updateEmployeeProfile] as a throwing suspend (returns the saved profile). */
@Throws(Throwable::class)
suspend fun ProfileRepository.updateEmployeeProfileOrThrow(profile: EmployeeProfile): EmployeeProfile =
    updateEmployeeProfile(profile).getOrThrow()

/**
 * Edit just the user-facing fields of an existing [EmployeeProfile] and persist
 * it — done Kotlin-side via `copy()` so Swift needn't reconstruct the whole
 * (18-field) data class or know which columns are immutable. `skills` is passed
 * as a list (empty → cleared). Returns the saved profile.
 */
@Throws(Throwable::class)
suspend fun ProfileRepository.editEmployeeProfileOrThrow(
    existing: EmployeeProfile,
    name: String,
    email: String?,
    bio: String?,
    skills: List<String>,
    dob: String?,
    gender: String?,
    state: String?,
    district: String?,
): EmployeeProfile {
    val updated = existing.copy(
        name = name,
        email = email?.takeIf { it.isNotBlank() },
        bio = bio?.takeIf { it.isNotBlank() },
        skills = skills.takeIf { it.isNotEmpty() },
        dob = dob?.takeIf { it.isNotBlank() } ?: existing.dob,
        gender = gender?.takeIf { it.isNotBlank() }
            ?.let { com.gighour.shared.domain.model.Gender.fromString(it) } ?: existing.gender,
        state = state?.takeIf { it.isNotBlank() } ?: existing.state,
        district = district?.takeIf { it.isNotBlank() } ?: existing.district,
    )
    return updateEmployeeProfile(updated).getOrThrow()
}

/** Save just the worker's UPI id (Wallet screen). Copies the existing profile. */
@Throws(Throwable::class)
suspend fun ProfileRepository.setUpiIdOrThrow(existing: EmployeeProfile, upiId: String): EmployeeProfile =
    updateEmployeeProfile(existing.copy(upiId = upiId.takeIf { it.isNotBlank() })).getOrThrow()

/**
 * [ProfileRepository.uploadProfilePhoto] as a throwing suspend, taking the image
 * as a **base64 string** rather than [ByteArray]. Kotlin/Native exports
 * `ByteArray` as `KotlinByteArray`, which Swift can't build cheaply from `Data`;
 * passing base64 (trivial from Swift `Data.base64EncodedString()`) and decoding
 * here avoids an element-by-element copy. Returns the public photo URL.
 */
@OptIn(kotlin.io.encoding.ExperimentalEncodingApi::class)
@Throws(Throwable::class)
suspend fun ProfileRepository.uploadProfilePhotoBase64OrThrow(userId: String, base64: String): String {
    val bytes = kotlin.io.encoding.Base64.decode(base64)
    return uploadProfilePhoto(userId, bytes).getOrThrow()
}

// ---- Dashboard stats + referral (item 4) ----

/** [DashboardRepository.getEmployeeStats] as a throwing suspend. */
@Throws(Throwable::class)
suspend fun DashboardRepository.getEmployeeStatsOrThrow(userId: String): EmployeeDashboardStats =
    getEmployeeStats(userId).getOrThrow()

/** [DashboardRepository.getEmployerStats] as a throwing suspend. */
@Throws(Throwable::class)
suspend fun DashboardRepository.getEmployerStatsOrThrow(employerId: String): EmployerDashboardStats =
    getEmployerStats(employerId).getOrThrow()

/** [DashboardRepository.getEmployerInsights] as a throwing suspend (hiring health). */
@Throws(Throwable::class)
suspend fun DashboardRepository.getEmployerInsightsOrThrow(employerId: String): com.gighour.shared.domain.repository.EmployerInsights =
    getEmployerInsights(employerId).getOrThrow()

/** [ReferralRepository.getReferralInfo] as a throwing suspend. */
@Throws(Throwable::class)
suspend fun ReferralRepository.getReferralInfoOrThrow(userId: String): ReferralInfo =
    getReferralInfo(userId).getOrThrow()

// ---- Employer payments (item 1) ----

/** [PaymentRepository.getEmployerPaymentSummary] as a throwing suspend. */
@Throws(Throwable::class)
suspend fun PaymentRepository.getEmployerPaymentSummaryOrThrow(employerId: String): List<EmployerPaymentSummary> =
    getEmployerPaymentSummary(employerId).getOrThrow()

/**
 * [PaymentRepository.createOrder] as a throwing suspend. Returns the
 * [PaymentOrder] (order id + payment session + link) the native Cashfree
 * checkout SDK consumes. `customerEmail` is optional (Kotlin default doesn't
 * survive the ObjC export, so Swift must pass it — pass nil for none).
 */
@Throws(Throwable::class)
suspend fun PaymentRepository.createOrderOrThrow(
    applicationId: String,
    amount: Double,
    employerId: String,
    employeeId: String,
    customerName: String,
    customerPhone: String,
    customerEmail: String?,
): PaymentOrder = createOrder(
    applicationId = applicationId,
    amount = amount,
    employerId = employerId,
    employeeId = employeeId,
    customerName = customerName,
    customerPhone = customerPhone,
    customerEmail = customerEmail,
).getOrThrow()

/** [PaymentRepository.verifyPayment] as a throwing suspend (poll order status after checkout). */
@Throws(Throwable::class)
suspend fun PaymentRepository.verifyPaymentOrThrow(orderId: String): PaymentVerifyResult =
    verifyPayment(orderId).getOrThrow()

// ---- Messaging (full parity) ----

/** [MessageRepository.getConversations] as a throwing suspend. */
@Throws(Throwable::class)
suspend fun MessageRepository.getConversationsOrThrow(userId: String): List<ConversationRow> =
    getConversations(userId).getOrThrow()

/** [MessageRepository.getOrCreateConversation] as a throwing suspend (jobId optional → pass nil). */
@Throws(Throwable::class)
suspend fun MessageRepository.getOrCreateConversationOrThrow(
    employeeId: String,
    employerId: String,
    jobId: String?,
): ConversationRow = getOrCreateConversation(employeeId, employerId, jobId).getOrThrow()

/** [MessageRepository.getMessages] as a throwing suspend. */
@Throws(Throwable::class)
suspend fun MessageRepository.getMessagesOrThrow(conversationId: String): List<MessageRow> =
    getMessages(conversationId).getOrThrow()

/** [MessageRepository.sendMessage] as a throwing suspend (receiverId optional → pass nil to derive). */
@Throws(Throwable::class)
suspend fun MessageRepository.sendMessageOrThrow(
    conversationId: String,
    senderId: String,
    content: String,
    receiverId: String?,
): MessageRow = sendMessage(conversationId, senderId, content, receiverId).getOrThrow()

/**
 * [MessageRepository.getConversationSummaries] returns a Kotlin Map, which Swift
 * sees as an opaque NSDictionary; flatten to a typed list so SwiftUI can iterate.
 */
@Throws(Throwable::class)
suspend fun MessageRepository.getConversationSummariesList(
    conversationIds: List<String>,
    viewerUserId: String,
): List<ConversationSummary> =
    getConversationSummaries(conversationIds, viewerUserId).values.toList()

/** Display name for one participant (null when unknown) — avoids bridging a Map. */
@Throws(Throwable::class)
suspend fun MessageRepository.participantNameOrNull(userId: String): String? =
    getParticipantInfo(listOf(userId))[userId]?.name

/** Full participant info for one user (null when unknown). */
@Throws(Throwable::class)
suspend fun MessageRepository.participantInfoOrNull(userId: String): ParticipantInfo? =
    getParticipantInfo(listOf(userId))[userId]

/** [MessageRepository.contactAdmin] as a throwing suspend (returns the conversation id). */
@Throws(Throwable::class)
suspend fun MessageRepository.contactAdminOrThrow(message: String): String =
    contactAdmin(message).getOrThrow()

// --- Beneficiaries (Payment Methods) ---

/** [BeneficiaryRepository.listBeneficiaries] as a throwing suspend. */
@Throws(Throwable::class)
suspend fun BeneficiaryRepository.listBeneficiariesOrThrow(): List<Beneficiary> =
    listBeneficiaries().getOrThrow()

/** [BeneficiaryRepository.addBeneficiary] as a throwing suspend. */
@Throws(Throwable::class)
suspend fun BeneficiaryRepository.addBeneficiaryOrThrow(
    accountHolderName: String,
    accountType: AccountType,
    accountNumber: String?,
    ifscCode: String?,
    bankName: String?,
    upiId: String?,
    phoneNumber: String?,
    isPrimary: Boolean,
): Beneficiary = addBeneficiary(
    accountHolderName, accountType, accountNumber, ifscCode, bankName, upiId, phoneNumber, isPrimary
).getOrThrow()

/** [BeneficiaryRepository.setPrimary] as a throwing suspend. */
@Throws(Throwable::class)
suspend fun BeneficiaryRepository.setPrimaryBeneficiaryOrThrow(beneficiaryId: String) {
    setPrimary(beneficiaryId).getOrThrow()
}

/** [BeneficiaryRepository.deleteBeneficiary] as a throwing suspend. */
@Throws(Throwable::class)
suspend fun BeneficiaryRepository.deleteBeneficiaryOrThrow(beneficiaryId: String) {
    deleteBeneficiary(beneficiaryId).getOrThrow()
}

// --- Notification preferences ---

/** [NotificationRepository.saveNotificationPreferences] as a throwing suspend. */
@Throws(Throwable::class)
suspend fun NotificationRepository.saveNotificationPreferencesOrThrow(
    prefs: com.gighour.shared.domain.repository.NotificationPreferences,
): com.gighour.shared.domain.repository.NotificationPreferences =
    saveNotificationPreferences(prefs).getOrThrow()

/**
 * [ApplicationRepository.getActiveEmployerApplications] as a throwing suspend —
 * in-flight applicants to the employer's jobs (server-filtered), for the
 * employer Home action carousel.
 */
@Throws(Throwable::class)
suspend fun ApplicationRepository.getActiveEmployerApplicationsOrThrow(employerId: String): List<Application> =
    getActiveEmployerApplications(employerId).getOrThrow()

// --- Employer applicant intelligence ---

/** [ApplicationRepository.rankCandidates] as a throwing suspend (mutual-fit ranking). */
@Throws(Throwable::class)
suspend fun ApplicationRepository.rankCandidatesOrThrow(jobId: String, employerId: String): List<CandidateRank> =
    rankCandidates(jobId, employerId).getOrThrow()

/** [ApplicationRepository.computeNoShowRisk] as a throwing suspend (nullable). */
@Throws(Throwable::class)
suspend fun ApplicationRepository.computeNoShowRiskOrThrow(applicationId: String): NoShowRisk? =
    computeNoShowRisk(applicationId).getOrThrow()
