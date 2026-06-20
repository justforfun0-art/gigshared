package com.gighour.shared.data.repository

import com.gighour.shared.data.StatusChangeNotifier
import com.gighour.shared.data.remote.ApplicationsApi
import com.gighour.shared.data.remote.ApplyRequest
import com.gighour.shared.data.remote.UpdateStatusRequest
import com.gighour.shared.data.remote.WorkSessionRequest
import com.gighour.shared.domain.model.Application
import com.gighour.shared.domain.model.ApplicationStatus
import com.gighour.shared.domain.model.WorkSession
import com.gighour.shared.domain.repository.ApplicationOdds
import com.gighour.shared.domain.repository.ApplicationRepository
import com.gighour.shared.domain.repository.ApplicationsPage
import com.gighour.shared.domain.repository.CandidateRank
import com.gighour.shared.domain.repository.NoShowRisk
import com.gighour.shared.domain.repository.ScheduleConflict
import com.gighour.shared.util.Logger
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.launch
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.put

/**
 * KMP port of Gigand's ApplicationRepositoryImpl (the largest repo, ~860 lines).
 * Platform couplings abstracted:
 *  - WhatsAppNotificationService → [StatusChangeNotifier] (NoopStatusChangeNotifier
 *    default; delivery stays per-platform).
 *  - Retrofit ApplicationsApi → Ktor [ApplicationsApi]; the Gson errorBody()
 *    re-parse in serverErrorMessage is gone — Ktor returns the decoded body even
 *    on non-2xx, so patchStatus/work-session errors come straight off body.error.
 *  - android.util.Log → [Logger].
 *
 * Preserved: SupervisorJob notifScope (one failed notification can't cancel all
 * future ones), the rpcJson lenient decoder (project_ranking_decode_bug), the
 * constraint-name embeds, fetchAllPages, and the patchStatus re-fetch-with-joins
 * (so the UI doesn't show stale "pending" after a status change).
 */
class ApplicationRepositoryImpl(
    private val applicationsApi: ApplicationsApi,
    private val supabaseClient: SupabaseClient,
    private val statusChangeNotifier: StatusChangeNotifier,
) : ApplicationRepository {

    private val notifScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    // Lenient decoder for RPC payloads: a new/extra column must NOT throw and
    // silently disable the feature (project_ranking_decode_bug).
    private val rpcJson = Json { ignoreUnknownKeys = true; isLenient = true }

    override suspend fun applyToJob(jobId: String, employeeId: String): Result<Application> {
        return try {
            val existing = supabaseClient.from("applications")
                .select(columns = Columns.raw("id")) {
                    filter {
                        eq("job_id", jobId)
                        eq("employee_id", employeeId)
                    }
                    limit(1L)
                }
                .decodeList<ApplicationIdOnly>()
            if (existing.isNotEmpty()) {
                return Result.failure(Exception("Already applied to this job"))
            }

            val result = supabaseClient.from("applications")
                .insert(
                    mapOf(
                        "job_id" to jobId,
                        "employee_id" to employeeId,
                        "status" to "APPLIED",
                    )
                ) { select() }
                .decodeSingle<Application>()

            notify(result.id, "APPLIED")
            Result.success(result)
        } catch (e: Exception) {
            Logger.e(TAG, "applyToJob: Supabase failed, trying REST", e)
            try {
                val response = applicationsApi.applyForJob(ApplyRequest(jobId, employeeId))
                if (response.success && response.application != null) {
                    notify(response.application.id, "APPLIED")
                    Result.success(response.application)
                } else {
                    Result.failure(Exception(response.error ?: "Failed to apply"))
                }
            } catch (restError: Exception) {
                Logger.e(TAG, "applyToJob: REST also failed", restError)
                Result.failure(restError)
            }
        }
    }

    override suspend fun getEmployeeApplications(employeeId: String): Result<List<Application>> {
        return try {
            val results = fetchAllPages { from, to ->
                supabaseClient.from("applications")
                    // Constraint-name embed: jobs.employer_id has two FKs, so the
                    // column-name form is ambiguous and throws.
                    .select(Columns.raw("*, job:jobs(*, employer_profiles(*), users!jobs_employer_id_fkey(user_id, phone))")) {
                        filter { eq("employee_id", employeeId) }
                        order("created_at", Order.DESCENDING)
                        range(from, to)
                    }
                    .decodeList<Application>()
            }
            Result.success(results)
        } catch (e: Exception) {
            Logger.e(TAG, "getEmployeeApplications: Supabase failed, trying REST", e)
            try {
                val response = applicationsApi.getApplications(employeeId = employeeId)
                if (response.success) Result.success(response.applications)
                else Result.failure(Exception(response.error ?: "Failed to fetch applications"))
            } catch (restError: Exception) {
                Logger.e(TAG, "getEmployeeApplications: REST also failed", restError)
                Result.failure(e)
            }
        }
    }

    override suspend fun getActionableApplicationIds(
        userId: String,
        statuses: List<ApplicationStatus>,
        isEmployer: Boolean,
    ): Result<List<String>> {
        if (statuses.isEmpty()) return Result.success(emptyList())
        return try {
            val statusNames = statuses.map { it.name }
            val rows = if (isEmployer) {
                supabaseClient.from("applications")
                    .select(Columns.raw("id, jobs!inner(employer_id)")) {
                        filter {
                            eq("jobs.employer_id", userId)
                            isIn("status", statusNames)
                        }
                    }
                    .decodeList<ApplicationIdOnly>()
            } else {
                supabaseClient.from("applications")
                    .select(Columns.raw("id")) {
                        filter {
                            eq("employee_id", userId)
                            isIn("status", statusNames)
                        }
                    }
                    .decodeList<ApplicationIdOnly>()
            }
            Result.success(rows.map { it.id })
        } catch (e: Exception) {
            Logger.e(TAG, "getActionableApplicationIds failed", e)
            Result.failure(e)
        }
    }

    override suspend fun getActiveEmployeeApplications(employeeId: String): Result<List<Application>> {
        return try {
            val results = supabaseClient.from("applications")
                .select(Columns.raw("*, job:jobs(*, employer_profiles(*), users!jobs_employer_id_fkey(user_id, phone))")) {
                    filter {
                        eq("employee_id", employeeId)
                        isIn("status", ACTIVE_DASHBOARD_STATUSES)
                    }
                    order("created_at", Order.DESCENDING)
                }
                .decodeList<Application>()
            Result.success(results)
        } catch (e: Exception) {
            Logger.e(TAG, "getActiveEmployeeApplications: Supabase failed, trying REST", e)
            try {
                val response = applicationsApi.getApplications(employeeId = employeeId)
                if (response.success) {
                    val filtered = response.applications.filter { it.status.name in ACTIVE_DASHBOARD_STATUSES }
                    Result.success(filtered)
                } else {
                    Result.failure(Exception(response.error ?: "Failed to fetch applications"))
                }
            } catch (restError: Exception) {
                Logger.e(TAG, "getActiveEmployeeApplications: REST also failed", restError)
                Result.failure(e)
            }
        }
    }

    override suspend fun getActiveEmployerApplications(employerId: String): Result<List<Application>> {
        return try {
            val results = supabaseClient.from("applications")
                .select(Columns.raw("*, job:jobs!inner(*, employer_profiles(*)), employee_profiles(*)")) {
                    filter {
                        eq("jobs.employer_id", employerId)
                        isIn("status", ACTIVE_DASHBOARD_STATUSES)
                    }
                    order("created_at", Order.DESCENDING)
                }
                .decodeList<Application>()
            Result.success(results)
        } catch (e: Exception) {
            Logger.e(TAG, "getActiveEmployerApplications: Supabase failed, trying REST", e)
            try {
                val response = applicationsApi.getApplications(employerId = employerId)
                if (response.success) {
                    val filtered = response.applications.filter { it.status.name in ACTIVE_DASHBOARD_STATUSES }
                    Result.success(filtered)
                } else {
                    Result.failure(Exception(response.error ?: "Failed to fetch applications"))
                }
            } catch (restError: Exception) {
                Logger.e(TAG, "getActiveEmployerApplications: REST also failed", restError)
                Result.failure(e)
            }
        }
    }

    override suspend fun getEmployeeApplicationsPage(
        employeeId: String,
        limit: Int,
        offset: Int,
    ): Result<ApplicationsPage> {
        return try {
            val results = supabaseClient.from("applications")
                .select(Columns.raw("*, job:jobs(*, employer_profiles(*))")) {
                    filter { eq("employee_id", employeeId) }
                    order("created_at", Order.DESCENDING)
                    range(offset.toLong(), (offset + limit).toLong())
                }
                .decodeList<Application>()
            val hasMore = results.size > limit
            val page = if (hasMore) results.take(limit) else results
            Result.success(ApplicationsPage(items = page, hasMore = hasMore))
        } catch (e: Exception) {
            Logger.e(TAG, "getEmployeeApplicationsPage failed", e)
            Result.failure(e)
        }
    }

    override suspend fun getApplicationById(applicationId: String): Result<Application?> {
        val supabaseError: Exception? = try {
            val result = supabaseClient.from("applications")
                .select(Columns.raw("*, job:jobs(*, employer_profiles(*)), employee_profiles(*)")) {
                    filter { eq("id", applicationId) }
                    limit(1L)
                }
                .decodeSingleOrNull<Application>()
            // null usually means RLS filtered the row (stale/unminted Supabase
            // token, e.g. cold start from a notification tap), NOT that it's
            // missing — fall through to REST which uses the app JWT cookie.
            if (result != null) return Result.success(result)
            null
        } catch (e: Exception) {
            Logger.e(TAG, "getApplicationById: Supabase failed, trying REST", e)
            e
        }
        return try {
            val response = applicationsApi.getApplicationById(applicationId)
            if (response.success) Result.success(response.application)
            else Result.failure(Exception(response.error ?: "Failed to fetch application"))
        } catch (restError: Exception) {
            Result.failure(supabaseError ?: restError)
        }
    }

    override suspend fun withdrawApplication(applicationId: String): Result<Application> =
        patchStatus(applicationId, "WITHDRAWN", failureMsg = "Failed to withdraw application")

    override suspend fun updateApplicationStatus(
        applicationId: String,
        status: ApplicationStatus,
    ): Result<Application> =
        patchStatus(applicationId, status.name, failureMsg = "Failed to update status")

    override suspend fun acceptSelection(applicationId: String): Result<Application> {
        val result = patchStatus(
            applicationId, "ACCEPTED", termsConfirmed = true, failureMsg = "Failed to accept selection",
        )
        if (result.isSuccess) notify(applicationId, "ACCEPTED")
        return result
    }

    private suspend fun patchStatus(
        applicationId: String,
        status: String,
        reason: String? = null,
        termsConfirmed: Boolean? = null,
        failureMsg: String,
    ): Result<Application> {
        return try {
            val result = applicationsApi.updateApplicationStatus(
                UpdateStatusRequest(applicationId, status, reason, termsConfirmed)
            )
            val response = result.body
            if (!response.success) {
                // Surface the server's reason (e.g. 409 "Position already filled")
                // instead of a raw status code.
                return Result.failure(Exception(response.error ?: failureMsg))
            }
            // Prefer a fresh re-fetch (with joins) over the PATCH's bare echoed
            // row, which could read back stale and leave the UI on "pending".
            val updated = getApplicationById(applicationId).getOrNull() ?: response.data
            if (updated != null) Result.success(updated)
            else Result.failure(Exception(response.error ?: failureMsg))
        } catch (e: Exception) {
            Result.failure(Exception(e.message?.takeIf { it.isNotBlank() } ?: failureMsg))
        }
    }

    override fun observeEmployeeApplications(employeeId: String): Flow<List<Application>> = flow {
        getEmployeeApplications(employeeId).getOrNull()?.let { emit(it) }
    }

    override suspend fun getApplicationsForJob(jobId: String): Result<List<Application>> {
        return try {
            val results = supabaseClient.from("applications")
                .select(Columns.raw("*, job:jobs(*, employer_profiles(*)), employee_profiles(*)")) {
                    filter { eq("job_id", jobId) }
                    order("created_at", Order.DESCENDING)
                }
                .decodeList<Application>()
            Result.success(results)
        } catch (e: Exception) {
            Logger.e(TAG, "getApplicationsForJob: Supabase failed, trying REST", e)
            try {
                val response = applicationsApi.getApplications(jobId = jobId)
                if (response.success) Result.success(response.applications)
                else Result.failure(Exception(response.error ?: "Failed to fetch applications"))
            } catch (_: Exception) {
                Result.failure(e)
            }
        }
    }

    override suspend fun rankCandidates(jobId: String, employerId: String): Result<List<CandidateRank>> {
        return try {
            val result = supabaseClient.postgrest.rpc(
                function = "rank_candidates",
                parameters = buildJsonObject {
                    put("p_job_id", jobId)
                    put("p_employer_id", employerId)
                },
            )
            val rows = rpcJson.decodeFromString<List<JsonObject>>(result.data)
            val ranks = rows.mapNotNull { row ->
                val employeeId = (row["employee_id"] as? JsonPrimitive)?.contentOrNull
                    ?: return@mapNotNull null
                val score = (row["score"] as? JsonPrimitive)?.doubleOrNull ?: 0.0
                val breakdown = (row["breakdown"] as? JsonObject)?.mapValues { (_, v) ->
                    (v as? JsonPrimitive)?.doubleOrNull ?: 0.0
                } ?: emptyMap()
                CandidateRank(employeeId = employeeId, score = score, breakdown = breakdown)
            }
            Result.success(ranks)
        } catch (e: Exception) {
            Logger.e(TAG, "rankCandidates failed for job $jobId; default order", e)
            Result.success(emptyList())
        }
    }

    override suspend fun getEmployerApplicationsPage(
        employerId: String,
        limit: Int,
        offset: Int,
    ): Result<ApplicationsPage> {
        return try {
            val results = supabaseClient.from("applications")
                .select(Columns.raw("*, job:jobs!inner(*, employer_profiles(*)), employee_profiles(*)")) {
                    filter { eq("jobs.employer_id", employerId) }
                    order("created_at", Order.DESCENDING)
                    range(offset.toLong(), (offset + limit).toLong())
                }
                .decodeList<Application>()
            val hasMore = results.size > limit
            val page = if (hasMore) results.take(limit) else results
            Result.success(ApplicationsPage(items = page, hasMore = hasMore))
        } catch (e: Exception) {
            Logger.e(TAG, "getEmployerApplicationsPage failed", e)
            Result.failure(e)
        }
    }

    override suspend fun getEmployerApplications(employerId: String): Result<List<Application>> {
        return try {
            val results = fetchAllPages { from, to ->
                supabaseClient.from("applications")
                    .select(Columns.raw("*, job:jobs!inner(*, employer_profiles(*)), employee_profiles(*)")) {
                        filter { eq("jobs.employer_id", employerId) }
                        order("created_at", Order.DESCENDING)
                        range(from, to)
                    }
                    .decodeList<Application>()
            }
            Result.success(results)
        } catch (e: Exception) {
            Logger.e(TAG, "getEmployerApplications: Supabase failed, trying REST", e)
            try {
                val response = applicationsApi.getApplications(employerId = employerId)
                if (response.success) Result.success(response.applications)
                else Result.failure(Exception(response.error ?: "Failed to fetch applications"))
            } catch (restError: Exception) {
                Logger.e(TAG, "getEmployerApplications: REST also failed", restError)
                Result.failure(e)
            }
        }
    }

    private suspend fun <T> fetchAllPages(
        pageSize: Int = PAGE_FETCH_SIZE,
        page: suspend (from: Long, to: Long) -> List<T>,
    ): List<T> {
        val all = mutableListOf<T>()
        var offset = 0L
        while (true) {
            val chunk = page(offset, offset + pageSize - 1)
            all += chunk
            if (chunk.size < pageSize || all.size >= MAX_TOTAL_ROWS) break
            offset += pageSize
        }
        return all
    }

    override suspend fun selectApplicant(applicationId: String): Result<Application> {
        val result = patchStatus(applicationId, "SELECTED", failureMsg = "Failed to select applicant")
        if (result.isSuccess) notify(applicationId, "SELECTED")
        return result
    }

    override suspend fun rejectApplicant(applicationId: String, reason: String?): Result<Application> {
        val result = patchStatus(applicationId, "REJECTED", reason = reason, failureMsg = "Failed to reject applicant")
        if (result.isSuccess) notify(applicationId, "REJECTED")
        return result
    }

    override suspend fun markNoShow(applicationId: String): Result<Application> =
        patchStatus(applicationId, "NO_SHOW", failureMsg = "Failed to mark no-show")

    override fun observeApplicationsForJob(jobId: String): Flow<List<Application>> = flow {
        getApplicationsForJob(jobId).getOrNull()?.let { emit(it) }
    }

    override suspend fun generateWorkOtp(applicationId: String): Result<String> =
        generateStartOtp(applicationId)

    override suspend fun verifyWorkOtp(applicationId: String, otp: String): Result<Boolean> {
        return try {
            val result = applicationsApi.workSessionAction(
                WorkSessionRequest(action = "verify-otp", applicationId = applicationId, otp = otp)
            )
            Result.success(result.body.success)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    override suspend fun generateStartOtp(applicationId: String): Result<String> {
        return try {
            val result = applicationsApi.workSessionAction(
                WorkSessionRequest(action = "create", applicationId = applicationId)
            )
            val response = result.body
            val otp = response.data?.otp
            if (response.success && otp != null) Result.success(otp)
            else Result.failure(Exception(response.error ?: "Failed to generate OTP"))
        } catch (e: Exception) {
            Logger.e(TAG, "generateStartOtp failed for $applicationId: ${e.message}")
            Result.failure(Exception(e.message?.takeIf { it.isNotBlank() } ?: "Failed to start work. Please try again."))
        }
    }

    override suspend fun verifyStartOtp(applicationId: String, otp: String): Result<Application> {
        return try {
            val result = applicationsApi.workSessionAction(
                WorkSessionRequest(action = "verify-otp", applicationId = applicationId, otp = otp)
            )
            if (result.body.success) {
                notify(applicationId, "WORK_IN_PROGRESS")
                val app = getApplicationById(applicationId).getOrNull()
                if (app != null) Result.success(app)
                else Result.failure(Exception("OTP verified but failed to fetch updated application"))
            } else {
                Result.failure(Exception(result.body.error ?: "Failed to verify OTP"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    override suspend fun generateCompletionOtp(applicationId: String): Result<String> {
        return try {
            val result = applicationsApi.workSessionAction(
                WorkSessionRequest(action = "complete", applicationId = applicationId)
            )
            val response = result.body
            val otp = response.completionOtp ?: response.data?.completionOtp
            if (response.success && otp != null) {
                notify(applicationId, "COMPLETION_PENDING")
                Result.success(otp)
            } else {
                Result.failure(Exception(response.error ?: "Failed to generate completion OTP"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    override suspend fun regenerateCompletionOtp(applicationId: String): Result<String> {
        return try {
            val result = applicationsApi.workSessionAction(
                WorkSessionRequest(action = "regenerate-completion", applicationId = applicationId)
            )
            val response = result.body
            val otp = response.completionOtp ?: response.data?.completionOtp
            if (response.success && otp != null) Result.success(otp)
            else Result.failure(Exception(response.error ?: "Failed to regenerate completion OTP"))
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    override suspend fun verifyCompletionOtp(applicationId: String, otp: String): Result<Application> {
        return try {
            val result = applicationsApi.workSessionAction(
                WorkSessionRequest(action = "verify-completion", applicationId = applicationId, otp = otp)
            )
            if (result.body.success) {
                notify(applicationId, "COMPLETED")
                val app = getApplicationById(applicationId).getOrNull()
                if (app != null) Result.success(app)
                else Result.failure(Exception("Completion verified but failed to fetch updated application"))
            } else {
                Result.failure(Exception(result.body.error ?: "Failed to verify completion OTP"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    override fun observeApplicationStatus(applicationId: String): Flow<ApplicationStatus> = flow {
        getApplicationById(applicationId).getOrNull()?.let { emit(it.status) }
    }

    override suspend fun hasApplied(jobId: String, employeeId: String): Boolean {
        return try {
            supabaseClient.from("applications")
                .select {
                    filter {
                        eq("employee_id", employeeId)
                        eq("job_id", jobId)
                    }
                    limit(1L)
                }
                .decodeList<Application>()
                .isNotEmpty()
        } catch (_: Exception) {
            try {
                val response = applicationsApi.getApplications(employeeId = employeeId, jobId = jobId)
                response.success && response.applications.isNotEmpty()
            } catch (_: Exception) {
                false
            }
        }
    }

    override suspend fun getWorkSession(applicationId: String): Result<WorkSession?> {
        return try {
            val result = supabaseClient.from("work_sessions")
                .select {
                    filter { eq("application_id", applicationId) }
                    limit(1L)
                }
                .decodeSingleOrNull<WorkSession>()
            Result.success(result)
        } catch (e: Exception) {
            Logger.e(TAG, "getWorkSession failed for $applicationId", e)
            Result.success(null)
        }
    }

    override suspend fun predictApplicationSuccess(jobId: String, workerId: String): Result<ApplicationOdds> {
        return try {
            val result = supabaseClient.postgrest.rpc(
                function = "predict_application_success",
                parameters = buildJsonObject {
                    put("p_job_id", jobId)
                    put("p_worker_id", workerId)
                },
            )
            val rows = rpcJson.decodeFromString<List<ApplicationOddsRow>>(result.data)
            val row = rows.firstOrNull() ?: return Result.success(ApplicationOdds())
            Result.success(
                ApplicationOdds(
                    probability = row.probability ?: 0.0,
                    applicants = row.applicants ?: 0,
                    positions = row.positions ?: 1,
                    fit = row.fit ?: 0.0,
                    band = row.band ?: "medium",
                )
            )
        } catch (e: Exception) {
            Logger.e(TAG, "predictApplicationSuccess failed for job $jobId", e)
            Result.failure(e)
        }
    }

    override suspend fun checkScheduleConflict(jobId: String, workerId: String): Result<ScheduleConflict?> {
        return try {
            val result = supabaseClient.postgrest.rpc(
                function = "check_schedule_conflict",
                parameters = buildJsonObject {
                    put("p_job_id", jobId)
                    put("p_worker_id", workerId)
                },
            )
            val rows = rpcJson.decodeFromString<List<ScheduleConflictRow>>(result.data)
            val row = rows.firstOrNull() ?: return Result.success(null)
            Result.success(
                ScheduleConflict(
                    jobId = row.conflictJobId,
                    title = row.conflictTitle,
                    date = row.conflictDate,
                    startTime = row.conflictStart,
                    endTime = row.conflictEnd,
                )
            )
        } catch (e: Exception) {
            Logger.e(TAG, "checkScheduleConflict failed for job $jobId", e)
            Result.success(null)
        }
    }

    override suspend fun computeNoShowRisk(applicationId: String): Result<NoShowRisk?> {
        return try {
            val result = supabaseClient.postgrest.rpc(
                function = "compute_no_show_risk",
                parameters = buildJsonObject { put("p_application_id", applicationId) },
            )
            val rows = rpcJson.decodeFromString<List<NoShowRiskRow>>(result.data)
            val row = rows.firstOrNull() ?: return Result.success(null)
            Result.success(
                NoShowRisk(
                    risk = row.risk ?: 0.0,
                    band = row.band ?: "low",
                    priorNoShows = row.priorNoShows ?: 0,
                    priorCommitments = row.priorCommitments ?: 0,
                    outOfDistrict = row.outOfDistrict ?: false,
                )
            )
        } catch (e: Exception) {
            Logger.e(TAG, "computeNoShowRisk failed for $applicationId", e)
            Result.success(null)
        }
    }

    /** Fire-and-forget status notification on the SupervisorJob scope. */
    private fun notify(applicationId: String, status: String) {
        notifScope.launch { statusChangeNotifier.notifyStatusChange(applicationId, status) }
    }

    companion object {
        private const val TAG = "ApplicationRepository"
        private const val PAGE_FETCH_SIZE = 100
        private const val MAX_TOTAL_ROWS = 10_000

        private val ACTIVE_DASHBOARD_STATUSES = listOf(
            "WORK_IN_PROGRESS",
            "COMPLETION_PENDING",
            "PAYMENT_PENDING",
            "SELECTED",
            "ACCEPTED",
            "OTP_REQUESTED",
        )
    }
}

@Serializable
private data class ScheduleConflictRow(
    @SerialName("conflict_job_id") val conflictJobId: String,
    @SerialName("conflict_title") val conflictTitle: String? = null,
    @SerialName("conflict_date") val conflictDate: String? = null,
    @SerialName("conflict_start") val conflictStart: String? = null,
    @SerialName("conflict_end") val conflictEnd: String? = null,
)

@Serializable
private data class NoShowRiskRow(
    val risk: Double? = null,
    val band: String? = null,
    @SerialName("prior_no_shows") val priorNoShows: Int? = null,
    @SerialName("prior_commitments") val priorCommitments: Int? = null,
    @SerialName("out_of_district") val outOfDistrict: Boolean? = null,
)

@Serializable
private data class ApplicationOddsRow(
    val probability: Double? = null,
    val applicants: Int? = null,
    val positions: Int? = null,
    val fit: Double? = null,
    val band: String? = null,
)

@Serializable
private data class ApplicationIdOnly(
    val id: String,
)
