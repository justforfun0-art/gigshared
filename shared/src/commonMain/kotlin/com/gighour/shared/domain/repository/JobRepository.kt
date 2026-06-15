package com.gighour.shared.domain.repository

import com.gighour.shared.domain.model.Job
import com.gighour.shared.domain.model.JobFilter
import kotlinx.coroutines.flow.Flow

interface JobRepository {
    // Browse jobs (for employees)
    suspend fun getJobs(filter: JobFilter? = null, page: Int = 1, limit: Int = 20): Result<List<Job>>
    suspend fun getJobById(jobId: String): Result<Job?>
    suspend fun searchJobs(query: String, filter: JobFilter? = null): Result<List<Job>>
    fun observeJobs(filter: JobFilter? = null): Flow<List<Job>>

    // Employer job management
    suspend fun getEmployerJobs(employerId: String): Result<List<Job>>
    suspend fun createJob(job: Job): Result<Job>
    suspend fun updateJob(job: Job): Result<Job>
    suspend fun deleteJob(jobId: String): Result<Unit>
    suspend fun toggleJobActive(jobId: String, isActive: Boolean): Result<Job>
    fun observeEmployerJobs(employerId: String): Flow<List<Job>>

    // Swipe functionality
    suspend fun getJobsForSwipe(userId: String, filter: JobFilter? = null): Result<List<Job>>
    suspend fun markJobAsSeen(userId: String, jobId: String)
    suspend fun markJobAsNotInterested(userId: String, jobId: String)

    // Local caching
    suspend fun cacheJobs(jobs: List<Job>)
    suspend fun getCachedJobs(): List<Job>
    suspend fun clearCache()

    // Suggested pay (when posting a job)
    suspend fun getSuggestedPay(category: String?, district: String?, state: String?): Result<PaySuggestion>

    // Smart feed: relevance ordering of open jobs for a worker (job_id → rank).
    suspend fun rankJobsForWorker(workerId: String, limit: Int = 100): Result<List<String>>
}

/** Thrown by [JobRepository.deleteJob] when the job has applicants and so cannot be deleted. */
class JobHasApplicantsException : Exception("This job has applicants and cannot be deleted")

/**
 * Suggested hourly pay range from the shared `suggest_pay` DB function, based
 * on actual paid rates for similar jobs. [p25]/[median]/[p75] are rupees/hour,
 * null when [scope] is "none" (no comparable data). [scope] reports how broad
 * the cohort was (category_district → category → district → global → none) and
 * [sampleCount] how many real jobs backed it — so the UI can be honest.
 */
data class PaySuggestion(
    val p25: Int? = null,
    val median: Int? = null,
    val p75: Int? = null,
    val sampleCount: Int = 0,
    val scope: String = "none"
) {
    val hasSuggestion: Boolean get() = scope != "none" && median != null
}
