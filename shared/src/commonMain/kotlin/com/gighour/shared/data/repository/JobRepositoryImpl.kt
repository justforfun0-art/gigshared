package com.gighour.shared.data.repository

import com.gighour.shared.data.ServerClock
import com.gighour.shared.data.local.JobCache
import com.gighour.shared.data.remote.CreateJobRequest
import com.gighour.shared.data.remote.JobsApi
import com.gighour.shared.data.remote.ToggleActiveRequest
import com.gighour.shared.data.remote.UpdateJobRequest
import com.gighour.shared.domain.model.Job
import com.gighour.shared.domain.model.JobFilter
import com.gighour.shared.domain.repository.JobHasApplicantsException
import com.gighour.shared.domain.repository.JobRepository
import com.gighour.shared.domain.repository.PaySuggestion
import com.gighour.shared.util.Logger
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlin.math.round

/**
 * KMP port of Gigand's JobRepositoryImpl. Behaviour preserved; the platform
 * couplings were abstracted:
 *  - Retrofit JobsApi → Ktor [JobsApi] (Phase 2 rewrite)
 *  - Room JobDao/JobEntity → [JobCache] (NoopJobCache by default — see note)
 *  - ServerTimeService → [ServerClock]
 *  - android.util.Log → [Logger]; Math.round → kotlin.math.round
 *
 * NOTE: with NoopJobCache the offline/cache fallbacks become no-ops (empty),
 * so getJobs falls through to a plain failure when both Supabase and REST fail,
 * and observeJobs emits nothing. Wire a real cache (Phase 6) to restore parity.
 */
class JobRepositoryImpl(
    private val jobsApi: JobsApi,
    private val jobCache: JobCache,
    private val supabaseClient: SupabaseClient,
    private val serverClock: ServerClock,
) : JobRepository {

    // Tolerant decoder for the embedded-count jobs query: the raw row carries
    // DB columns not present in the Job model, so unknown keys must be ignored.
    private val jobJson = Json { ignoreUnknownKeys = true }

    private suspend fun todayString(): String {
        serverClock.awaitSync()
        return serverClock.serverToday().toString()
    }

    override suspend fun getJobs(filter: JobFilter?, page: Int, limit: Int): Result<List<Job>> {
        return try {
            Logger.d(TAG, "getJobs: Supabase query state=${filter?.state}, district=${filter?.district}")
            val today = todayString()
            val jobs = fetchAllPages { from, to ->
                supabaseClient.from("jobs")
                    .select {
                        filter {
                            eq("is_active", true)
                            eq("status", "APPROVED")
                            gte("job_date", today)
                            filter?.state?.let { eq("state", it) }
                            filter?.district?.let { eq("district", it) }
                            filter?.jobType?.let { eq("job_type", it.name) }
                        }
                        order("created_at", Order.DESCENDING)
                        range(from, to)
                    }
                    .decodeList<Job>()
            }

            val nowInIndia = serverClock.serverNowInIndia()
            val filteredJobs = jobs.filter { job ->
                if (job.jobDate == null) return@filter false
                if (job.isFilled) return@filter false
                !job.isExpired(nowInIndia)
            }

            Logger.d(TAG, "getJobs: ${jobs.size} jobs, ${filteredJobs.size} after filter")
            if (filteredJobs.isNotEmpty()) cacheJobs(filteredJobs)
            Result.success(filteredJobs)
        } catch (e: Exception) {
            Logger.e(TAG, "getJobs: Supabase failed, trying REST", e)
            try {
                val response = jobsApi.getJobs(
                    page = page,
                    limit = limit,
                    state = filter?.state,
                    district = filter?.district,
                    jobType = filter?.jobType?.name,
                    search = filter?.searchQuery,
                    minSalary = filter?.minSalary,
                    maxSalary = filter?.maxSalary,
                )
                if (response.success) {
                    cacheJobs(response.jobs)
                    Result.success(response.jobs)
                } else {
                    val cached = cachedJobsMatching(filter)
                    if (cached.isNotEmpty()) Result.success(cached)
                    else Result.failure(Exception(response.error ?: "Failed to fetch jobs"))
                }
            } catch (restError: Exception) {
                Logger.e(TAG, "getJobs: REST also failed", restError)
                val cached = cachedJobsMatching(filter)
                if (cached.isNotEmpty()) Result.success(cached) else Result.failure(e)
            }
        }
    }

    override suspend fun getSuggestedPay(
        category: String?,
        district: String?,
        state: String?,
    ): Result<PaySuggestion> {
        return try {
            val result = supabaseClient.postgrest.rpc(
                function = "suggest_pay",
                parameters = buildJsonObject {
                    put("p_category", category?.takeIf { it.isNotBlank() }?.let { JsonPrimitive(it) } ?: JsonNull)
                    put("p_district", district?.takeIf { it.isNotBlank() }?.let { JsonPrimitive(it) } ?: JsonNull)
                    put("p_state", state?.takeIf { it.isNotBlank() }?.let { JsonPrimitive(it) } ?: JsonNull)
                },
            )
            val rows = jobJson.decodeFromString<List<PaySuggestionRow>>(result.data)
            val row = rows.firstOrNull() ?: return Result.success(PaySuggestion())
            Result.success(
                PaySuggestion(
                    p25 = row.p25?.let { round(it).toInt() },
                    median = row.median?.let { round(it).toInt() },
                    p75 = row.p75?.let { round(it).toInt() },
                    sampleCount = row.sampleCount ?: 0,
                    scope = row.scope ?: "none",
                )
            )
        } catch (e: Exception) {
            Logger.e(TAG, "getSuggestedPay failed; hiding suggestion", e)
            Result.success(PaySuggestion())
        }
    }

    override suspend fun rankJobsForWorker(workerId: String, limit: Int): Result<List<String>> {
        return try {
            val result = supabaseClient.postgrest.rpc(
                function = "rank_jobs",
                parameters = buildJsonObject {
                    put("p_worker_id", workerId)
                    put("p_limit", limit)
                },
            )
            // Lenient decode: rank_jobs returns {job_id, score}; strict Json
            // throws on the unknown 'score' key (project_ranking_decode_bug).
            val rows = jobJson.decodeFromString<List<RankedJobRow>>(result.data)
            Result.success(rows.map { it.jobId })
        } catch (e: Exception) {
            Logger.e(TAG, "rankJobsForWorker failed; using default order", e)
            Result.success(emptyList())
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

    override suspend fun getJobById(jobId: String): Result<Job?> {
        return try {
            val job = supabaseClient.from("jobs")
                .select {
                    filter { eq("id", jobId) }
                    limit(1L)
                }
                .decodeSingleOrNull<Job>()
            job?.let { jobCache.upsertAll(listOf(it), nowMillisOrZero()) }
            Result.success(job)
        } catch (e: Exception) {
            Logger.e(TAG, "getJobById: Supabase failed, trying REST", e)
            try {
                val response = jobsApi.getJobById(jobId)
                if (response.success) {
                    response.job?.let { jobCache.upsertAll(listOf(it), nowMillisOrZero()) }
                    Result.success(response.job)
                } else {
                    Result.success(jobCache.getById(jobId))
                }
            } catch (_: Exception) {
                Result.success(jobCache.getById(jobId))
            }
        }
    }

    override suspend fun searchJobs(query: String, filter: JobFilter?): Result<List<Job>> {
        return try {
            val allJobs = getJobs(filter)
            val filtered = allJobs.getOrNull()
                ?.filter { job ->
                    job.title.contains(query, ignoreCase = true) ||
                        job.description.contains(query, ignoreCase = true) ||
                        job.location.contains(query, ignoreCase = true)
                }
                .orEmpty()
            Result.success(filtered)
        } catch (_: Exception) {
            Result.success(jobCache.search(query))
        }
    }

    override fun observeJobs(filter: JobFilter?): Flow<List<Job>> = jobCache.observeAll()

    override suspend fun getEmployerJobs(employerId: String): Result<List<Job>> {
        return try {
            // Embed the applicant count via PostgREST aggregate so My Jobs cards
            // can show "N Applicants" on first render.
            val rows = supabaseClient.from("jobs")
                .select(Columns.raw("*, applications(count)")) {
                    filter { eq("employer_id", employerId) }
                    order("created_at", Order.DESCENDING)
                }
                .decodeList<JsonObject>()
            val jobs = rows.map { row ->
                val count = (row["applications"] as? JsonArray)
                    ?.firstOrNull()?.jsonObject?.get("count")
                    ?.jsonPrimitive?.intOrNull
                val job = jobJson.decodeFromJsonElement(Job.serializer(), JsonObject(row - "applications"))
                if (count != null) job.copy(applicationsCount = count) else job
            }
            Result.success(jobs)
        } catch (e: Exception) {
            Logger.e(TAG, "getEmployerJobs: Supabase failed, trying REST", e)
            try {
                val response = jobsApi.getEmployerJobs(employerId)
                if (response.success) Result.success(response.jobs)
                else Result.failure(Exception(response.error ?: "Failed to fetch jobs"))
            } catch (_: Exception) {
                Result.failure(e)
            }
        }
    }

    override suspend fun createJob(job: Job): Result<Job> {
        return try {
            val response = jobsApi.createJob(
                CreateJobRequest(
                    title = job.title,
                    description = job.description,
                    location = job.location,
                    salaryRange = job.salaryRange,
                    jobType = job.jobType,
                    requirements = job.requirements ?: emptyList(),
                    applicationDeadline = job.applicationDeadline,
                    tags = job.tags,
                    jobCategory = job.jobCategory,
                    preferredSkills = job.preferredSkills,
                    skillsRequired = job.skillsRequired,
                    workDuration = job.workDuration,
                    district = job.district,
                    state = job.state,
                    jobDate = job.jobDate,
                    startTime = job.startTime,
                    endTime = job.endTime,
                    breakDuration = job.breakDuration,
                    workAddress = job.workAddress,
                    workGoogleMapLocation = job.workGoogleMapLocation,
                    genderPreference = job.genderPreference,
                    languagePreference = job.languagePreference ?: emptyList(),
                    numPositions = job.numPositions,
                )
            )
            if (response.success) Result.success(response.job ?: job)
            else Result.failure(Exception(response.error ?: "Failed to create job"))
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    override suspend fun updateJob(job: Job): Result<Job> {
        return try {
            val response = jobsApi.updateJob(
                UpdateJobRequest(
                    jobId = job.id,
                    title = job.title,
                    description = job.description,
                    location = job.location,
                    salaryRange = job.salaryRange,
                    jobType = job.jobType,
                    requirements = job.requirements,
                    applicationDeadline = job.applicationDeadline,
                    tags = job.tags,
                    jobCategory = job.jobCategory,
                    preferredSkills = job.preferredSkills,
                    skillsRequired = job.skillsRequired,
                    workDuration = job.workDuration,
                    district = job.district,
                    state = job.state,
                    jobDate = job.jobDate,
                    startTime = job.startTime,
                    endTime = job.endTime,
                    breakDuration = job.breakDuration,
                    workAddress = job.workAddress,
                    workGoogleMapLocation = job.workGoogleMapLocation,
                    genderPreference = job.genderPreference,
                    languagePreference = job.languagePreference ?: emptyList(),
                    numPositions = job.numPositions,
                    isActive = job.isActive,
                )
            )
            if (response.success && response.job != null) Result.success(response.job)
            else Result.failure(Exception(response.error ?: "Failed to update job"))
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    override suspend fun deleteJob(jobId: String): Result<Unit> {
        return try {
            // Hard guard for EVERY caller: a job with ANY applicant cannot be
            // deleted — that would silently destroy people's applications.
            val applicantCount = supabaseClient.from("applications")
                .select(columns = Columns.raw("id")) {
                    filter { eq("job_id", jobId) }
                    limit(1L)
                }
                .decodeList<RowId>()
                .size
            if (applicantCount > 0) {
                Logger.e(TAG, "deleteJob blocked: job $jobId has applicants")
                return Result.failure(JobHasApplicantsException())
            }

            val response = jobsApi.deleteJob(jobId)
            if (response.success) Result.success(Unit)
            else Result.failure(Exception(response.error ?: "Failed to delete job"))
        } catch (e: JobHasApplicantsException) {
            Result.failure(e)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    override suspend fun toggleJobActive(jobId: String, isActive: Boolean): Result<Job> {
        return try {
            val response = jobsApi.toggleJobActive(jobId, ToggleActiveRequest(isActive))
            if (response.success && response.job != null) Result.success(response.job)
            else Result.failure(Exception(response.error ?: "Failed to toggle job status"))
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    override fun observeEmployerJobs(employerId: String): Flow<List<Job>> =
        jobCache.observeAll().map { jobs -> jobs.filter { it.employerId == employerId } }

    override suspend fun getJobsForSwipe(userId: String, filter: JobFilter?): Result<List<Job>> {
        return try {
            val appliedJobIds = try {
                supabaseClient.from("applications")
                    .select(columns = Columns.raw("job_id")) {
                        filter { eq("employee_id", userId) }
                    }
                    .decodeList<AppliedJobId>()
                    .map { it.jobId }
                    .toSet()
            } catch (e: Exception) {
                Logger.e(TAG, "getJobsForSwipe: failed to fetch applied jobs, continuing", e)
                emptySet()
            }

            val jobsResult = getJobs(filter)
            jobsResult.map { jobs -> jobs.filter { job -> job.id !in appliedJobIds } }
        } catch (e: Exception) {
            Logger.e(TAG, "getJobsForSwipe failed", e)
            Result.failure(e)
        }
    }

    override suspend fun markJobAsSeen(userId: String, jobId: String) {
        // Local "seen" tracking — deferred with the cache (Phase 6).
    }

    override suspend fun markJobAsNotInterested(userId: String, jobId: String) {
        // Local "not interested" tracking — deferred with the cache (Phase 6).
    }

    override suspend fun cacheJobs(jobs: List<Job>) {
        // Server-adjusted time so cache freshness tracks the server clock, not
        // the (potentially skewed) device clock.
        serverClock.awaitSync()
        jobCache.upsertAll(jobs, serverClock.serverNowMillis())
    }

    override suspend fun getCachedJobs(): List<Job> = jobCache.getAll()

    private suspend fun cachedJobsMatching(filter: JobFilter?): List<Job> {
        // Offline fallback: often runs when no fresh sync is available. Don't
        // throw on an unsynced clock — skip the expiry filter rather than crash;
        // never device time.
        val nowInIndia = serverClock.serverNowInIndiaOrNull()
        return getCachedJobs().filter { job ->
            if (job.jobDate == null) return@filter false
            if (job.isFilled) return@filter false
            if (nowInIndia != null && job.isExpired(nowInIndia)) return@filter false
            filter?.state?.let { if (!job.state.equals(it, ignoreCase = true)) return@filter false }
            filter?.district?.let { if (!job.district.equals(it, ignoreCase = true)) return@filter false }
            filter?.jobType?.let { if (job.jobType != it.name) return@filter false }
            true
        }
    }

    override suspend fun clearCache() = jobCache.clear()

    private suspend fun nowMillisOrZero(): Long =
        runCatching { serverClock.serverNowMillis() }.getOrDefault(0L)

    companion object {
        private const val TAG = "JobRepository"
        private const val PAGE_FETCH_SIZE = 100
        private const val MAX_TOTAL_ROWS = 10_000
    }
}

@Serializable
private data class AppliedJobId(
    @SerialName("job_id") val jobId: String,
)

@Serializable
private data class RowId(val id: String)

@Serializable
private data class RankedJobRow(
    @SerialName("job_id") val jobId: String,
)

@Serializable
private data class PaySuggestionRow(
    val p25: Double? = null,
    val median: Double? = null,
    val p75: Double? = null,
    @SerialName("sample_count") val sampleCount: Int? = null,
    val scope: String? = null,
)
