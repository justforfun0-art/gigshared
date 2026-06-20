package com.gighour.shared.domain.repository

import com.gighour.shared.domain.model.Application
import com.gighour.shared.domain.model.ApplicationStatus
import com.gighour.shared.domain.model.WorkSession
import kotlinx.coroutines.flow.Flow

data class ApplicationsPage(
    val items: List<Application>,
    val hasMore: Boolean
)

/**
 * One applicant's mutual-fit ranking, produced by the shared `rank_candidates`
 * DB function (same scoring as the web app). Higher [score] = better fit.
 * [breakdown] maps each signal name (reliability, skillMatch, …) to its 0..1
 * contribution, for an optional "why ranked here" UI.
 */
data class CandidateRank(
    val employeeId: String,
    val score: Double,
    val breakdown: Map<String, Double>
)

interface ApplicationRepository {
    // Employee applications
    suspend fun applyToJob(jobId: String, employeeId: String): Result<Application>
    suspend fun getEmployeeApplications(employeeId: String): Result<List<Application>>
    /**
     * Dashboard-only fetch: returns just the applications in an actionable
     * status (the cards the home screen renders), filtered server-side so a
     * worker with a long history doesn't download every past application plus
     * its nested job/employer rows on each home-screen load.
     */
    suspend fun getActiveEmployeeApplications(employeeId: String): Result<List<Application>>

    /** In-flight applicants to the employer's jobs (server-filtered to the
     *  active dashboard statuses), for the employer Home action carousel. */
    suspend fun getActiveEmployerApplications(employerId: String): Result<List<Application>>

    suspend fun getEmployeeApplicationsPage(employeeId: String, limit: Int = 50, offset: Int = 0): Result<ApplicationsPage>

    /**
     * IDs of a user's applications currently in one of [statuses]. Used by the
     * top-bar badge, which only needs the actionable IDs to diff against
     * "seen" — far cheaper than fetching every application + joins on startup,
     * and the filtered set is always small so no paging/cap concern applies.
     * [isEmployer] selects the employer (job-owner) vs employee filter.
     */
    suspend fun getActionableApplicationIds(
        userId: String,
        statuses: List<ApplicationStatus>,
        isEmployer: Boolean
    ): Result<List<String>>
    suspend fun getApplicationById(applicationId: String): Result<Application?>
    suspend fun withdrawApplication(applicationId: String): Result<Application>
    suspend fun acceptSelection(applicationId: String): Result<Application>
    suspend fun updateApplicationStatus(applicationId: String, status: ApplicationStatus): Result<Application>
    fun observeEmployeeApplications(employeeId: String): Flow<List<Application>>

    // Employer applications
    suspend fun getApplicationsForJob(jobId: String): Result<List<Application>>
    suspend fun rankCandidates(jobId: String, employerId: String): Result<List<CandidateRank>>
    suspend fun getEmployerApplications(employerId: String): Result<List<Application>>
    suspend fun getEmployerApplicationsPage(employerId: String, limit: Int = 50, offset: Int = 0): Result<ApplicationsPage>
    suspend fun selectApplicant(applicationId: String): Result<Application>
    suspend fun rejectApplicant(applicationId: String, reason: String?): Result<Application>
    suspend fun markNoShow(applicationId: String): Result<Application>
    fun observeApplicationsForJob(jobId: String): Flow<List<Application>>

    // Work session management
    suspend fun generateWorkOtp(applicationId: String): Result<String>
    suspend fun verifyWorkOtp(applicationId: String, otp: String): Result<Boolean>
    suspend fun generateStartOtp(applicationId: String): Result<String>
    suspend fun verifyStartOtp(applicationId: String, otp: String): Result<Application>
    suspend fun generateCompletionOtp(applicationId: String): Result<String>
    suspend fun regenerateCompletionOtp(applicationId: String): Result<String>
    suspend fun verifyCompletionOtp(applicationId: String, otp: String): Result<Application>

    // Status updates (realtime)
    fun observeApplicationStatus(applicationId: String): Flow<ApplicationStatus>

    // Work session data
    suspend fun getWorkSession(applicationId: String): Result<WorkSession?>

    // Check if already applied
    suspend fun hasApplied(jobId: String, employeeId: String): Boolean

    // Pre-apply: predict the worker's odds of being hired for a job.
    suspend fun predictApplicationSuccess(jobId: String, workerId: String): Result<ApplicationOdds>

    // Pre-apply: detect a schedule conflict with a job the worker already committed to.
    suspend fun checkScheduleConflict(jobId: String, workerId: String): Result<ScheduleConflict?>

    // Employer: no-show risk for a hired applicant.
    suspend fun computeNoShowRisk(applicationId: String): Result<NoShowRisk?>
}

/** An existing committed job that overlaps a candidate job's date+time window. */
data class ScheduleConflict(
    val jobId: String,
    val title: String?,
    val date: String?,
    val startTime: String?,
    val endTime: String?
)

/**
 * No-show risk for a hired worker, from `compute_no_show_risk`. [risk] is 0..1
 * (Laplace-smoothed so thin history isn't over-flagged); [band] is
 * high/medium/low for UI color. Driven by prior no-show history + distance.
 */
data class NoShowRisk(
    val risk: Double = 0.0,
    val band: String = "low",
    val priorNoShows: Int = 0,
    val priorCommitments: Int = 0,
    val outOfDistrict: Boolean = false
)

/**
 * Pre-apply hire-odds estimate from the shared `predict_application_success`
 * DB function. [probability] is 0..1 driven mainly by competition ([applicants]
 * vs [positions]) — the validated signal — refined by skill/location [fit].
 * [band] is "high"/"medium"/"low" for UI color. Deliberately does NOT use
 * reliability_score (confounded — it's computed from outcomes).
 */
data class ApplicationOdds(
    val probability: Double = 0.0,
    val applicants: Int = 0,
    val positions: Int = 1,
    val fit: Double = 0.0,
    val band: String = "medium"
)
